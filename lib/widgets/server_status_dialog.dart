import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../providers/room_provider.dart';
import '../theme/app_theme.dart';
import '../utils/app_logger.dart';

class ServerStatusDialog extends StatefulWidget {
  const ServerStatusDialog({super.key});

  @override
  State<ServerStatusDialog> createState() => _ServerStatusDialogState();
}

class _ServerStatusDialogState extends State<ServerStatusDialog> {
  String _torrentLogs = 'Loading torrent logs...';
  String _appLogs = 'Loading app logs...';
  bool _showAppLogs = true;
  Timer? _refreshTimer;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) => _loadLogs());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }
  Future<void> _loadLogs() async {
    // Load App Logs
    final appLogs = await AppLogger.getLogs();
    if (mounted) setState(() => _appLogs = appLogs);

    // Load Torrent Logs
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/torrent.log');
      if (await file.exists()) {
        final lines = await file.readAsLines();
        final recent = lines.length > 50 ? lines.sublist(lines.length - 50) : lines;
        if (mounted) setState(() => _torrentLogs = recent.join('\\n'));
      } else {
        if (mounted) setState(() => _torrentLogs = 'No log file found at ${file.path}');
      }
    } catch (e) {
      if (mounted) setState(() => _torrentLogs = 'Failed to read torrent logs: $e');
    }
  }

  Future<void> _clearLogs() async {
    if (_showAppLogs) {
      await AppLogger.clearLogs();
    } else {
      try {
        final dir = await getApplicationSupportDirectory();
        final file = File('${dir.path}/torrent.log');
        if (await file.exists()) await file.writeAsString('');
      } catch (_) {}
    }
    await _loadLogs();
  }

  @override
  Widget build(BuildContext context) {
    final torrent = context.watch<RoomProvider>().torrent;

    return Dialog(
      backgroundColor: AppTheme.bgSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 800,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Diagnostics & Logs',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Status Grid
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Col: Metrics
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      _buildMetricTile(
                        'Status', 
                        torrent.isReady.value ? 'Ready' : 'Initializing...',
                         icon: torrent.isReady.value ? Icons.check_circle : Icons.hourglass_empty,
                         color: torrent.isReady.value ? AppTheme.success : AppTheme.warning,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _buildMetricTile(
                            'Peers', 
                            '${torrent.numPeers.value}',
                            icon: Icons.people,
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricTile(
                            'Speed', 
                            _formatSpeed(torrent.downloadSpeed.value),
                            icon: Icons.speed,
                          )),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildMetricTile(
                        'Progress', 
                        '${(torrent.progress.value * 100).toStringAsFixed(1)}%',
                        icon: Icons.download,
                        progress: torrent.progress.value,
                      ),
                      const SizedBox(height: 12),
                      if (torrent.lastError.value != null)
                        _buildMetricTile(
                          'Error',
                          torrent.lastError.value!,
                          icon: Icons.error_outline,
                          color: AppTheme.error,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                // Right Col: Details
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.bgElevated,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDetailRow('Server URL', torrent.serverUrl.value ?? 'Not running'),
                        const SizedBox(height: 8),
                        _buildDetailRow('Magnet URI', torrent.magnetUri.value ?? 'None'),
                        const SizedBox(height: 8),
                         _buildDetailRow('Torrent Name', torrent.torrentName.value ?? 'None'),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            Row(
              children: [
                _buildTab('App Events & Errors', _showAppLogs, () => setState(() => _showAppLogs = true)),
                const SizedBox(width: 8),
                _buildTab('Torrent Engine', !_showAppLogs, () => setState(() => _showAppLogs = false)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _clearLogs,
                  icon: const Icon(Icons.delete_outline, size: 16, color: AppTheme.error),
                  label: const Text('Clear Active Log', style: TextStyle(color: AppTheme.error)),
                  style: TextButton.styleFrom(
                    backgroundColor: AppTheme.error.withValues(alpha: 0.1),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border.withValues(alpha: 0.3)),
                ),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  reverse: true,
                  child: Text(
                    _showAppLogs ? _appLogs : _torrentLogs,
                    style: const TextStyle(
                      color: Color(0xFF00FF00),
                      fontFamily: 'Consolas',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.2) : AppTheme.bgElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, {IconData? icon, Color? color, double? progress}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgElevated,
        borderRadius: BorderRadius.circular(8),
        border: color != null ? Border.all(color: color.withValues(alpha: 0.3)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: color ?? AppTheme.textMuted),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color ?? AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: AppTheme.bgDeep,
              color: AppTheme.primary,
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
            fontFamily: 'Consolas',
          ),
        ),
      ],
    );
  }

  String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec < 1024) return '$bytesPerSec B/s';
    if (bytesPerSec < 1024 * 1024) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}
