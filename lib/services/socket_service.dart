import 'dart:ui';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter/foundation.dart';

/// Socket.IO service for room management, playback sync, and WebRTC signaling.
/// Connects to the ShareStream signaling server.
class SocketService {
  io.Socket? _socket;
  String? _currentRoom;
  String? _userId;
  String? _participantId;
  bool _isHost = false;

  final ValueNotifier<bool> connected = ValueNotifier(false);
  final ValueNotifier<List<Participant>> participants = ValueNotifier([]);
  final ValueNotifier<List<ChatMessage>> messages = ValueNotifier([]);
  final ValueNotifier<String?> magnetUri = ValueNotifier(null);
  final ValueNotifier<String?> streamPath = ValueNotifier(null);
  final ValueNotifier<String?> movieName = ValueNotifier(null);

  // Playback sync callbacks
  void Function(double time)? onSeekRequested;
  void Function(bool playing)? onPlayPauseRequested;
  void Function(String magnet, String path)? onTorrentMagnet;

  // Sync callbacks
  void Function(int timestamp)? onSyncCheck;
  void Function(String participantId, double time, bool playing)? onSyncReport;
  void Function(double time, bool playing, String actionId)? onSyncCorrect;
  void Function(double time, bool playing)? onSyncUpdate;

  // Join approval callbacks
  void Function(String participantId, String name)? onJoinRequest;
  void Function(String participantId)? onJoinApproved;
  void Function()? onJoinRejected;
  void Function()? onJoinPending;

  // Playback readiness callbacks
  void Function(int count)? onReadyCountUpdate;
  void Function()? onStartPlayback;

  // WebRTC signaling callbacks
  void Function(String peerId, bool initiator)? onStartWebRTC;
  void Function(String fromId, Map<String, dynamic> offer)? onOffer;
  void Function(String fromId, Map<String, dynamic> answer)? onAnswer;
  void Function(String fromId, Map<String, dynamic> candidate)? onIceCandidate;
  void Function(String peerId)? onPeerLeft;

  String? get currentRoom => _currentRoom;
  String? get userId => _userId;
  bool get isHost => _isHost;
  bool get isConnected => connected.value;

