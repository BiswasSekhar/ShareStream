import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../providers/room_provider.dart';
import '../services/socket_service.dart';
import 'server_status_dialog.dart';

/// Top navigation bar for the room screen.
class TopBarWidget extends StatelessWidget {
  final RoomProvider provider;
  final bool showParticipants;
  final bool showChat;
  final VoidCallback onLeave;
  final VoidCallback onToggleVideoCall;
  final VoidCallback onToggleParticipants;
  final VoidCallback onToggleChat;
  final int pendingJoinRequests;

  const TopBarWidget({
    super.key,
    required this.provider,
    required this.showParticipants,
    required this.showChat,
    required this.onLeave,
    required this.onToggleVideoCall,
    required this.onToggleParticipants,
    required this.onToggleChat,
    this.pendingJoinRequests = 0,
  });

  void _copyRoomCode(BuildContext context) {
    final code = provider.roomCode;
    final url = provider.serverUrl;
    if (code != null) {
      final copyText = url != null ? '$url#$code' : code;
      Clipboard.setData(ClipboardData(text: copyText));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: AppTheme.success, size: 18),
              const SizedBox(width: 10),
              const Expanded(child: Text('Room link copied! Share this with your friends to let them join.')),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
            onPressed: onLeave,
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
          Tooltip(
            message: 'Copy Invite Link',
            child: GestureDetector(
              onTap: () => _copyRoomCode(context),
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
          ),
          const Spacer(),
          // Participant count
          ValueListenableBuilder<List<Participant>>(
            valueListenable: provider.participants,
            builder: (_, participants, __) {
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
            builder: (_, inCall, __) {
              return IconButton(
                onPressed: onToggleVideoCall,
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
          // Toggle participants with pending badge
          Stack(
            children: [
              IconButton(
                onPressed: onToggleParticipants,
                icon: Icon(
                  Icons.people_alt_rounded,
                  size: 20,
                  color: showParticipants ? AppTheme.primary : AppTheme.textMuted,
                ),
                tooltip: 'Participants',
              ),
              if (pendingJoinRequests > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppTheme.error,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$pendingJoinRequests',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Toggle chat
          IconButton(
            onPressed: onToggleChat,
            icon: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 20,
              color: showChat ? AppTheme.primary : AppTheme.textMuted,
            ),
            tooltip: 'Chat',
          ),
          // Server Status
          IconButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const ServerStatusDialog(),
            ),
            icon: const Icon(
              Icons.dns_rounded,
              size: 20,
              color: AppTheme.textMuted,
            ),
            tooltip: 'Server Status',
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.3, duration: 300.ms);
  }
}
