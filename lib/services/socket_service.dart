import 'dart:ui';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter/foundation.dart';

/// Socket.IO service for room management, playback sync, and WebRTC signaling.
/// Connects to the ShareStream signaling server.
class SocketService {
  io.Socket? _socket;
  String? _currentRoom;
  String? _currentServerUrl;
  String? _userId;
  String? _participantId;
  String _userName = 'User';
  bool _isHost = false;

  final ValueNotifier<bool> connected = ValueNotifier(false);
  final ValueNotifier<String?> lastConnectionError = ValueNotifier(null);
  final ValueNotifier<List<Participant>> participants = ValueNotifier([]);
  final ValueNotifier<List<ChatMessage>> messages = ValueNotifier([]);
  final ValueNotifier<String?> magnetUri = ValueNotifier(null);
  final ValueNotifier<String?> streamPath = ValueNotifier(null);
  final ValueNotifier<String?> movieName = ValueNotifier(null);
  final ValueNotifier<String?> inviteToken = ValueNotifier(null);

  // Playback sync callbacks
  void Function(double time)? onSeekRequested;
  void Function(bool playing)? onPlayPauseRequested;
  void Function(String magnet, String path)? onTorrentMagnet;
  void Function(
    int serverSeq,
    String actionType,
    double targetTime,
    bool playWhenReady,
    String initiatorParticipantId,
  )?
  onControlCommitted;

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

  // Torrent peer exchange callback
  void Function(String fromId, String address, int port)? onTorrentPeerInfo;

  String? get currentRoom => _currentRoom;
  String? get currentServerUrl => _currentServerUrl;
  String? get userId => _userId;
  String? get participantId => _participantId;
  bool get isHost => _isHost;
  bool get isConnected => connected.value;

