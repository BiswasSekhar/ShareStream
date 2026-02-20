import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../theme/app_theme.dart';
import '../providers/room_provider.dart';
import 'common_widgets.dart';

/// Video player area with play/pause overlay and empty state.
class VideoPlayerWidget extends StatelessWidget {
  final VideoController videoController;
  final RoomProvider provider;
  final bool videoLoaded;
  final bool isPlaying;
  final bool controlsVisible;
  final Duration position;
  final Duration duration;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onToggleControls;
  final VoidCallback onPickFile;
  final ValueChanged<double> onSeek;
  final String? selectedFileName;

  const VideoPlayerWidget({
    super.key,
    required this.videoController,
    required this.provider,
    required this.videoLoaded,
    required this.isPlaying,
    required this.controlsVisible,
    required this.position,
    required this.duration,
    required this.onTogglePlayPause,
    required this.onToggleControls,
    required this.onPickFile,
    required this.onSeek,
    this.selectedFileName,
  });

  @override
  Widget build(BuildContext context) {
    if (!videoLoaded) {
      return _buildEmptyState();
    }

    return GestureDetector(
      onTap: onToggleControls,
      onDoubleTap: onTogglePlayPause,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Video(
              controller: videoController,
              fill: Colors.black,
              controls: NoVideoControls,
            ),
          ),
          if (controlsVisible)
            Center(
              child: AnimatedOpacity(
                opacity: controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: GestureDetector(
                  onTap: onTogglePlayPause,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
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

  Widget _buildEmptyState() {
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
                onPressed: onPickFile,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Playback controls bar (seek slider + play/pause + time).
class PlaybackControlsWidget extends StatelessWidget {
  final bool videoLoaded;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final VoidCallback onTogglePlayPause;
  final ValueChanged<double> onSeek;
  final String? selectedFileName;

  const PlaybackControlsWidget({
    super.key,
    required this.videoLoaded,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.onTogglePlayPause,
    required this.onSeek,
    this.selectedFileName,
  });

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (!videoLoaded) return const SizedBox.shrink();

    final totalSec = duration.inSeconds.toDouble();
    final posSec = position.inSeconds.toDouble().clamp(0.0, totalSec);

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
              onChanged: onSeek,
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: onTogglePlayPause,
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: AppTheme.textPrimary,
                  size: 28,
                ),
              ),
              Text(
                '${_formatDuration(position)} / ${_formatDuration(duration)}',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              if (selectedFileName != null)
                Flexible(
                  child: Text(
                    selectedFileName!,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(width: 8),
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
}
