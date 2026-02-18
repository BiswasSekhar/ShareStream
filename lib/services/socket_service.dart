import 'dart:ui';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter/foundation.dart';

/// Socket.IO service for room management, playback sync, and WebRTC signaling.
/// Connects to the Lovestream server (multi-participant rooms).
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
    _socket = io.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'reconnection': true,
      'reconnectionDelay': 1000,
      'reconnectionAttempts': 10,
    });

    _socket!.onConnect((_) {
      debugPrint('[socket] Connected: ${_socket!.id}');
      _userId = _socket!.id;
      connected.value = true;
    });

    _socket!.onDisconnect((_) {
      debugPrint('[socket] Disconnected');
      connected.value = false;
    });

    _socket!.onReconnect((_) {
      debugPrint('[socket] Reconnected');
      connected.value = true;
      if (_currentRoom != null) {
        joinRoom(_currentRoom!, name: 'Reconnecting');
      }
    });

    // ─── Participant Events (N-participant) ───
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

    // ─── WebRTC Signaling ───
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

    // ─── Torrent / Stream Events ───
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

    // ─── Movie metadata ───
    _socket!.on('movie-loaded', (data) {
      debugPrint('[socket] Movie loaded: ${data['name']}');
      movieName.value = data['name'];
    });

    // ─── Room mode ───
    _socket!.on('room-mode', (data) {
      debugPrint('[socket] Room mode: ${data['mode']}');
    });

    // ─── Playback Sync Events ───
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

    // ─── Chat Events ───
    _socket!.on('chat-message', (data) {
      final msg = ChatMessage(
        id: data['id'] ?? '',
        senderId: data['senderId'] ?? '',
        senderName: data['sender'] ?? 'Unknown',
        senderRole: data['senderRole'] ?? 'viewer',
        text: data['text'] ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (data['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        ),
        isMe: data['senderId'] == _userId,
      );
      messages.value = [...messages.value, msg];
    });

    _socket!.on('error', (data) {
      debugPrint('[socket] Error: $data');
    });
  }

  // ─── Generic emit (used by WebRTCService) ───
  void emit(String event, Map<String, dynamic> data) {
    _socket?.emit(event, data);
  }

  // ─── Room Actions ───
  void createRoom({String? name, String? requestedCode}) {
    _isHost = true;
    _participantId = _generateParticipantId();
    _socket?.emit('create-room', [
      {
        'participantId': _participantId,
        'name': name ?? 'Host',
        'capabilities': {'nativePlayback': true},
        'requestedCode': requestedCode,
      },
      (dynamic response) {
        if (response != null && response['success'] == true) {
          _currentRoom = response['room']?['code'];
          debugPrint('[socket] Created room: $_currentRoom');
        } else {
          debugPrint('[socket] Create room failed: $response');
        }
      },
    ]);
  }

  void joinRoom(String code, {String? name}) {
    _isHost = false;
    _participantId ??= _generateParticipantId();
    final normalizedCode = code.trim().toUpperCase();
    _socket?.emit('join-room', [
      {
        'code': normalizedCode,
        'participantId': _participantId,
        'name': name ?? 'Guest',
        'capabilities': {'nativePlayback': true},
      },
      (dynamic response) {
        if (response != null && response['success'] == true) {
          _currentRoom = response['room']?['code'];
          final role = response['room']?['role'] ?? 'viewer';
          _isHost = role == 'host';
          debugPrint('[socket] Joined room: $_currentRoom as $role');
        } else {
          debugPrint('[socket] Join failed: ${response?['error']}');
        }
      },
    ]);
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

  // ─── Stream Actions ───
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

  // ─── Playback Sync ───
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

  // ─── Chat ───
  void sendMessage(String text) {
    _socket?.emit('chat-message', {'text': text});
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

// ─── Data Models ───

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
