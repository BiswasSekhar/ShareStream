import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/socket_service.dart';
import '../services/webrtc_service.dart';
import '../services/torrent_service.dart';

/// Central state management for room, streaming, and video calling
class RoomProvider extends ChangeNotifier {
  final SocketService _socket = SocketService();
  late final WebRTCService _webrtc;
  final TorrentService _torrent = TorrentService();

  // ─── State ───
  String? _roomCode;
  String _userName = 'User';
  bool _isHost = false;
  bool _inRoom = false;
  String? _error;
  String? _selectedFilePath;
  String? _selectedFileName;
  bool _isStreaming = false;
  double _downloadProgress = 0;
  bool _isProcessing = false;
  String _serverUrl = dotenv.env['SERVER_URL'] ?? 'http://localhost:3001';
  
  // Join approval state
  bool _joinPending = false;
  bool _joinApproved = false;
  bool _joinRejected = false;

  // Sync heartbeat
  Timer? _syncTimer;
  final Map<String, double> _viewerDrifts = {};
  static const double _maxDriftSeconds = 2.0;

  RoomProvider() {
    _webrtc = WebRTCService(_socket);

    // Listen for incoming magnet URIs from other participants
    _socket.onTorrentMagnet = _onTorrentMagnet;
    
    // Join approval callbacks
    _socket.onJoinRequest = _onJoinRequest;
    _socket.onJoinApproved = _onJoinApproved;
    _socket.onJoinRejected = _onJoinRejected;
    _socket.onJoinPending = _onJoinPending;

    // Sync callbacks
    _socket.onSyncCheck = _onSyncCheck;
    _socket.onSyncReport = _onSyncReport;
    _socket.onSyncCorrect = _onSyncCorrect;
  }

  // ─── Getters ───
  SocketService get socket => _socket;
  WebRTCService get webrtc => _webrtc;
  TorrentService get torrent => _torrent;
  String? get roomCode => _roomCode;
  String get userName => _userName;
  bool get isHost => _isHost;
  bool get inRoom => _inRoom;
  String? get error => _error;
  String? get selectedFilePath => _selectedFilePath;
  String? get selectedFileName => _selectedFileName;
  bool get isStreaming => _isStreaming;
  double get downloadProgress => _downloadProgress;
  bool get isProcessing => _isProcessing;
  String get serverUrl => _serverUrl;

  ValueNotifier<List<Participant>> get participants => _socket.participants;
  ValueNotifier<List<ChatMessage>> get messages => _socket.messages;
  ValueNotifier<bool> get connected => _socket.connected;
  
  // Join approval getters
  bool get joinPending => _joinPending;
  bool get joinApproved => _joinApproved;
  bool get joinRejected => _joinRejected;

  void setServerUrl(String url) {
    _serverUrl = url;
    notifyListeners();
  }

  void setUserName(String name) {
    _userName = name;
    notifyListeners();
  }

  /// Connect to server and create a new room
  Future<String> createRoom() async {
    _error = null;
    _isHost = true;
    notifyListeners();

    debugPrint('[room] createRoom() → connecting to $_serverUrl');
    _socket.connect(_serverUrl);

    // Wait for connection (polling transport through Cloudflare can take 3-5s)
    await Future.delayed(const Duration(milliseconds: 500));
    int retries = 0;
    while (!_socket.isConnected && retries < 20) {
      debugPrint('[room] Waiting for connection... attempt ${retries + 1}/20 (connected=${_socket.isConnected})');
      await Future.delayed(const Duration(milliseconds: 300));
      retries++;
    }

    if (!_socket.isConnected) {
      debugPrint('[room] ❌ Failed to connect after ${retries * 300 + 500}ms. Check that the server is running on $_serverUrl');
      _error = 'Could not connect to server at $_serverUrl';
      notifyListeners();
      return '';
    }

    debugPrint('[room] ✅ Connected — emitting create-room for user: $_userName');
    _socket.createRoom(name: _userName);

    // Wait for room-created event (Go server emits it as a separate event)
    int roomRetries = 0;
    while (_socket.currentRoom == null && roomRetries < 20) {
      if (roomRetries % 5 == 0) {
        debugPrint('[room] Waiting for room-created event... attempt ${roomRetries + 1}/20');
      }
      await Future.delayed(const Duration(milliseconds: 150));
      roomRetries++;
    }
    
    _roomCode = _socket.currentRoom;
    if (_roomCode == null || _roomCode!.isEmpty) {
      debugPrint('[room] ❌ No room-created event received after ${roomRetries * 150}ms. The server may be rejecting the event.');
      _error = 'Failed to create room — no response from server';
      notifyListeners();
      return '';
    }
    debugPrint('[room] ✅ Room created: $_roomCode');
    _inRoom = true;
    notifyListeners();
    return _roomCode ?? '';
  }

