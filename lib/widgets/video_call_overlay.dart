import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/webrtc_service.dart';
import '../theme/app_theme.dart';

/// Draggable PIP video call cube with controls inside.
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

class _VideoCallOverlayState extends State<VideoCallOverlay> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};

  // Drag position (bottom-right corner by default)
  Offset _position = const Offset(16, 80);
  bool _expanded = false; // toggle between small PIP and expanded view

  @override
  void initState() {
    super.initState();
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
    _localRenderer.dispose();
    for (final r in _remoteRenderers.values) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = _expanded ? 320.0 : 180.0;
    final height = _expanded ? 280.0 : 140.0;

    return Positioned(
      right: _position.dx,
      bottom: _position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              (_position.dx - details.delta.dx).clamp(0, MediaQuery.of(context).size.width - width),
              (_position.dy - details.delta.dy).clamp(0, MediaQuery.of(context).size.height - height - 100),
            );
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.accent.withValues(alpha: 0.5),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Video content
              _buildVideoContent(),

              // Controls overlay at bottom
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildControls(),
              ),

              // Expand/collapse button
              Positioned(
                top: 4,
                right: 4,
                child: _buildSmallButton(
                  icon: _expanded ? Icons.close_fullscreen : Icons.open_in_full,
                  onTap: () => setState(() => _expanded = !_expanded),
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoContent() {
    // Show remote video if available, otherwise show local
    if (_remoteRenderers.isNotEmpty) {
      final firstRemote = _remoteRenderers.values.first;
      return Stack(
        fit: StackFit.expand,
        children: [
          RTCVideoView(
            firstRemote,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
          // Small local PIP in corner
          if (widget.webrtcService.localStream.value != null)
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                width: 48,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.primaryLight, width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: RTCVideoView(
                  _localRenderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),
        ],
      );
    }

    // Only local video
    if (widget.webrtcService.localStream.value != null) {
      return RTCVideoView(
        _localRenderer,
        mirror: true,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam_off, size: 24, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 4),
          Text(
            'Waiting...',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Mic
          ValueListenableBuilder<bool>(
            valueListenable: widget.webrtcService.audioEnabled,
            builder: (_, audioOn, _) {
              return _buildSmallButton(
                icon: audioOn ? Icons.mic : Icons.mic_off,
                onTap: widget.webrtcService.toggleAudio,
                color: audioOn ? Colors.white : Colors.redAccent,
              );
            },
          ),
          // Camera
          ValueListenableBuilder<bool>(
            valueListenable: widget.webrtcService.videoEnabled,
            builder: (_, videoOn, _) {
              return _buildSmallButton(
                icon: videoOn ? Icons.videocam : Icons.videocam_off,
                onTap: widget.webrtcService.toggleVideo,
                color: videoOn ? Colors.white : Colors.orangeAccent,
              );
            },
          ),
          // End call
          _buildSmallButton(
            icon: Icons.call_end,
            onTap: widget.onEndCall,
            color: Colors.white,
            bgColor: Colors.redAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildSmallButton({
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.white,
    Color? bgColor,
    double size = 16,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: bgColor ?? Colors.white.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: size),
      ),
    );
  }
}
