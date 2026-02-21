import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:flutter_webrtc/flutter_webrtc.dart' show RTCVideoRenderer;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'socket_service.dart';

/// Manages WebRTC mesh connections for video calling.
/// Each participant maintains a peer connection to every other participant.
///
/// KEY DESIGN:
/// - When a remote peer starts video, we auto-accept the connection
///   and receive their video WITHOUT starting our own camera.
/// - The user can optionally click "video call" to start their own
///   camera and transmit their video to all peers.
class WebRTCService {
  final SocketService _socket;

  List<Map<String, dynamic>> _iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];

  webrtc.MediaStream? _localStream;
  bool _audioEnabled = true;
  bool _videoEnabled = true;

  final Map<String, webrtc.RTCPeerConnection> _peers = {};
  final Map<String, webrtc.MediaStream> _remoteStreams = {};

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
  /// ALWAYS create the peer connection — even if local user hasn't started
  /// their camera. This allows receiving remote video automatically.
  void _onStartWebRTC(String peerId, bool initiator) {
    debugPrint('[webrtc] start-webrtc: creating peer to $peerId (initiator=$initiator)');
    _createPeerConnection(peerId, initiator: initiator);
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
          'width': {'ideal': 320},
          'height': {'ideal': 240},
          'frameRate': {'ideal': 15},
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
      // (peers created before we had local media)
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
  /// (for connections that were created before we had local media).
  Future<void> _addLocalTracksToAllPeers() async {
    if (_localStream == null) return;

    for (final entry in _peers.entries) {
      final remoteId = entry.key;
      final pc = entry.value;
      try {
        // Check if tracks already added by seeing if senders exist
        final senders = await pc.getSenders();
        if (senders.isEmpty) {
          for (final track in _localStream!.getTracks()) {
            await pc.addTrack(track, _localStream!);
          }
          debugPrint('[webrtc] Added local tracks to existing peer $remoteId');

          // If we were the non-initiator peer, we need to renegotiate
          // by creating a new offer
          final offer = await pc.createOffer();
          await pc.setLocalDescription(offer);
          _socket.emit('offer', {
            'offer': offer.toMap(),
            'to': remoteId,
          });
          debugPrint('[webrtc] Sent renegotiation offer to $remoteId');
        }
      } catch (e) {
        debugPrint('[webrtc] Warning: could not add tracks to peer $remoteId: $e');
      }
    }
  }

  Future<void> stopCall() async {
    for (final entry in _peers.entries) {
      await entry.value.close();
    }
    _peers.clear();

    for (final stream in _remoteStreams.values) {
      await stream.dispose();
    }
    _remoteStreams.clear();
    remoteStreams.value = {};

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
      debugPrint('[webrtc] peer $remoteId already exists, skipping');
      return;
    }

    debugPrint('[webrtc] creating peer connection to $remoteId, initiator: $initiator');

    try {
      final config = <String, dynamic>{
        'iceServers': _iceServers,
        'sdpSemantics': 'unified-plan',
      };

      final pc = await webrtc.createPeerConnection(config);

      // Add local tracks if we have them (user has already started their camera)
      if (_localStream != null) {
        try {
          for (final track in _localStream!.getTracks()) {
            await pc.addTrack(track, _localStream!);
          }
          debugPrint('[webrtc] Added local tracks to peer $remoteId');
        } catch (e) {
          debugPrint('[webrtc] Warning: addTrack failed, trying addStream: $e');
          try {
            await pc.addStream(_localStream!);
          } catch (e2) {
            debugPrint('[webrtc] Warning: addStream also failed: $e2');
          }
        }
      } else {
        debugPrint('[webrtc] No local stream yet — receive-only peer for $remoteId');
      }

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
          debugPrint('[webrtc] ✅ received remote stream from $remoteId');
          _remoteStreams[remoteId] = event.streams[0];
          remoteStreams.value = Map.from(_remoteStreams);
        }
      };

      pc.onConnectionState = (webrtc.RTCPeerConnectionState state) {
        debugPrint('[webrtc] connection state with $remoteId: $state');
        if (state == webrtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == webrtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          removePeer(remoteId);
        }
      };

      _peers[remoteId] = pc;

      if (initiator) {
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        _socket.emit('offer', {
          'offer': offer.toMap(),
          'to': remoteId,
        });
        debugPrint('[webrtc] sent offer to $remoteId');
      }
    } catch (e) {
      debugPrint('[webrtc] _createPeerConnection error for $remoteId: $e');
    }
  }

  /// Handle an incoming offer — ALWAYS accept (even without local camera).
  Future<void> handleOffer(String fromId, Map<String, dynamic> offerMap) async {
    try {
      if (!_peers.containsKey(fromId)) {
        await _createPeerConnection(fromId, initiator: false);
      }

      final pc = _peers[fromId];
      if (pc == null) {
        debugPrint('[webrtc] handleOffer: peer $fromId not found after creation');
        return;
      }

      final offer = webrtc.RTCSessionDescription(offerMap['sdp'], offerMap['type']);
      await pc.setRemoteDescription(offer);

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      _socket.emit('answer', {
        'answer': answer.toMap(),
        'to': fromId,
      });
      debugPrint('[webrtc] sent answer to $fromId');
    } catch (e) {
      debugPrint('[webrtc] handleOffer error from $fromId: $e');
    }
  }

  Future<void> handleAnswer(String fromId, Map<String, dynamic> answerMap) async {
    try {
      final pc = _peers[fromId];
      if (pc == null) return;

      final answer = webrtc.RTCSessionDescription(answerMap['sdp'], answerMap['type']);
      await pc.setRemoteDescription(answer);
      debugPrint('[webrtc] ✅ set remote answer from $fromId — connection established');
    } catch (e) {
      debugPrint('[webrtc] handleAnswer error from $fromId: $e');
    }
  }

  Future<void> handleIceCandidate(String fromId, Map<String, dynamic> candidateMap) async {
    try {
      final pc = _peers[fromId];
      if (pc == null) return;

      final candidate = webrtc.RTCIceCandidate(
        candidateMap['candidate'],
        candidateMap['sdpMid'],
        candidateMap['sdpMLineIndex'],
      );
      await pc.addCandidate(candidate);
    } catch (e) {
      debugPrint('[webrtc] handleIceCandidate error from $fromId: $e');
    }
  }

  Future<void> removePeer(String remoteId) async {
    final pc = _peers.remove(remoteId);
    if (pc != null) {
      await pc.close();
    }
    final stream = _remoteStreams.remove(remoteId);
    if (stream != null) {
      await stream.dispose();
    }
    remoteStreams.value = Map.from(_remoteStreams);
    debugPrint('[webrtc] removed peer $remoteId');
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