  void connect(String serverUrl) {
    // If already connected to a different URL, disconnect first
    if (_socket != null) {
      debugPrint('[socket] Cleaning up previous connection before connecting to: $serverUrl');
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      connected.value = false;
    }
    
    debugPrint('[socket] Connecting to: $serverUrl');
    debugPrint('[socket] Transport: websocket');
    
    _socket = io.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'reconnection': true,
      'reconnectionDelay': 1000,
      'reconnectionAttempts': 10,
      'timeout': 20000,
    });

    _socket!.onConnect((_) {
      debugPrint('[socket] ✅ Connected! Socket ID: ${_socket!.id}');
      _userId = _socket!.id;
      connected.value = true;
    });

    _socket!.onDisconnect((reason) {
      debugPrint('[socket] ❌ Disconnected. Reason: $reason');
      connected.value = false;
    });

    _socket!.on('connect_error', (err) {
      debugPrint('[socket] ❌ Connection error: $err');
      debugPrint('[socket]    → Make sure signal server is running on $serverUrl');
      connected.value = false;
    });

    _socket!.on('connect_timeout', (_) {
      debugPrint('[socket] ❌ Connection timed out to $serverUrl');
      connected.value = false;
    });

    _socket!.onReconnect((_) {
      debugPrint('[socket] Reconnected after disconnect');
      connected.value = true;
      if (_currentRoom != null) {
        debugPrint('[socket] Re-joining room: $_currentRoom');
        joinRoom(_currentRoom!, name: 'Reconnecting');
      }
    });

    _socket!.onReconnectAttempt((attempt) {
      debugPrint('[socket] Reconnect attempt #$attempt to $serverUrl');
    });

    _socket!.onReconnectFailed((_) {
      debugPrint('[socket] ❌ Reconnection failed after all attempts to $serverUrl');
    });

    _socket!.onReconnectError((err) {
      debugPrint('[socket] Reconnect error: $err');
    });

    // Participant Events
    _socket!.on('participant-list', (data) {
      if (data['participants'] is List) {
        participants.value = (data['participants'] as List)
            .map((p) => Participant.fromMap(p))
            .toList();
      }
    });

    _socket!.on('participant-joined', (data) {
      debugPrint('[socket] Participant joined: ${data['name']}');
    });

    _socket!.on('participant-left', (data) {
      debugPrint('[socket] Participant left: ${data['id']}');
      final leftId = data['id'] as String?;
      if (leftId != null) {
        onPeerLeft?.call(leftId);
      }
    });

    // WebRTC Signaling
    _socket!.on('start-webrtc', (data) {
      final peerId = data['peerId'] as String?;
      final initiator = data['initiator'] as bool? ?? false;
      if (peerId != null) {
        debugPrint('[socket] start-webrtc: peer=$peerId, initiator=$initiator');
        onStartWebRTC?.call(peerId, initiator);
      }
    });

    _socket!.on('offer', (data) {
      final from = data['from'] as String?;
      final offer = data['offer'];
      if (from != null && offer != null) {
        onOffer?.call(from, Map<String, dynamic>.from(offer));
      }
    });

    _socket!.on('answer', (data) {
      final from = data['from'] as String?;
      final answer = data['answer'];
      if (from != null && answer != null) {
        onAnswer?.call(from, Map<String, dynamic>.from(answer));
      }
    });

    _socket!.on('ice-candidate', (data) {
      final from = data['from'] as String?;
      final candidate = data['candidate'];
      if (from != null && candidate != null) {
        onIceCandidate?.call(from, Map<String, dynamic>.from(candidate));
      }
    });

    // Torrent / Stream Events
    _socket!.on('torrent-magnet', (data) {
      debugPrint('[socket] Received torrent magnet');
      magnetUri.value = data['magnetURI'];
      streamPath.value = data['streamPath'] ?? 'direct';
      movieName.value = data['name'];
      onTorrentMagnet?.call(
        data['magnetURI'] ?? '',
        data['streamPath'] ?? 'direct',
      );
    });

    _socket!.on('movie-loaded', (data) {
      debugPrint('[socket] Movie loaded: ${data['name']}');
      movieName.value = data['name'];
    });

    _socket!.on('room-mode', (data) {
      debugPrint('[socket] Room mode: ${data['mode']}');
    });

    // Playback Sync Events
    _socket!.on('sync-play', (data) {
      final time = (data['time'] as num?)?.toDouble();
      onPlayPauseRequested?.call(true);
      if (time != null) onSeekRequested?.call(time);
    });

    _socket!.on('sync-pause', (data) {
      final time = (data['time'] as num?)?.toDouble();
      onPlayPauseRequested?.call(false);
      if (time != null) onSeekRequested?.call(time);
    });

    _socket!.on('sync-seek', (data) {
      final time = (data['time'] as num?)?.toDouble();
      if (time != null) onSeekRequested?.call(time);
    });

    _socket!.on('playback-snapshot', (data) {
      final playback = data['playback'];
      if (playback != null) {
        final time = (playback['time'] as num?)?.toDouble();
        final type = playback['type'] as String?;
        if (time != null) onSeekRequested?.call(time);
        if (type == 'play') onPlayPauseRequested?.call(true);
        if (type == 'pause') onPlayPauseRequested?.call(false);
      }
    });

    // New Sync Events
    _socket!.on('sync-check', (data) {
      final timestamp = (data['timestamp'] as num?)?.toInt();
      if (timestamp != null) {
        onSyncCheck?.call(timestamp);
      }
    });

    _socket!.on('sync-report', (data) {
      final participantId = data['participantId'] as String?;
      final playbackTime = (data['playbackTime'] as num?)?.toDouble();
      final playing = data['playing'] as bool? ?? false;
      if (participantId != null && playbackTime != null) {
        onSyncReport?.call(participantId, playbackTime, playing);
      }
    });

    _socket!.on('sync-correct', (data) {
      final playbackTime = (data['playbackTime'] as num?)?.toDouble();
      final playing = data['playing'] as bool? ?? false;
      final actionId = data['actionId'] as String?;
      if (playbackTime != null) {
        onSyncCorrect?.call(playbackTime, playing, actionId ?? '');
      }
    });

    _socket!.on('sync-update', (data) {
      final time = (data['time'] as num?)?.toDouble();
      final playing = data['playing'] as bool? ?? false;
      if (time != null) {
        onSyncUpdate?.call(time, playing);
      }
    });

    // Chat Events - with deduplication
    _socket!.on('chat-message', (data) {
      final msgId = data['id'] ?? '';
      final senderId = data['senderId'] ?? '';
      
      // Check for duplicate message
      final isDuplicate = messages.value.any((m) => m.id == msgId);
      if (isDuplicate) {
        debugPrint('[socket] Duplicate chat message ignored: $msgId');
        return;
      }
      
      final msg = ChatMessage(
        id: msgId,
        senderId: senderId,
        senderName: data['sender'] ?? 'Unknown',
        senderRole: data['senderRole'] ?? 'viewer',
        text: data['text'] ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (data['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        ),
        isMe: senderId == _userId,
      );
      messages.value = [...messages.value, msg];
    });

    _socket!.on('error', (data) {
      debugPrint('[socket] Error: $data');
    });

    // Join Approval Events
    _socket!.on('join-request', (data) {
      final participantId = data['participantId'] as String?;
      final name = data['name'] as String? ?? 'Unknown';
      if (participantId != null) {
        debugPrint('[socket] Join request from: $name ($participantId)');
        onJoinRequest?.call(participantId, name);
      }
    });

    _socket!.on('join-approved', (data) {
      final participantId = data['participantId'] as String?;
      debugPrint('[socket] Join approved for: $participantId');
      onJoinApproved?.call(participantId ?? '');
    });

    _socket!.on('join-rejected', (data) {
      debugPrint('[socket] Join rejected');
      onJoinRejected?.call();
    });

    _socket!.on('join-pending', (data) {
      debugPrint('[socket] Join pending - waiting for approval');
      onJoinPending?.call();
    });

    // Playback Readiness Events
    _socket!.on('ready-count-update', (data) {
      final count = (data['readyCount'] as num?)?.toInt() ?? 0;
      debugPrint('[socket] Ready count update: $count');
      onReadyCountUpdate?.call(count);
    });

    _socket!.on('playback-started', (data) {
      debugPrint('[socket] Playback started by host');
      onStartPlayback?.call();
    });

    // Room creation/join responses (Go server emits these as events, not acks)
    _socket!.on('room-created', (data) {
      debugPrint('[socket] room-created event: $data');
      if (data != null && data['success'] == true) {
        _currentRoom = data['room']?['code'];
        _isHost = true;
        debugPrint('[socket] Created room: $_currentRoom');
      } else {
        debugPrint('[socket] Create room failed: $data');
      }
    });

    _socket!.on('room-joined', (data) {
      debugPrint('[socket] room-joined event: $data');
      if (data != null && data['success'] == true) {
        _currentRoom = data['room']?['code'];
        final role = data['room']?['role'] ?? 'viewer';
        _isHost = role == 'host';
        debugPrint('[socket] Joined room: $_currentRoom as $role');
      } else {
        debugPrint('[socket] Join failed: ${data?['error']}');
      }
    });
  }

  // Generic emit
  void emit(String event, Map<String, dynamic> data) {
    _socket?.emit(event, data);
  }

  // Room Actions
  void createRoom({String? name, String? requestedCode}) {
    _isHost = true;
    _participantId = _generateParticipantId();
    _socket?.emit('create-room', {
      'participantId': _participantId,
      'name': name ?? 'Host',
      'capabilities': {'nativePlayback': true},
      'requestedCode': requestedCode,
    });
  }

  void joinRoom(String code, {String? name}) {
    _isHost = false;
    _participantId ??= _generateParticipantId();
    final normalizedCode = code.trim().toUpperCase();
    _socket?.emit('join-room', {
      'code': normalizedCode,
      'participantId': _participantId,
      'name': name ?? 'Guest',
      'capabilities': {'nativePlayback': true},
    });
  }

  void joinRequest(String code, String name) {
    _participantId ??= _generateParticipantId();
    final normalizedCode = code.trim().toUpperCase();
    _socket?.emit('join-request', {
      'code': normalizedCode,
      'participantId': _participantId,
      'name': name,
    });
  }

  void approveJoin(String participantId) {
    _socket?.emit('approve-join', {
      'participantId': participantId,
    });
    debugPrint('[socket] Approved join for: $participantId');
  }

  void rejectJoin(String participantId) {
    _socket?.emit('reject-join', {
      'participantId': participantId,
    });
    debugPrint('[socket] Rejected join for: $participantId');
  }

  void requestJoinApproval() {
    if (_currentRoom == null || _participantId == null) return;
    _socket?.emit('request-join-status', {
      'roomCode': _currentRoom,
      'participantId': _participantId,
    });
  }

  void leaveRoom() {
    if (_currentRoom != null) {
      _socket?.emit('leave-room');
      _currentRoom = null;
      _isHost = false;
      participants.value = [];
      messages.value = [];
      magnetUri.value = null;
      streamPath.value = null;
      movieName.value = null;
    }
  }

  // Stream Actions
  void shareMagnet(String magnet, String path, String name) {
    _socket?.emit('torrent-magnet', {
      'magnetURI': magnet,
      'streamPath': path,
      'name': name,
    });
  }

  void emitMovieLoaded(String name, double duration) {
    _socket?.emit('movie-loaded', {
      'name': name,
      'duration': duration,
    });
  }

  // Playback Sync
  void syncPlay(double time) {
    _socket?.emit('sync-play', {
      'time': time,
      'actionId': DateTime.now().millisecondsSinceEpoch.toString(),
    });
  }

  void syncPause(double time) {
    _socket?.emit('sync-pause', {
      'time': time,
      'actionId': DateTime.now().millisecondsSinceEpoch.toString(),
    });
  }

  void syncSeek(double time) {
    _socket?.emit('sync-seek', {
      'time': time,
      'actionId': DateTime.now().millisecondsSinceEpoch.toString(),
    });
  }

  // Sync Actions (New)
  void syncCheck(String code) {
    _socket?.emit('sync-check', {
      'code': code,
    });
  }

  void syncReport(String code, double time, bool playing, double buffered) {
    _socket?.emit('sync-report', {
      'code': code,
      'time': time,
      'playing': playing,
      'buffered': buffered,
    });
  }

  void syncCorrect(String participantId, double time, bool playing) {
    _socket?.emit('sync-correct', {
      'participantId': participantId,
      'time': time,
      'playing': playing,
    });
  }

  void syncUpdate(String code, double time, bool playing) {
    _socket?.emit('sync-update', {
      'code': code,
      'time': time,
      'playing': playing,
    });
  }

  // Chat
  void sendMessage(String text) {
    // Generate client-side message ID for deduplication
    final msgId = '${_userId}_${DateTime.now().millisecondsSinceEpoch}';
    _socket?.emit('chat-message', {
      'text': text,
      'clientId': msgId,
    });
  }

  // Playback Readiness
  void readyToStart(String code) {
    _socket?.emit('ready-to-start', {'code': code});
    debugPrint('[socket] Sent ready-to-start for room: $code');
  }

  void startPlayback(String code) {
    _socket?.emit('start-playback', {'code': code});
    debugPrint('[socket] Sent start-playback for room: $code');
  }

  void disconnect() {
    leaveRoom();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    connected.value = false;
  }

  void dispose() {
    disconnect();
    connected.dispose();
    participants.dispose();
    messages.dispose();
    magnetUri.dispose();
    streamPath.dispose();
    movieName.dispose();
  }

  String _generateParticipantId() {
    return 'flutter_${DateTime.now().millisecondsSinceEpoch}';
  }
}

class Participant {
  final String id;
  final String name;
  final String role;
  final Color? avatarColor;

  Participant({
    required this.id,
    required this.name,
    this.role = 'viewer',
    this.avatarColor,
  });

  bool get isHost => role == 'host';

  factory Participant.fromMap(dynamic data) {
    return Participant(
      id: data['id'] ?? '',
      name: data['name'] ?? 'User',
      role: data['role'] ?? 'viewer',
    );
  }
}

class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String senderRole;
  final String text;
  final DateTime timestamp;
  final bool isMe;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.text,
    required this.timestamp,
    this.isMe = false,
  });
}
