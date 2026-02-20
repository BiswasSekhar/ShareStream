import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/room_provider.dart';
import '../widgets/top_bar_widget.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/side_panel_widget.dart';
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

    _player = Player(
      configuration: const PlayerConfiguration(
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

  // ─── Actions ───

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

    final torrentUrl = await provider.seedFile(file.path!, file.name);

    if (!mounted) return;

    if (torrentUrl != null) {
      await _player.open(Media(torrentUrl));
    } else {
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

  // ─── Build ───

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
                  TopBarWidget(
                    provider: provider,
                    showParticipants: _showParticipants,
                    showChat: _showChat,
                    onLeave: _leaveRoom,
                    onToggleVideoCall: _toggleVideoCall,
                    onToggleParticipants: () => setState(() => _showParticipants = !_showParticipants),
                    onToggleChat: () => setState(() => _showChat = !_showChat),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 800;
                        if (isWide) return _buildWideLayout(provider);
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
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  Expanded(
                    child: VideoPlayerWidget(
                      videoController: _videoController,
                      provider: provider,
                      videoLoaded: _videoLoaded,
                      isPlaying: _isPlaying,
                      controlsVisible: _controlsVisible,
                      position: _position,
                      duration: _duration,
                      onTogglePlayPause: _togglePlayPause,
                      onToggleControls: () {
                        setState(() => _controlsVisible = !_controlsVisible);
                        if (_controlsVisible) _startControlsTimer();
                      },
                      onPickFile: _pickFile,
                      onSeek: _onSeek,
                      selectedFileName: provider.selectedFileName,
                    ),
                  ),
                  PlaybackControlsWidget(
                    videoLoaded: _videoLoaded,
                    isPlaying: _isPlaying,
                    position: _position,
                    duration: _duration,
                    onTogglePlayPause: _togglePlayPause,
                    onSeek: _onSeek,
                    selectedFileName: provider.selectedFileName,
                  ),
                ],
              ),
            ),
            if (_showChat || _showParticipants)
              SizedBox(
                width: 320,
                child: SidePanelWidget(
                  provider: provider,
                  showChat: _showChat,
                  showParticipants: _showParticipants,
                  onShowParticipants: () => setState(() {
                    _showParticipants = true;
                    _showChat = false;
                  }),
                  onShowChat: () => setState(() {
                    _showChat = true;
                    _showParticipants = false;
                  }),
                  chatController: _chatController,
                  chatScrollController: _chatScrollController,
                  onSendMessage: _sendMessage,
                ),
              ),
          ],
        ),
        // Video call PIP overlay
        ValueListenableBuilder<bool>(
          valueListenable: provider.webrtc.isInCall,
          builder: (_, inCall, __) {
            if (!inCall) return const SizedBox.shrink();
            return VideoCallOverlay(
              webrtcService: provider.webrtc,
              onEndCall: () async {
                await provider.endCall();
                if (mounted) setState(() {});
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(RoomProvider provider) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: VideoPlayerWidget(
            videoController: _videoController,
            provider: provider,
            videoLoaded: _videoLoaded,
            isPlaying: _isPlaying,
            controlsVisible: _controlsVisible,
            position: _position,
            duration: _duration,
            onTogglePlayPause: _togglePlayPause,
            onToggleControls: () {
              setState(() => _controlsVisible = !_controlsVisible);
              if (_controlsVisible) _startControlsTimer();
            },
            onPickFile: _pickFile,
            onSeek: _onSeek,
            selectedFileName: provider.selectedFileName,
          ),
        ),
        PlaybackControlsWidget(
          videoLoaded: _videoLoaded,
          isPlaying: _isPlaying,
          position: _position,
          duration: _duration,
          onTogglePlayPause: _togglePlayPause,
          onSeek: _onSeek,
          selectedFileName: provider.selectedFileName,
        ),
        ParticipantStripWidget(provider: provider),
        if (_showChat)
          Expanded(
            child: SidePanelWidget(
              provider: provider,
              showChat: true,
              showParticipants: false,
              onShowParticipants: () {},
              onShowChat: () {},
              chatController: _chatController,
              chatScrollController: _chatScrollController,
              onSendMessage: _sendMessage,
            ),
          ),
        if (!_showChat) const Spacer(),
      ],
    );
  }
}
