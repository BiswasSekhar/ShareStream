import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:flutter_webrtc/flutter_webrtc.dart' show RTCVideoRenderer;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'socket_service.dart';

/// Manages WebRTC mesh connections for video calling.
/// Uses Perfect Negotiation pattern to handle glare (simultaneous offers).
///
/// KEY DESIGN:
/// - When a remote peer starts video, we auto-accept the connection
///   and receive their video WITHOUT starting our own camera.
/// - The user can optionally click "video call" to start their own
///   camera and transmit their video to all peers.
/// - Polite/impolite roles are assigned based on peer ID comparison to
///   handle negotiation collisions deterministically.
class WebRTCService {
  final SocketService _socket;

  final List<Map<String, dynamic>> _iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];

  webrtc.MediaStream? _localStream;
  bool _audioEnabled = true;
  bool _videoEnabled = true;

  final Map<String, webrtc.RTCPeerConnection> _peers = {};
  final Map<String, webrtc.MediaStream> _remoteStreams = {};
  
  // Perfect negotiation state per peer
  final Map<String, bool> _isPolite = {};
  final Map<String, bool> _makingOffer = {};
  final Map<String, List<Map<String, dynamic>>> _pendingCandidates = {};
  final Map<String, Timer> _connectionTimers = {};
  
  // Connection retry state
  final Map<String, int> _connectionAttempts = {};
  static const int _maxConnectionAttempts = 3;
  static const Duration _connectionTimeout = Duration(seconds: 15);

  /// Whether the LOCAL user has started their camera/mic
  final ValueNotifier<bool> isInCall = ValueNotifier(false);
  final ValueNotifier<bool> audioEnabled = ValueNotifier(true);
  final ValueNotifier<bool> videoEnabled = ValueNotifier(true);
  final ValueNotifier<webrtc.MediaStream?> localStream = ValueNotifier(null);
  final ValueNotifier<Map<String, webrtc.MediaStream>> remoteStreams = ValueNotifier({});

  WebRTCService(this._socket) {
    _loadTURNCredentials();
    _setupSignaling();
  }

  void _loadTURNCredentials() async {
    final turnUrl = dotenv.env['TURN_URL'];
    final turnUsername = dotenv.env['TURN_USERNAME'];
    final turnCredential = dotenv.env['TURN_CREDENTIAL'];

    if (turnUrl != null && turnUsername != null && turnCredential != null) {
      _iceServers.add({
        'urls': turnUrl,
        'username': turnUsername,
        'credential': turnCredential,
      });
      debugPrint('[webrtc] Added TURN server: $turnUrl');
    }
  }

  void _setupSignaling() {
    _socket.onStartWebRTC = _onStartWebRTC;
    _socket.onOffer = handleOffer;
    _socket.onAnswer = handleAnswer;
    _socket.onIceCandidate = handleIceCandidate;
    _socket.onPeerLeft = removePeer;
  }

  /// Called when a remote peer is ready for WebRTC.
  Future<void> _onStartWebRTC(String peerId, bool initiator) async {
    debugPrint('[webrtc] start-webrtc: peer=$peerId, initiator=$initiator');
    
    // If we already have a connection to this peer, ignore
    if (_peers.containsKey(peerId)) {
      debugPrint('[webrtc] Peer $peerId already exists, skipping');
      return;
    }
    
    await _createPeerConnection(peerId, initiator: initiator);
    
    // If we're the initiator, start the negotiation
    if (initiator) {
      await _initiateNegotiation(peerId);
    }
  }

  // ─── Start/Stop Local Camera ──────────────────────────────────────────

  /// Start the local camera and microphone, and signal readiness to peers.
  Future<void> startCall() async {
    try {
      _localStream = await webrtc.navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': {
          'width': {'ideal': 640},
          'height': {'ideal': 480},
          'frameRate': {'ideal': 24},
          'facingMode': 'user',
        },
      });

      _audioEnabled = true;
      _videoEnabled = true;
      localStream.value = _localStream;
      audioEnabled.value = true;
      videoEnabled.value = true;
      isInCall.value = true;

      // Add local tracks to any existing peer connections
      await _addLocalTracksToAllPeers();

      // Tell the server we're ready — triggers start-webrtc for other peers
      _socket.emit('ready-for-connection', {});

      debugPrint('[webrtc] call started, local stream ready');
    } catch (e) {
      debugPrint('[webrtc] getUserMedia error: $e');
      rethrow;
    }
  }

  /// Add local media tracks to all existing peer connections
  Future<void> _addLocalTracksToAllPeers() async {
    if (_localStream == null) return;

    for (final remoteId in _peers.keys) {
      await _addLocalTracksToPeer(remoteId);
    }
  }

  Future<void> _addLocalTracksToPeer(String remoteId) async {
    final pc = _peers[remoteId];
    if (pc == null || _localStream == null) return;
    
    try {
      // Check if tracks already added
      final senders = await pc.getSenders();
      if (senders.isNotEmpty) {
        debugPrint('[webrtc] Tracks already added to peer $remoteId');
        return;
      }
      
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
      debugPrint('[webrtc] Added local tracks to peer $remoteId');
      
      // The onnegotiationneeded handler will fire and create an offer
    } catch (e) {
      debugPrint('[webrtc] Warning: could not add tracks to peer $remoteId: $e');
    }
  }

  Future<void> stopCall() async {
    // Clear all timers
    for (final timer in _connectionTimers.values) {
      timer.cancel();
    }
    _connectionTimers.clear();
    _connectionAttempts.clear();

    // Close all peer connections
    for (final entry in _peers.entries) {
      await entry.value.close();
    }
    _peers.clear();
    _isPolite.clear();
    _makingOffer.clear();
    _pendingCandidates.clear();

    // Dispose remote streams
    for (final stream in _remoteStreams.values) {
      await stream.dispose();
    }
    _remoteStreams.clear();
    remoteStreams.value = {};

    // Stop local stream
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }
    localStream.value = null;
    isInCall.value = false;
    debugPrint('[webrtc] call stopped');
  }

  // ─── Audio/Video Controls ─────────────────────────────────────────────

  void toggleAudio() {
    if (_localStream == null) return;
    _audioEnabled = !_audioEnabled;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = _audioEnabled;
    }
    audioEnabled.value = _audioEnabled;
  }

  void toggleVideo() {
    if (_localStream == null) return;
    _videoEnabled = !_videoEnabled;
    for (final track in _localStream!.getVideoTracks()) {
      track.enabled = _videoEnabled;
    }
    videoEnabled.value = _videoEnabled;
  }

  // ─── Peer Connection Management ───────────────────────────────────────

  Future<void> _createPeerConnection(String remoteId, {bool initiator = false}) async {
    if (_peers.containsKey(remoteId)) {
      debugPrint('[webrtc] peer $remoteId already exists, skipping creation');
      return;
    }

    debugPrint('[webrtc] creating peer connection to $remoteId, initiator: $initiator');

    try {
      final config = <String, dynamic>{
        'iceServers': _iceServers,
        'sdpSemantics': 'unified-plan',
        'iceCandidatePoolSize': 10,
      };

      final pc = await webrtc.createPeerConnection(config);

      // Assign polite role based on peer ID comparison
      // The peer with lexicographically smaller ID is polite
      final myId = _socket.userId ?? '';
      _isPolite[remoteId] = myId.compareTo(remoteId) > 0;
      _makingOffer[remoteId] = false;
      _pendingCandidates[remoteId] = [];
      _connectionAttempts[remoteId] = 0;
      
      debugPrint('[webrtc] Peer $remoteId: I am ${_isPolite[remoteId]! ? "polite" : "impolite"} (myId: $myId, theirId: $remoteId)');

      // Add local tracks if we have them
      if (_localStream != null) {
        await _addLocalTracksToPeer(remoteId);
      }

      // Perfect negotiation: handle onnegotiationneeded
      pc.onRenegotiationNeeded = () async {
        debugPrint('[webrtc] onRenegotiationNeeded for $remoteId');
        await _initiateNegotiation(remoteId);
      };

      pc.onIceCandidate = (webrtc.RTCIceCandidate candidate) {
        _socket.emit('ice-candidate', {
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
          'to': remoteId,
        });
      };

      pc.onTrack = (webrtc.RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          debugPrint('[webrtc] ✅ received remote stream from $remoteId, track: ${event.track.kind}');
          _remoteStreams[remoteId] = event.streams[0];
          remoteStreams.value = Map.from(_remoteStreams);
          
          // Cancel connection timer since we got a track
          _connectionTimers[remoteId]?.cancel();
          _connectionTimers.remove(remoteId);
        }
      };

      pc.onConnectionState = (webrtc.RTCPeerConnectionState state) {
        debugPrint('[webrtc] connection state with $remoteId: $state');
        
        switch (state) {
          case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            debugPrint('[webrtc] ✅ Connection established with $remoteId');
            _connectionTimers[remoteId]?.cancel();
            _connectionTimers.remove(remoteId);
            _connectionAttempts[remoteId] = 0;
            break;
            
          case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed:
            debugPrint('[webrtc] ❌ Connection failed with $remoteId');
            _handleConnectionFailure(remoteId);
            break;
            
          case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
            debugPrint('[webrtc] ⚠️ Connection disconnected with $remoteId');
            // Wait a bit to see if it recovers
            Future.delayed(const Duration(seconds: 5), () {
              final currentState = pc.connectionState;
              if (currentState == webrtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
                  currentState == webrtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
                _handleConnectionFailure(remoteId);
              }
            });
            break;
            
          default:
            break;
        }
      };

      pc.onIceConnectionState = (webrtc.RTCIceConnectionState state) {
        debugPrint('[webrtc] ICE connection state with $remoteId: $state');
      };

      _peers[remoteId] = pc;
      
      // Start connection timeout timer
      _startConnectionTimer(remoteId);
      
    } catch (e) {
      debugPrint('[webrtc] _createPeerConnection error for $remoteId: $e');
    }
  }

  void _startConnectionTimer(String remoteId) {
    _connectionTimers[remoteId]?.cancel();
    _connectionTimers[remoteId] = Timer(_connectionTimeout, () {
      final pc = _peers[remoteId];
      if (pc == null) return;
      
      final state = pc.connectionState;
      if (state != webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
          state != webrtc.RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        debugPrint('[webrtc] Connection timeout for $remoteId');
        _handleConnectionFailure(remoteId);
      }
    });
  }

  Future<void> _initiateNegotiation(String remoteId) async {
    final pc = _peers[remoteId];
    if (pc == null) return;
    
    // Don't start new negotiation if one is in progress
    if (_makingOffer[remoteId] == true) {
      debugPrint('[webrtc] Already making offer to $remoteId, skipping');
      return;
    }
    
    // Check signaling state — treat null as stable (freshly created peer)
    final signalingState = pc.signalingState;
    if (signalingState != null && signalingState != webrtc.RTCSignalingState.RTCSignalingStateStable) {
      debugPrint('[webrtc] Signaling state not stable ($signalingState), deferring negotiation');
      return;
    }
    
    try {
      _makingOffer[remoteId] = true;
      debugPrint('[webrtc] Creating offer for $remoteId');
      
      final offer = await pc.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      
      await pc.setLocalDescription(offer);
      
      _socket.emit('offer', {
        'offer': offer.toMap(),
        'to': remoteId,
      });
      
      debugPrint('[webrtc] Sent offer to $remoteId');
    } catch (e) {
      debugPrint('[webrtc] Error creating offer for $remoteId: $e');
    } finally {
      _makingOffer[remoteId] = false;
    }
  }

  // ─── Perfect Negotiation: Handle Incoming Offer ───────────────────────

  Future<void> handleOffer(String fromId, Map<String, dynamic> offerMap) async {
    debugPrint('[webrtc] Received offer from $fromId');
    
    try {
      // Create peer connection if it doesn't exist
      if (!_peers.containsKey(fromId)) {
        await _createPeerConnection(fromId, initiator: false);
      }

      final pc = _peers[fromId];
      if (pc == null) {
        debugPrint('[webrtc] handleOffer: peer $fromId not found after creation');
        return;
      }

      final polite = _isPolite[fromId] ?? true;
      final makingOffer = _makingOffer[fromId] ?? false;
      
      // Check for offer collision (glare)
      // Treat null signaling state as stable (freshly created peer)
      final signalingState = pc.signalingState;
      final isStable = signalingState == null || signalingState == webrtc.RTCSignalingState.RTCSignalingStateStable;
      final offerCollision = makingOffer || !isStable;

      if (offerCollision) {
        if (!polite) {
          // I'm impolite, ignore the incoming offer
          debugPrint('[webrtc] Ignoring colliding offer from $fromId (I am impolite)');
          return;
        }
        // I'm polite, rollback my offer and accept theirs
        debugPrint('[webrtc] Rolling back to accept offer from $fromId (I am polite)');
        
        // Stop making our offer
        _makingOffer[fromId] = false;
        
        // Rollback: create a rollback description
        try {
          final rollback = webrtc.RTCSessionDescription('', 'rollback');
          await pc.setLocalDescription(rollback);
        } catch (e) {
          debugPrint('[webrtc] Rollback failed: $e');
        }
      }

      // Apply the remote offer
      final offer = webrtc.RTCSessionDescription(offerMap['sdp'], offerMap['type']);
      await pc.setRemoteDescription(offer);
      debugPrint('[webrtc] Set remote description (offer) from $fromId');

      // Apply any pending ICE candidates
      await _applyPendingCandidates(fromId);

      // Create and send answer
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      _socket.emit('answer', {
        'answer': answer.toMap(),
        'to': fromId,
      });
      debugPrint('[webrtc] Sent answer to $fromId');
      
    } catch (e, stackTrace) {
      debugPrint('[webrtc] handleOffer error from $fromId: $e');
      debugPrint('[webrtc] Stack trace: $stackTrace');
    }
  }

  Future<void> handleAnswer(String fromId, Map<String, dynamic> answerMap) async {
    debugPrint('[webrtc] Received answer from $fromId');
    
    try {
      final pc = _peers[fromId];
      if (pc == null) {
        debugPrint('[webrtc] handleAnswer: peer $fromId not found');
        return;
      }

      final answer = webrtc.RTCSessionDescription(answerMap['sdp'], answerMap['type']);
      await pc.setRemoteDescription(answer);
      debugPrint('[webrtc] ✅ Set remote answer from $fromId — connection establishing');
      
      // Apply any pending ICE candidates
      await _applyPendingCandidates(fromId);
      
    } catch (e) {
      debugPrint('[webrtc] handleAnswer error from $fromId: $e');
    }
  }

  Future<void> handleIceCandidate(String fromId, Map<String, dynamic> candidateMap) async {
    try {
      final pc = _peers[fromId];
      
      // If we don't have a peer connection yet, queue the candidate
      if (pc == null) {
        debugPrint('[webrtc] Queuing ICE candidate from $fromId (no peer yet)');
        _pendingCandidates.putIfAbsent(fromId, () => []).add(candidateMap);
        return;
      }
      
      // If we don't have a remote description yet, queue the candidate
      final remoteDesc = await pc.getRemoteDescription();
      if (remoteDesc == null) {
        debugPrint('[webrtc] Queuing ICE candidate from $fromId (no remote desc yet)');
        _pendingCandidates.putIfAbsent(fromId, () => []).add(candidateMap);
        return;
      }

      // Apply the candidate immediately
      await _applyIceCandidate(pc, candidateMap);
      
    } catch (e) {
      debugPrint('[webrtc] handleIceCandidate error from $fromId: $e');
    }
  }

  Future<void> _applyIceCandidate(webrtc.RTCPeerConnection pc, Map<String, dynamic> candidateMap) async {
    try {
      final candidate = webrtc.RTCIceCandidate(
        candidateMap['candidate'],
        candidateMap['sdpMid'],
        candidateMap['sdpMLineIndex'],
      );
      await pc.addCandidate(candidate);
    } catch (e) {
      debugPrint('[webrtc] Error adding ICE candidate: $e');
    }
  }

  Future<void> _applyPendingCandidates(String remoteId) async {
    final pc = _peers[remoteId];
    if (pc == null) return;
    
    final candidates = _pendingCandidates[remoteId];
    if (candidates == null || candidates.isEmpty) return;
    
    debugPrint('[webrtc] Applying ${candidates.length} pending ICE candidates for $remoteId');
    
    for (final candidate in candidates) {
      await _applyIceCandidate(pc, candidate);
    }
    
    candidates.clear();
  }

  // ─── Connection Recovery ──────────────────────────────────────────────

  Future<void> _handleConnectionFailure(String remoteId) async {
    final attempts = _connectionAttempts[remoteId] ?? 0;
    
    if (attempts >= _maxConnectionAttempts) {
      debugPrint('[webrtc] Max connection attempts reached for $remoteId, removing peer');
      await removePeer(remoteId);
      return;
    }
    
    _connectionAttempts[remoteId] = attempts + 1;
    debugPrint('[webrtc] Attempting ICE restart for $remoteId (attempt ${attempts + 1}/$_maxConnectionAttempts)');
    
    final pc = _peers[remoteId];
    if (pc == null) return;
    
    try {
      // Create offer with ICE restart
      final offer = await pc.createOffer({
        'iceRestart': true,
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      
      await pc.setLocalDescription(offer);
      
      _socket.emit('offer', {
        'offer': offer.toMap(),
        'to': remoteId,
      });
      
      debugPrint('[webrtc] Sent ICE restart offer to $remoteId');
      
      // Restart connection timer
      _startConnectionTimer(remoteId);
      
    } catch (e) {
      debugPrint('[webrtc] ICE restart failed for $remoteId: $e');
      await removePeer(remoteId);
    }
  }

  Future<void> removePeer(String remoteId) async {
    debugPrint('[webrtc] Removing peer $remoteId');
    
    // Cancel timers
    _connectionTimers[remoteId]?.cancel();
    _connectionTimers.remove(remoteId);
    
    // Close peer connection
    final pc = _peers.remove(remoteId);
    if (pc != null) {
      await pc.close();
    }
    
    // Clean up state
    _isPolite.remove(remoteId);
    _makingOffer.remove(remoteId);
    _pendingCandidates.remove(remoteId);
    _connectionAttempts.remove(remoteId);
    
    // Dispose and remove remote stream
    final stream = _remoteStreams.remove(remoteId);
    if (stream != null) {
      await stream.dispose();
    }
    
    remoteStreams.value = Map.from(_remoteStreams);
    debugPrint('[webrtc] Removed peer $remoteId');
  }

  void addTurnServer(String url, String username, String credential) {
    _iceServers.add({
      'urls': url,
      'username': username,
      'credential': credential,
    });
    debugPrint('[webrtc] Added TURN server: $url');
  }

  RTCVideoRenderer createRenderer() => RTCVideoRenderer();

  int get peerCount => _peers.length;

  Future<void> dispose() async {
    await stopCall();
    _socket.onStartWebRTC = null;
    _socket.onOffer = null;
    _socket.onAnswer = null;
    _socket.onIceCandidate = null;
    _socket.onPeerLeft = null;
    isInCall.dispose();
    audioEnabled.dispose();
    videoEnabled.dispose();
    localStream.dispose();
    remoteStreams.dispose();
  }
}