  void connect(String serverUrl) {
    lastConnectionError.value = null;

    final normalizedServerUrl = _normalizeSocketBaseUrl(serverUrl);
    _currentServerUrl = normalizedServerUrl;

    // If already connected to a different URL, disconnect first
    if (_socket != null) {
      debugPrint(
        '[socket] Cleaning up previous connection before connecting to: $normalizedServerUrl',
      );
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      connected.value = false;
    }

    debugPrint('[socket] Connecting to: $normalizedServerUrl');

    // Cloudflare tunnels (HTTPS) need polling-first handshake before upgrading to WS.
    // Localhost can go straight to websocket for lower latency.
    final isSecure = normalizedServerUrl.startsWith('https');
    final transports = isSecure
        ? ['polling', 'websocket']
        : ['websocket', 'polling'];
    debugPrint('[socket] Transport order: $transports (isSecure=$isSecure)');

    _socket = io.io(
      normalizedServerUrl,
      io.OptionBuilder()
          .setTransports(transports)
          .enableForceNew()
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionAttempts(10)
          .setTimeout(20000)
          .build(),
    );

    // Explicitly call connect in case autoConnect is delayed
    if (!_socket!.connected) {
      _socket!.connect();
    }

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
      final raw = '$err';
      var friendly = raw;
      if (raw.contains('HTTP status code: 530')) {
        friendly =
            'Tunnel is unavailable or expired (HTTP 530). Ask host for a fresh invite link.';
      }

      if (raw.contains(':0/socket.io/')) {
        friendly =
            'Invalid tunnel socket endpoint (port resolution issue). Please retry with a fresh link.';
      }

      lastConnectionError.value = friendly;
      debugPrint('[socket] ❌ Connection error: $raw');
      debugPrint(
        '[socket]    → Make sure signal server is running on $normalizedServerUrl',
      );
      connected.value = false;
    });

    _socket!.on('connect_timeout', (_) {
      lastConnectionError.value =
          'Connection timed out. Check network or verify host link.';
      debugPrint('[socket] ❌ Connection timed out to $normalizedServerUrl');
      connected.value = false;
    });

    _socket!.onReconnect((_) {
      debugPrint('[socket] Reconnected after disconnect');
      connected.value = true;
      if (_currentRoom != null && _participantId != null) {
        debugPrint('[socket] Re-joining room: $_currentRoom');
        _socket?.emit('register-participant', {
          'participantId': _participantId,
        });
        _socket?.emit('join-room', {
          'code': _currentRoom,
          'participantId': _participantId,
          'name': _userName,
          'capabilities': {'nativePlayback': true},
        });
      }
    });

    _socket!.onReconnectAttempt((attempt) {
      debugPrint(
        '[socket] Reconnect attempt #$attempt to $normalizedServerUrl',
      );
    });

    _socket!.onReconnectFailed((_) {
      debugPrint(
        '[socket] ❌ Reconnection failed after all attempts to $normalizedServerUrl',
      );
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

    _socket!.on('participant-left', (data) {
      final leftId = data['id'] as String?;
      debugPrint('[socket] Participant left: $leftId');
      if (leftId != null) {
        onPeerLeft?.call(leftId);
        final current = List<Participant>.from(participants.value);
        current.removeWhere((p) => p.id == leftId);
        participants.value = current;
        debugPrint(
          '[socket] Participants list updated: ${current.length} total',
        );
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

    // Notify when a new participant joins to start WebRTC
    _socket!.on('participant-joined', (data) {
      final id = data['id'] as String? ?? '';
      final name = data['name'] as String? ?? 'Unknown';
      debugPrint('[socket] Participant joined: $name ($id)');
      if (id.isNotEmpty) {
        final current = List<Participant>.from(participants.value);
        if (!current.any((p) => p.id == id)) {
          current.add(Participant(id: id, name: name, role: 'viewer'));
          participants.value = current;
          debugPrint(
            '[socket] Participants list updated: ${current.length} total',
          );
        }

        // Don't trigger WebRTC connection to ourselves
        final myId = _participantId ?? _userId ?? '';
        if (id == myId || id == _userId) {
          debugPrint('[socket] Skipping WebRTC trigger for self ($id)');
          return;
        }

        // Trigger WebRTC connection to new peer
        final imInitiator = myId.compareTo(id) < 0;
        debugPrint(
          '[socket] Triggering WebRTC with $id, initiator: $imInitiator',
        );
        onStartWebRTC?.call(id, imInitiator);
      }
    });

    _socket!.on('offer', (data) {
      final from = data['from'] as String?;
      final offer = data['offer'];
      if (from != null && offer != null) {
        debugPrint('[socket] Received offer from $from');
        onOffer?.call(from, Map<String, dynamic>.from(offer));
      }
    });

    _socket!.on('answer', (data) {
      final from = data['from'] as String?;
      final answer = data['answer'];
      if (from != null && answer != null) {
        debugPrint('[socket] Received answer from $from');
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

    // Playback control events (server-authoritative, ordered)
    _socket!.on('control-committed', (data) {
      final serverSeq = (data['serverSeq'] as num?)?.toInt() ?? 0;
      final actionType = data['actionType'] as String? ?? '';
      final targetTime =
          (data['targetTimeSec'] as num?)?.toDouble() ??
          (data['time'] as num?)?.toDouble() ??
          0.0;
      final playWhenReady =
          data['playWhenReady'] as bool? ??
          data['playing'] as bool? ??
          (actionType == 'play');
      final initiatorParticipantId =
          data['initiatorParticipantId'] as String? ?? '';

      onControlCommitted?.call(
        serverSeq,
        actionType,
        targetTime,
        playWhenReady,
        initiatorParticipantId,
      );
    });

    _socket!.on('playback-snapshot', (data) {
      final playback = data['playback'];
      if (playback != null) {
        final time = (playback['time'] as num?)?.toDouble();
        final type = playback['type'] as String?;
        final serverSeq =
            (data['serverSeq'] as num?)?.toInt() ??
            (playback['serverSeq'] as num?)?.toInt() ??
            0;

        if (onControlCommitted != null && time != null && type != null) {
          onControlCommitted!.call(
            serverSeq,
            type,
            time,
            type == 'play',
            'snapshot',
          );
          return;
        }

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
      final msgId = data['id'] as String? ?? '';
      final senderId = data['senderId'] ?? '';

      // Only deduplicate if message has a real ID (non-empty)
      if (msgId.isNotEmpty) {
        final isDuplicate = messages.value.any((m) => m.id == msgId);
        if (isDuplicate) {
          debugPrint('[socket] Duplicate chat message ignored: $msgId');
          return;
        }
      }

      // Generate a unique ID if server didn't provide one
      final effectiveId = msgId.isNotEmpty
          ? msgId
          : '${senderId}_${DateTime.now().millisecondsSinceEpoch}';

      final isMe = senderId == _userId || senderId == _participantId;

      // Skip messages we sent ourselves (already added locally)
      if (isMe) {
        debugPrint('[socket] Skipping own chat message echo');
        return;
      }

      final msg = ChatMessage(
        id: effectiveId,
        senderId: senderId,
        senderName: data['sender'] ?? 'Unknown',
        senderRole: data['senderRole'] ?? 'viewer',
        text: data['text'] ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (data['timestamp'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        ),
        isMe: false,
      );
      messages.value = [...messages.value, msg];
    });

    _socket!.on('error', (data) {
      debugPrint('[socket] Error: $data');
    });

    // Torrent Peer Exchange
    _socket!.on('torrent-peer-info', (data) {
      final from = data['from'] as String?;
      final address = data['address'] as String?;
      final port = (data['port'] as num?)?.toInt() ?? 0;
      if (from != null && address != null && port > 0) {
        debugPrint('[socket] Torrent peer info from $from: $address:$port');
        onTorrentPeerInfo?.call(from, address, port);
      }
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
      final code = data['code'] as String?;
      debugPrint('[socket] Join approved, room code: $code');
      onJoinApproved?.call(code ?? '');
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
        inviteToken.value = data['room']?['inviteToken'] as String?;
        // Add self as first participant (host)
        participants.value = [
          Participant(
            id: _participantId ?? 'host',
            name: _userName,
            role: 'host',
          ),
        ];
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
        if (!_isHost) {
          _isHost = role == 'host';
        }
        // Add self to participant list
        final current = List<Participant>.from(participants.value);
        if (!current.any((p) => p.id == _participantId)) {
          current.add(
            Participant(
              id: _participantId ?? 'viewer',
              name: _userName,
              role: role,
            ),
          );
          participants.value = current;
        }
        debugPrint('[socket] Joined room: $_currentRoom as $role');
      } else {
        debugPrint('[socket] Join failed: ${data?['error']}');
      }
    });
  }

  String _normalizeSocketBaseUrl(String raw) {
    final input = raw.trim();
    if (input.isEmpty) {
      return raw;
    }

    // Strip trailing slashes — Socket.IO appends its own /socket.io/ path
    String normalized = input;
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    return normalized;
  }

  // Generic emit
  void emit(String event, Map<String, dynamic> data) {
    _socket?.emit(event, data);
  }

  // Room Actions
  void createRoom({String? name, String? requestedCode}) {
    _isHost = true;
    _userName = name ?? 'Host';
    _participantId = _generateParticipantId();
    _socket?.emit('register-participant', {'participantId': _participantId});
    _socket?.emit('create-room', {
      'participantId': _participantId,
      'name': name ?? 'Host',
      'capabilities': {'nativePlayback': true},
      'requestedCode': requestedCode,
    });
  }

  void joinRoom(String code, {String? name}) {
    _isHost = false;
    _userName = name ?? 'Guest';
    _participantId ??= _generateParticipantId();
    final normalizedCode = code.trim().toUpperCase();
    debugPrint(
      '[socket] Emitting join-room for code: $normalizedCode, participant: $_participantId',
    );
    // Register participant ID so server can send targeted messages
    _socket?.emit('register-participant', {'participantId': _participantId});
    _socket?.emit('join-room', {
      'code': normalizedCode,
      'participantId': _participantId,
      'name': name ?? 'Guest',
      'capabilities': {'nativePlayback': true},
    });
  }

  void joinRequest(String code, String name, {String? inviteTokenValue}) {
    _userName = name;
    _participantId ??= _generateParticipantId();
    final normalizedCode = code.trim().toUpperCase();
    debugPrint(
      '[socket] Sending join-request for code: $normalizedCode, participant: $_participantId',
    );
    // Register participant ID so server can send targeted messages
    _socket?.emit('register-participant', {'participantId': _participantId});
    _socket?.emit('join-request', {
      'code': normalizedCode,
      'participantId': _participantId,
      'name': name,
      'inviteToken': inviteTokenValue ?? inviteToken.value,
    });
  }

  void approveJoin(String participantId) {
    _socket?.emit('join-approve', {
      'participantId': participantId,
      'code': _currentRoom,
    });
    debugPrint(
      '[socket] Approved join for: $participantId in room: $_currentRoom',
    );
  }

  void rejectJoin(String participantId) {
    _socket?.emit('join-reject', {
      'participantId': participantId,
      'code': _currentRoom,
    });
    debugPrint(
      '[socket] Rejected join for: $participantId in room: $_currentRoom',
    );
  }

  void requestJoinApproval() {
    if (_currentRoom == null || _participantId == null) return;
    _socket?.emit('request-join-approval', {
      'code': _currentRoom,
      'participantId': _participantId,
    });
  }

  void leaveRoom() {
    if (_currentRoom != null) {
      _socket?.emit('leave-room', {'code': _currentRoom});
      _currentRoom = null;
      _isHost = false;
      participants.value = [];
      messages.value = [];
      magnetUri.value = null;
      streamPath.value = null;
      movieName.value = null;
      inviteToken.value = null;
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
    _socket?.emit('movie-loaded', {'name': name, 'duration': duration});
  }

  // Playback control (shared authority, server-ordered)
  void sendControlRequest({
    required String actionType,
    required double targetTimeSec,
    required bool playWhenReady,
    int? baseSeq,
  }) {
    _socket?.emit('control-request', {
      'code': _currentRoom,
      'participantId': _participantId ?? _userId ?? '',
      'actionId':
          '${_participantId ?? _userId ?? 'unknown'}_${DateTime.now().microsecondsSinceEpoch}',
      'actionType': actionType,
      'targetTimeSec': targetTimeSec,
      'playWhenReady': playWhenReady,
      'baseSeq': baseSeq ?? 0,
      'sentAtMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void sendControlAck({
    required int serverSeq,
    required double currentTimeSec,
    required bool playing,
    required double bufferedSec,
  }) {
    _socket?.emit('control-ack', {
      'code': _currentRoom,
      'serverSeq': serverSeq,
      'participantId': _participantId ?? _userId ?? '',
      'currentTimeSec': currentTimeSec,
      'playing': playing,
      'bufferedSec': bufferedSec,
      'sentAtMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // Sync Actions (New)
  void syncCheck(String code) {
    _socket?.emit('sync-check', {'code': code});
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
      'code': _currentRoom,
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
    final msgId = '${_participantId}_${DateTime.now().millisecondsSinceEpoch}';
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    _socket?.emit('chat-message', {
      'text': text,
      'id': msgId,
      'senderId': _participantId ?? _userId ?? '',
      'sender': _userName,
      'senderRole': _isHost ? 'host' : 'viewer',
      'timestamp': timestamp,
    });

    // Add to local messages immediately (sender doesn't wait for echo)
    final msg = ChatMessage(
      id: msgId,
      senderId: _participantId ?? _userId ?? '',
      senderName: _userName,
      senderRole: _isHost ? 'host' : 'viewer',
      text: text,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
      isMe: true,
    );
    messages.value = [...messages.value, msg];
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

  // Torrent Peer Exchange
  void emitTorrentPeerInfo(String address, int port) {
    _socket?.emit('torrent-peer-info', {
      'address': address,
      'port': port,
    });
    debugPrint('[socket] Sent torrent-peer-info: $address:$port');
  }

  void disconnect() {
    leaveRoom();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    connected.value = false;
    lastConnectionError.value = null;
  }

  void dispose() {
    disconnect();
    connected.dispose();
    participants.dispose();
    messages.dispose();
    magnetUri.dispose();
    streamPath.dispose();
    movieName.dispose();
    inviteToken.dispose();
    lastConnectionError.dispose();
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
