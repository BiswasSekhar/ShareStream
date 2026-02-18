import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/webrtc_service.dart';
import '../theme/app_theme.dart';

/// Floating video call overlay with PIP self-view and remote participant grid.
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
    with TickerProviderStateMixin {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  late AnimationController _fadeController;

  // PIP drag position
  Offset _pipOffset = const Offset(16, 16);

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _initializeRenderers();
    _fadeController.forward();
  }

  Future<void> _initializeRenderers() async {
    await _localRenderer.initialize();

    // Listen for local stream changes
    widget.webrtcService.localStream.addListener(_onLocalStreamChanged);
    widget.webrtcService.remoteStreams.addListener(_onRemoteStreamsChanged);

    // Set initial local stream
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

    // Remove renderers for peers no longer present
    final toRemove = _remoteRenderers.keys
        .where((id) => !streams.containsKey(id))
        .toList();
    for (final id in toRemove) {
      await _remoteRenderers[id]?.dispose();
      _remoteRenderers.remove(id);
    }

    // Add renderers for new peers
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
    _fadeController.dispose();
    _localRenderer.dispose();
    for (final r in _remoteRenderers.values) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeController,
      child: Stack(
        children: [
          // Remote video grid
          _buildRemoteGrid(),

          // PIP self-view (draggable)
          Positioned(
            right: _pipOffset.dx,
            bottom: _pipOffset.dy + 80, // above controls
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _pipOffset = Offset(
                    (_pipOffset.dx - details.delta.dx).clamp(0, MediaQuery.of(context).size.width - 140),
                    (_pipOffset.dy - details.delta.dy).clamp(0, MediaQuery.of(context).size.height - 200),
                  );
                });
              },
              child: _buildPipView(),
            ),
          ),

          // Controls bar at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildControlsBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoteGrid() {
    if (_remoteRenderers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              'Waiting for others to join the call...',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    final count = _remoteRenderers.length;
    final cols = count <= 1 ? 1 : (count <= 4 ? 2 : 3);

    return Padding(
      padding: const EdgeInsets.only(bottom: 80),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          childAspectRatio: 4 / 3,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: count,
        itemBuilder: (context, index) {
          final entry = _remoteRenderers.entries.elementAt(index);
          return _buildRemoteVideoTile(entry.key, entry.value);
        },
      ),
    );
  }

  Widget _buildRemoteVideoTile(String peerId, RTCVideoRenderer renderer) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.accent.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          RTCVideoView(
            renderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
          // Peer ID label
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                peerId.length > 8 ? peerId.substring(0, 8) : peerId,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPipView() {
    return Container(
      width: 130,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.accentAlt.withValues(alpha: 0.6),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentAlt.withValues(alpha: 0.3),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: widget.webrtcService.localStream.value != null
          ? RTCVideoView(
              _localRenderer,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          : const Center(
              child: Icon(Icons.person, color: Colors.white38, size: 32),
            ),
    );
  }

  Widget _buildControlsBar() {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Mic toggle
          ValueListenableBuilder<bool>(
            valueListenable: widget.webrtcService.audioEnabled,
            builder: (_, audioOn, _) {
              return _buildControlButton(
                icon: audioOn ? Icons.mic : Icons.mic_off,
                label: audioOn ? 'Mute' : 'Unmute',
                color: audioOn ? Colors.white : Colors.redAccent,
                bgColor: audioOn
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.redAccent.withValues(alpha: 0.2),
                onTap: widget.webrtcService.toggleAudio,
              );
            },
          ),
          const SizedBox(width: 16),

          // Camera toggle
          ValueListenableBuilder<bool>(
            valueListenable: widget.webrtcService.videoEnabled,
            builder: (_, videoOn, _) {
              return _buildControlButton(
                icon: videoOn ? Icons.videocam : Icons.videocam_off,
                label: videoOn ? 'Cam Off' : 'Cam On',
                color: videoOn ? Colors.white : Colors.orangeAccent,
                bgColor: videoOn
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.orangeAccent.withValues(alpha: 0.2),
                onTap: widget.webrtcService.toggleVideo,
              );
            },
          ),
          const SizedBox(width: 16),

          // End call
          _buildControlButton(
            icon: Icons.call_end,
            label: 'End',
            color: Colors.white,
            bgColor: Colors.redAccent,
            onTap: widget.onEndCall,
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.7),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
