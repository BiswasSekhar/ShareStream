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

  RoomProvider() {
    _webrtc = WebRTCService(_socket);

    // Listen for incoming magnet URIs from other participants
    _socket.onTorrentMagnet = _onTorrentMagnet;
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

    _socket.connect(_serverUrl);

    // Wait for connection
    await Future.delayed(const Duration(milliseconds: 500));
    int retries = 0;
    while (!_socket.isConnected && retries < 10) {
      await Future.delayed(const Duration(milliseconds: 300));
      retries++;
    }

    if (!_socket.isConnected) {
      _error = 'Could not connect to server';
      notifyListeners();
      return '';
    }

    _socket.createRoom(name: _userName);

    // Wait for room code to be assigned
    await Future.delayed(const Duration(milliseconds: 500));
    _roomCode = _socket.currentRoom;
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

  void leaveRoom() {
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
      // Share magnet URI with other participants
      final magnet = _torrent.magnetUri.value;
      if (magnet != null) {
        _socket.shareMagnet(magnet, 'direct', fileName);
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

    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      debugPrint('[room] Torrent streaming not available on this platform');
      return;
    }

    _isProcessing = true;
    _isStreaming = false;
    notifyListeners();

    final serverUrl = await _torrent.download(magnet);

    _isProcessing = false;
    if (serverUrl != null) {
      _isStreaming = true;
    } else {
      _error = _torrent.lastError.value ?? 'Failed to download torrent';
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

  @override
  void dispose() {
    _webrtc.dispose();
    _torrent.dispose();
    _socket.dispose();
    super.dispose();
  }
}