  /// Join an existing room
  Future<bool> joinRoom(String code) async {
    _error = null;
    _roomCode = code.toUpperCase().trim();
    _isHost = false;
    notifyListeners();

    _socket.connect(_serverUrl);

    await Future.delayed(const Duration(milliseconds: 500));
    int retries = 0;
    while (!_socket.isConnected && retries < 10) {
      await Future.delayed(const Duration(milliseconds: 300));
      retries++;
    }

    if (!_socket.isConnected) {
      _error = 'Could not connect to server';
      notifyListeners();
      return false;
    }

    _socket.joinRoom(_roomCode!, name: _userName);
    _inRoom = true;
    notifyListeners();
    return true;
  }

  /// Request to join a room (sends join request, waits for approval)
  Future<bool> requestJoin(String code) async {
    _error = null;
    _joinPending = false;
    _joinApproved = false;
    _joinRejected = false;
    _roomCode = code.toUpperCase().trim();
    _isHost = false;
    notifyListeners();

    _socket.connect(_serverUrl);

    await Future.delayed(const Duration(milliseconds: 500));
    int retries = 0;
    while (!_socket.isConnected && retries < 10) {
      await Future.delayed(const Duration(milliseconds: 300));
      retries++;
    }

    if (!_socket.isConnected) {
      _error = 'Could not connect to server';
      notifyListeners();
      return false;
    }

    _socket.joinRequest(_roomCode!, _userName);
    _inRoom = true;
    notifyListeners();
    return true;
  }

  /// Host approves a viewer join request
  void approveJoin(String participantId) {
    _socket.approveJoin(participantId);
  }

  /// Host rejects a viewer join request
  void rejectJoin(String participantId) {
    _socket.rejectJoin(participantId);
  }

  /// Viewer polls for join approval status
  void pollJoinStatus() {
    _socket.requestJoinApproval();
  }

  void _onJoinRequest(String participantId, String name) {
    debugPrint('[room] Join request from: $name ($participantId)');
    notifyListeners();
  }

  void _onJoinApproved(String participantId) {
    _joinPending = false;
    _joinApproved = true;
    _joinRejected = false;
    debugPrint('[room] Join approved - now joining room');
    // Actually join the room after approval
    if (_roomCode != null) {
      _socket.joinRoom(_roomCode!, name: _userName);
    }
    notifyListeners();
  }

  void _onJoinRejected() {
    _joinPending = false;
    _joinApproved = false;
    _joinRejected = true;
    _error = 'Join request was rejected by host';
    debugPrint('[room] Join rejected');
    notifyListeners();
  }

  void _onJoinPending() {
    _joinPending = true;
    _joinApproved = false;
    _joinRejected = false;
    debugPrint('[room] Join pending - waiting for approval');
    notifyListeners();
  }

  void resetJoinState() {
    _joinPending = false;
    _joinApproved = false;
    _joinRejected = false;
    notifyListeners();
  }

  void leaveRoom() {
    _stopSyncHeartbeat();
    _viewerDrifts.clear();
    _webrtc.stopCall();
    _torrent.stop();
    _socket.leaveRoom();
    _inRoom = false;
    _isHost = false;
    _roomCode = null;
    _selectedFilePath = null;
    _selectedFileName = null;
    _isStreaming = false;
    _downloadProgress = 0;
    _isProcessing = false;
    resetJoinState();
    notifyListeners();
  }

  // ─── Video Call ───
  Future<void> startCall() async {
    try {
      await _webrtc.startCall();
      notifyListeners();
    } catch (e) {
      _error = 'Could not start call: $e';
      notifyListeners();
    }
  }

  Future<void> endCall() async {
    await _webrtc.stopCall();
    notifyListeners();
  }

  // ─── Torrent Streaming ───

