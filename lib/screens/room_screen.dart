import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../providers/room_provider.dart';
import '../services/socket_service.dart';
import '../widgets/video_call_overlay.dart';

class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key});

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> with TickerProviderStateMixin {
  // ─── Media Kit ───
  late final Player _player;
  late final VideoController _videoController;

  // ─── Chat ───
  final _chatController = TextEditingController();
  final _chatScrollController = ScrollController();
  bool _showChat = false;
  bool _showParticipants = true;

  // ─── State ───
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _controlsVisible = true;
  bool _videoLoaded = false;

  @override
  void initState() {
    super.initState();

    // Initialize media_kit player with hardware acceleration
    _player = Player(
      configuration: const PlayerConfiguration(
        // Enable hardware decoding
        bufferSize: 32 * 1024 * 1024,
      ),
    );
    _videoController = VideoController(_player);

    // Listen to player state
    _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
    _player.stream.position.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _player.stream.duration.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
    _player.stream.completed.listen((completed) {
      if (completed && mounted) setState(() => _isPlaying = false);
    });

    // Wire up socket sync
    final provider = context.read<RoomProvider>();
    provider.socket.onPlayPauseRequested = (playing) {
      if (playing) {
        _player.play();
      } else {
        _player.pause();
      }
    };
    provider.socket.onSeekRequested = (pos) {
      _player.seek(Duration(seconds: pos.toInt()));
    };

    // Torrent auto-play: when viewer's torrent service gets a server URL
    provider.torrent.serverUrl.addListener(() {
      final url = provider.torrent.serverUrl.value;
      if (url != null && !provider.isHost && mounted) {
        debugPrint('[room] Auto-playing torrent from: $url');
        _player.open(Media(url));
        setState(() => _videoLoaded = true);
      }
    });

    // Auto-hide controls
    _startControlsTimer();
  }

  void _startControlsTimer() {
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      dialogTitle: 'Select Video to Share',
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) return;

    if (!mounted) return;
    final provider = context.read<RoomProvider>();
    provider.setSelectedFile(file.path!, file.name);

    // Try to seed via torrent service (desktop)
    final torrentUrl = await provider.seedFile(file.path!, file.name);

    if (!mounted) return;

    if (torrentUrl != null) {
      // Play from the torrent's localhost HTTP server
      await _player.open(Media(torrentUrl));
    } else {
      // Fallback: play directly from local file
      await _player.open(Media(file.path!));
      provider.socket.emitMovieLoaded(file.name, 0);
    }

    if (!mounted) return;
    setState(() => _videoLoaded = true);
  }

  void _togglePlayPause() {
    final provider = context.read<RoomProvider>();
    final time = _position.inSeconds.toDouble();
    if (_isPlaying) {
      _player.pause();
      provider.socket.syncPause(time);
    } else {
      _player.play();
      provider.socket.syncPlay(time);
    }
  }

  void _onSeek(double value) {
    final pos = Duration(seconds: value.toInt());
    _player.seek(pos);
    context.read<RoomProvider>().socket.syncSeek(value);
  }

  void _toggleVideoCall() async {
    final provider = context.read<RoomProvider>();
    if (provider.webrtc.isInCall.value) {
      await provider.endCall();
    } else {
      await provider.startCall();
    }
    if (mounted) setState(() {});
  }

  void _sendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    final provider = context.read<RoomProvider>();
    provider.socket.sendMessage(text);
    _chatController.clear();

    // Scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _leaveRoom() {
    context.read<RoomProvider>().leaveRoom();
    Navigator.pop(context);
  }

  void _copyRoomCode() {
    final code = context.read<RoomProvider>().roomCode;
    if (code != null) {
      Clipboard.setData(ClipboardData(text: code));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: AppTheme.success, size: 18),
              const SizedBox(width: 10),
              Text('Room code "$code" copied!'),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RoomProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.bgDeep, AppTheme.bgPrimary],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // ─── Top Bar ───
                  _buildTopBar(provider),

                  // ─── Main Content ───
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 800;
                        if (isWide) {
                          return _buildWideLayout(provider);
                        }
                        return _buildNarrowLayout(provider);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWideLayout(RoomProvider provider) {
    return Stack(
      children: [
        Row(
          children: [
            // Video section
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  Expanded(child: _buildVideoArea(provider)),
                  _buildPlaybackControls(),
                ],
              ),
            ),
            // Side panel
            if (_showChat || _showParticipants)
              SizedBox(
                width: 320,
                child: _buildSidePanel(provider),
              ),
          ],
        ),
        // Video call overlay
        ValueListenableBuilder<bool>(
          valueListenable: provider.webrtc.isInCall,
          builder: (_, inCall, _) {
            if (!inCall) return const SizedBox.shrink();
            return Positioned.fill(
              child: VideoCallOverlay(
                webrtcService: provider.webrtc,
                onEndCall: () async {
                  await provider.endCall();
                  if (mounted) setState(() {});
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(RoomProvider provider) {
    return Column(
      children: [
        // Video area
        AspectRatio(
          aspectRatio: 16 / 9,
          child: _buildVideoArea(provider),
        ),
        // Controls
        _buildPlaybackControls(),
        // Participants strip
        _buildParticipantStrip(provider),
        // Chat area  
        if (_showChat) Expanded(child: _buildChatArea(provider)),
        if (!_showChat) const Spacer(),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  TOP BAR
  // ═══════════════════════════════════════════════════════════════

  Widget _buildTopBar(RoomProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMD,
        vertical: AppTheme.spacingSM,
      ),
      decoration: BoxDecoration(
        color: AppTheme.bgPrimary.withValues(alpha: 0.9),
        border: Border(
          bottom: BorderSide(color: AppTheme.border.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            onPressed: _leaveRoom,
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
            tooltip: 'Leave Room',
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.bgElevated,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Room code badge
          GestureDetector(
            onTap: _copyRoomCode,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.tag_rounded, size: 16, color: AppTheme.primaryLight),
                  const SizedBox(width: 6),
                  Text(
                    provider.roomCode ?? '—',
                    style: const TextStyle(
                      color: AppTheme.primaryLight,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.copy_rounded, size: 14, color: AppTheme.textMuted),
                ],
              ),
            ),
          ),
          const Spacer(),
          // Participant count
          ValueListenableBuilder<List<Participant>>(
            valueListenable: provider.participants,
            builder: (_, participants, _) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.bgElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people_outline_rounded, size: 16, color: AppTheme.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      '${participants.length}',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          // Video call button
          ValueListenableBuilder<bool>(
            valueListenable: provider.webrtc.isInCall,
            builder: (_, inCall, _) {
              return IconButton(
                onPressed: _toggleVideoCall,
                icon: Icon(
                  inCall ? Icons.videocam : Icons.videocam_outlined,
                  size: 22,
                  color: inCall ? AppTheme.accent : AppTheme.textMuted,
                ),
                tooltip: inCall ? 'End Call' : 'Start Video Call',
                style: inCall
                    ? IconButton.styleFrom(
                        backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      )
                    : null,
              );
            },
          ),
          // Toggle participants
          IconButton(
            onPressed: () => setState(() => _showParticipants = !_showParticipants),
            icon: Icon(
              Icons.people_alt_rounded,
              size: 20,
              color: _showParticipants ? AppTheme.primary : AppTheme.textMuted,
            ),
            tooltip: 'Participants',
          ),
          // Toggle chat
          IconButton(
            onPressed: () => setState(() => _showChat = !_showChat),
            icon: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 20,
              color: _showChat ? AppTheme.primary : AppTheme.textMuted,
            ),
            tooltip: 'Chat',
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.3, duration: 300.ms);
  }

  // ═══════════════════════════════════════════════════════════════
  //  VIDEO AREA
  // ═══════════════════════════════════════════════════════════════

  Widget _buildVideoArea(RoomProvider provider) {
    if (!_videoLoaded) {
      return _buildEmptyVideoState(provider);
    }

    return GestureDetector(
      onTap: () {
        setState(() => _controlsVisible = !_controlsVisible);
        if (_controlsVisible) _startControlsTimer();
      },
      onDoubleTap: _togglePlayPause,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Video(
              controller: _videoController,
              fill: Colors.black,
            ),
          ),

          // Play/Pause overlay
          if (_controlsVisible)
            Center(
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: GestureDetector(
                  onTap: _togglePlayPause,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 36,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyVideoState(RoomProvider provider) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgDeep,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.1),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.movie_creation_outlined,
                size: 36,
                color: AppTheme.primaryLight,
              ),
            ).animate(
              onPlay: (c) => c.repeat(reverse: true),
            ).scale(
              begin: const Offset(1.0, 1.0),
              end: const Offset(1.05, 1.05),
              duration: 2000.ms,
            ),
            const SizedBox(height: 20),
            Text(
              provider.isHost
                  ? 'Select a video to share'
                  : 'Waiting for host to share...',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (provider.isHost) ...[
              const SizedBox(height: 20),
              GradientButton(
                label: 'Browse Files',
                icon: Icons.folder_open_rounded,
                onPressed: _pickFile,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  PLAYBACK CONTROLS
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPlaybackControls() {
    if (!_videoLoaded) return const SizedBox.shrink();

    final totalSec = _duration.inSeconds.toDouble();
    final posSec = _position.inSeconds.toDouble().clamp(0.0, totalSec);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMD,
        vertical: AppTheme.spacingSM,
      ),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface.withValues(alpha: 0.9),
        border: Border(
          top: BorderSide(color: AppTheme.border.withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        children: [
          // Seek bar
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: AppTheme.primary,
              inactiveTrackColor: AppTheme.bgElevated,
              thumbColor: AppTheme.primaryLight,
              overlayColor: AppTheme.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: totalSec > 0 ? posSec : 0.0,
              max: totalSec > 0 ? totalSec : 1,
              onChanged: _onSeek,
            ),
          ),
          // Controls row
          Row(
            children: [
              // Play/Pause
              IconButton(
                onPressed: _togglePlayPause,
                icon: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: AppTheme.textPrimary,
                  size: 28,
                ),
              ),
              // Time
              Text(
                '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              // File name
              if (context.read<RoomProvider>().selectedFileName != null)
                Flexible(
                  child: Text(
                    context.read<RoomProvider>().selectedFileName!,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(width: 8),
              // Fullscreen (placeholder)
              IconButton(
                onPressed: () {},
                icon: const Icon(
                  Icons.fullscreen_rounded,
                  color: AppTheme.textSecondary,
                  size: 24,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  PARTICIPANT STRIP (mobile)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildParticipantStrip(RoomProvider provider) {
    return ValueListenableBuilder<List<Participant>>(
      valueListenable: provider.participants,
      builder: (_, participants, _) {
        if (participants.isEmpty) return const SizedBox.shrink();

        return Container(
          height: 72,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMD),
            itemCount: participants.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final p = participants[i];
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ParticipantAvatar(
                    name: p.name,
                    isHost: p.isHost,
                    size: 36,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    p.name,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  SIDE PANEL (desktop)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSidePanel(RoomProvider provider) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        border: Border(
          left: BorderSide(color: AppTheme.border.withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        children: [
          // Tab bar
          Container(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                _buildPanelTab(
                  'Participants',
                  Icons.people_outline_rounded,
                  _showParticipants,
                  () => setState(() {
                    _showParticipants = true;
                    _showChat = false;
                  }),
                ),
                const SizedBox(width: 4),
                _buildPanelTab(
                  'Chat',
                  Icons.chat_bubble_outline_rounded,
                  _showChat,
                  () => setState(() {
                    _showChat = true;
                    _showParticipants = false;
                  }),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.divider),
          // Content
          Expanded(
            child: _showChat
                ? _buildChatArea(provider)
                : _buildParticipantList(provider),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelTab(String label, IconData icon, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppTheme.primary.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: active ? AppTheme.primary : AppTheme.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: active ? AppTheme.primary : AppTheme.textMuted,
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  PARTICIPANT LIST (desktop panel)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildParticipantList(RoomProvider provider) {
    return ValueListenableBuilder<List<Participant>>(
      valueListenable: provider.participants,
      builder: (_, participants, _) {
        if (participants.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.person_add_alt_1_outlined,
                  size: 40,
                  color: AppTheme.textMuted.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Share the room code\nto invite others',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(AppTheme.spacingMD),
          itemCount: participants.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final p = participants[i];
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  ParticipantAvatar(name: p.name, isHost: p.isHost, size: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          p.isHost ? 'Host' : 'Viewer',
                          style: TextStyle(
                            color: p.isHost ? AppTheme.warning : AppTheme.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppTheme.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: (i * 80).ms).slideX(begin: 0.1);
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  CHAT
  // ═══════════════════════════════════════════════════════════════

  Widget _buildChatArea(RoomProvider provider) {
    return Column(
      children: [
        // Messages
        Expanded(
          child: ValueListenableBuilder<List<ChatMessage>>(
            valueListenable: provider.messages,
            builder: (_, messages, _) {
              if (messages.isEmpty) {
                return const Center(
                  child: Text(
                    'No messages yet',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
                  ),
                );
              }
              return ListView.builder(
                controller: _chatScrollController,
                padding: const EdgeInsets.all(AppTheme.spacingMD),
                itemCount: messages.length,
                itemBuilder: (_, i) => _buildChatBubble(messages[i]),
              );
            },
          ),
        ),
        // Input
        Container(
          padding: const EdgeInsets.all(AppTheme.spacingSM),
          decoration: BoxDecoration(
            color: AppTheme.bgSurface,
            border: Border(
              top: BorderSide(color: AppTheme.border.withValues(alpha: 0.3)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.bgElevated,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: TextField(
                    controller: _chatController,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(color: AppTheme.textMuted),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: const BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                  padding: const EdgeInsets.all(10),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatBubble(ChatMessage msg) {
    final isMe = msg.isMe;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ParticipantAvatar(name: msg.senderName, size: 28),
            ),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe
                    ? AppTheme.primary.withValues(alpha: 0.2)
                    : AppTheme.bgCard,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                border: Border.all(
                  color: isMe
                      ? AppTheme.primary.withValues(alpha: 0.3)
                      : AppTheme.border.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        msg.senderName,
                        style: const TextStyle(
                          color: AppTheme.primaryLight,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Text(
                    msg.text,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Helpers ───

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }
}
