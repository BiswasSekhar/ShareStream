import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/webrtc_service.dart';
import '../theme/app_theme.dart';

/// Meet/Jitsi-style video call panel with grid layout and floating controls.
class VideoCallOverlay extends StatefulWidget {
  final WebRTCService webrtcService;
  final VoidCallback onEndCall;

  const VideoCallOverlay({
    super.key,
    required this.webrtcService,
    required this.onEndCall,
  });

  @override
  State<VideoCallOverlay> createState() => _VideoCallOverlayState();
}

class _VideoCallOverlayState extends State<VideoCallOverlay>
    with SingleTickerProviderStateMixin {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};

  // Layout mode: overlay (floating) vs panel (side panel replacement)
  bool _isPanelMode = false;

  // Drag position for overlay mode
  Offset _position = const Offset(16, 80);

  late AnimationController _controlsAnimController;

  @override
  void initState() {
    super.initState();
    _controlsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0,
    );
    _initializeRenderers();
  }

  Future<void> _initializeRenderers() async {
    await _localRenderer.initialize();

    widget.webrtcService.localStream.addListener(_onLocalStreamChanged);
    widget.webrtcService.remoteStreams.addListener(_onRemoteStreamsChanged);

    _onLocalStreamChanged();
    _onRemoteStreamsChanged();
  }

  void _onLocalStreamChanged() {
    final stream = widget.webrtcService.localStream.value;
    if (stream != null) {
      _localRenderer.srcObject = stream;
    }
    if (mounted) setState(() {});
  }

  void _onRemoteStreamsChanged() async {
    final streams = widget.webrtcService.remoteStreams.value;

    final toRemove = _remoteRenderers.keys
        .where((id) => !streams.containsKey(id))
        .toList();
    for (final id in toRemove) {
      await _remoteRenderers[id]?.dispose();
      _remoteRenderers.remove(id);
    }

    for (final entry in streams.entries) {
      if (!_remoteRenderers.containsKey(entry.key)) {
        final renderer = RTCVideoRenderer();
        await renderer.initialize();
        renderer.srcObject = entry.value;
        _remoteRenderers[entry.key] = renderer;
      } else {
        _remoteRenderers[entry.key]!.srcObject = entry.value;
      }
    }

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.webrtcService.localStream.removeListener(_onLocalStreamChanged);
    widget.webrtcService.remoteStreams.removeListener(_onRemoteStreamsChanged);
    _controlsAnimController.dispose();
    _localRenderer.dispose();
    for (final r in _remoteRenderers.values) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isPanelMode) {
      return _buildPanelMode();
    }
    return _buildOverlayMode();
  }

  // ── Overlay Mode (floating, draggable) ──

  Widget _buildOverlayMode() {
    final totalParticipants = _remoteRenderers.length +
        (widget.webrtcService.localStream.value != null ? 1 : 0);
    final width = totalParticipants <= 1 ? 240.0 : 360.0;
    final height = totalParticipants <= 1 ? 180.0 : 300.0;

    return Positioned(
      right: _position.dx,
      bottom: _position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              (_position.dx - details.delta.dx)
                  .clamp(0, MediaQuery.of(context).size.width - width),
              (_position.dy - details.delta.dy)
                  .clamp(0, MediaQuery.of(context).size.height - height - 100),
            );
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.accent.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
                spreadRadius: 4,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Video grid
              _buildVideoGrid(),

              // Controls bar at bottom
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildControlsBar(),
              ),

              // Mode toggle + participant count
              Positioned(
                top: 6,
                right: 6,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (totalParticipants > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.people, size: 10, color: Colors.white70),
                            const SizedBox(width: 3),
                            Text(
                              '$totalParticipants',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(width: 4),
                    _buildIconButton(
                      icon: Icons.open_in_full,
                      onTap: () => setState(() => _isPanelMode = true),
                      size: 14,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Panel Mode (full side panel) ──

  Widget _buildPanelMode() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141424),
        border: Border(
          left: BorderSide(color: AppTheme.border.withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              border: Border(
                bottom: BorderSide(
                    color: AppTheme.border.withValues(alpha: 0.3)),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.videocam, color: AppTheme.accent, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Video Call',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                _buildIconButton(
                  icon: Icons.close_fullscreen,
                  onTap: () => setState(() => _isPanelMode = false),
                  size: 16,
                ),
              ],
            ),
          ),
          // Video grid
          Expanded(child: _buildVideoGrid()),
          // Controls bar
          _buildControlsBar(),
        ],
      ),
    );
  }

  // ── Video Grid ──

  Widget _buildVideoGrid() {
    final tiles = <Widget>[];

    // Add remote videos
    for (final entry in _remoteRenderers.entries) {
      tiles.add(_buildVideoTile(
        renderer: entry.value,
        label: _peerLabel(entry.key),
        isMuted: false,
        isRemote: true,
      ));
    }

    // Add local video
    if (widget.webrtcService.localStream.value != null) {
      tiles.add(_buildVideoTile(
        renderer: _localRenderer,
        label: 'You',
        isMuted: !widget.webrtcService.audioEnabled.value,
        mirror: true,
        isRemote: false,
      ));
    }

    if (tiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_rounded,
                size: 32, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 8),
            Text(
              'Waiting for participants...',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
            ),
          ],
        ),
      );
    }

    // Layout: 1=full, 2=side-by-side, 3-4=2x2
    if (tiles.length == 1) {
      return tiles[0];
    }

    if (tiles.length == 2) {
      return Row(
        children: tiles.map((t) => Expanded(child: t)).toList(),
      );
    }

    // 3-4 tiles: 2x2 grid
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: tiles[0]),
              Expanded(child: tiles[1]),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: tiles[2]),
              if (tiles.length > 3)
                Expanded(child: tiles[3])
              else
                const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVideoTile({
    required RTCVideoRenderer renderer,
    required String label,
    required bool isMuted,
    bool mirror = false,
    bool isRemote = false,
  }) {
    return Container(
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video
          RTCVideoView(
            renderer,
            mirror: mirror,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),

          // Gradient overlay at bottom for label
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 4),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isMuted)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.mic_off,
                          size: 12, color: Colors.redAccent),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Controls Bar ──

  Widget _buildControlsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E).withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
              color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Mic toggle
          ValueListenableBuilder<bool>(
            valueListenable: widget.webrtcService.audioEnabled,
            builder: (_, audioOn, __) {
              return _buildControlButton(
                icon: audioOn ? Icons.mic : Icons.mic_off,
                label: audioOn ? 'Mute' : 'Unmute',
                active: audioOn,
                activeColor: Colors.white,
                inactiveColor: Colors.redAccent,
                inactiveBg: Colors.redAccent.withValues(alpha: 0.15),
                onTap: widget.webrtcService.toggleAudio,
              );
            },
          ),
          const SizedBox(width: 8),
          // Camera toggle
          ValueListenableBuilder<bool>(
            valueListenable: widget.webrtcService.videoEnabled,
            builder: (_, videoOn, __) {
              return _buildControlButton(
                icon: videoOn ? Icons.videocam : Icons.videocam_off,
                label: videoOn ? 'Stop' : 'Start',
                active: videoOn,
                activeColor: Colors.white,
                inactiveColor: Colors.orangeAccent,
                inactiveBg: Colors.orangeAccent.withValues(alpha: 0.15),
                onTap: widget.webrtcService.toggleVideo,
              );
            },
          ),
          const SizedBox(width: 12),
          // End call
          _buildControlButton(
            icon: Icons.call_end,
            label: 'End',
            active: false,
            activeColor: Colors.white,
            inactiveColor: Colors.white,
            inactiveBg: Colors.redAccent,
            onTap: widget.onEndCall,
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool active,
    required Color activeColor,
    required Color inactiveColor,
    required Color inactiveBg,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: active
                  ? Colors.white.withValues(alpha: 0.1)
                  : inactiveBg,
              shape: BoxShape.circle,
              border: active
                  ? Border.all(color: Colors.white.withValues(alpha: 0.15))
                  : null,
            ),
            child: Icon(
              icon,
              color: active ? activeColor : inactiveColor,
              size: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 16,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white70, size: size),
      ),
    );
  }

  String _peerLabel(String peerId) {
    // Truncate long IDs for display
    if (peerId.length > 8) {
      return 'Peer ${peerId.substring(0, 6)}';
    }
    return 'Peer $peerId';
  }
}