  /// Host: seed a local file, share magnet with room
  Future<String?> seedFile(String filePath, String fileName) async {
    _selectedFilePath = filePath;
    _selectedFileName = fileName;
    _isProcessing = true;
    _error = null;
    notifyListeners();

    // Only use torrent on desktop
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      _error = 'Torrent streaming only available on desktop';
      _isProcessing = false;
      notifyListeners();
      return null;
    }

    final serverUrl = await _torrent.seed(filePath);

    _isProcessing = false;
    if (serverUrl != null) {
      _isStreaming = true;
      if (_isHost) {
        _startSyncHeartbeat();
      }
      // Share magnet URI with other participants
      final magnet = _torrent.magnetUri.value;
      if (magnet != null) {
        // Validate magnet before sharing
        if (!magnet.startsWith('magnet:?') || !magnet.contains('xt=urn:btih:')) {
          debugPrint('[room] Invalid magnet URI generated, skipping share');
        } else {
          _socket.shareMagnet(magnet, 'direct', fileName);
        }
        _socket.emitMovieLoaded(fileName, 0);
      }
    } else {
      _error = _torrent.lastError.value ?? 'Failed to seed file';
    }
    notifyListeners();
    return serverUrl;
  }

  /// Viewer: receive magnet and start downloading
  void _onTorrentMagnet(String magnet, String streamPath) async {
    if (_isHost) return; // Host already has the file

    // Validate magnet URI
    if (!magnet.startsWith('magnet:?') || !magnet.contains('xt=urn:btih:')) {
      debugPrint('[room] Received invalid magnet URI, ignoring');
      _error = 'Received invalid magnet link';
      notifyListeners();
      return;
    }

    // Mobile viewers can't run local engine
    if (_torrent.isMobile) {
      debugPrint('[room] Mobile viewer — streaming not yet supported');
      _error = 'Mobile streaming coming soon';
      notifyListeners();
      return;
    }

    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      debugPrint('[room] Torrent streaming not available on this platform');
      return;
    }

    _isProcessing = true;
    _isStreaming = false;
    notifyListeners();

    try {
      final serverUrl = await _torrent.download(magnet);

      _isProcessing = false;
      if (serverUrl != null) {
        _isStreaming = true;
        _startSyncHeartbeat();
      } else {
        _error = _torrent.lastError.value ?? 'Failed to download torrent';
      }
    } catch (e) {
      _isProcessing = false;
      _error = 'Torrent download failed: $e';
      debugPrint('[room] Torrent download error: $e');
    }
    notifyListeners();
  }

  void setSelectedFile(String path, String name) {
    _selectedFilePath = path;
    _selectedFileName = name;
    notifyListeners();
  }

  void setStreaming(bool streaming) {
    _isStreaming = streaming;
    notifyListeners();
  }

  void setDownloadProgress(double progress) {
    _downloadProgress = progress;
    notifyListeners();
  }

  void setProcessing(bool processing) {
    _isProcessing = processing;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ─── Sync Heartbeat ───

  void _startSyncHeartbeat() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _triggerSyncCheck();
    });
    debugPrint('[room] Started sync heartbeat (15s interval)');
  }

  void _stopSyncHeartbeat() {
    _syncTimer?.cancel();
    _syncTimer = null;
    debugPrint('[room] Stopped sync heartbeat');
  }

  void _triggerSyncCheck() {
    if (_roomCode == null) return;
    _socket.syncCheck(_roomCode!);
  }

  void _onSyncCheck(int timestamp) {
    if (_roomCode == null) return;
    debugPrint('[room] Received sync-check from host, responding with report');
    _socket.syncReport(_roomCode!, 0, true, 0);
  }

  void _onSyncReport(String participantId, double playbackTime, bool playing) {
    if (!_isHost || _roomCode == null) return;
    final drift = playbackTime;
    _viewerDrifts[participantId] = drift;
    debugPrint('[room] Sync report from $participantId: drift=${drift.toStringAsFixed(2)}s');
    if (drift.abs() > _maxDriftSeconds) {
      debugPrint('[room] Correcting $participantId (drift: ${drift.toStringAsFixed(2)}s)');
      _socket.syncCorrect(participantId, 0, playing);
    }
  }

  void _onSyncCorrect(double time, bool playing, String actionId) {
    debugPrint('[room] Received sync-correct: time=$time, playing=$playing');
  }

  @override
  void dispose() {
    _stopSyncHeartbeat();
    _webrtc.dispose();
    _torrent.dispose();
    _socket.dispose();
    super.dispose();
  }
}
