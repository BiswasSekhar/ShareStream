import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../providers/room_provider.dart';
import '../services/socket_service.dart';
import 'common_widgets.dart';

/// Side panel containing participants list and chat area.
/// Now a StatefulWidget to support auto-scroll and unread tracking.
class SidePanelWidget extends StatefulWidget {
  final RoomProvider provider;
  final bool showChat;
  final bool showParticipants;
  final VoidCallback onShowParticipants;
  final VoidCallback onShowChat;
  final TextEditingController chatController;
  final ScrollController chatScrollController;
  final VoidCallback onSendMessage;

  const SidePanelWidget({
    super.key,
    required this.provider,
    required this.showChat,
    required this.showParticipants,
    required this.onShowParticipants,
    required this.onShowChat,
    required this.chatController,
    required this.chatScrollController,
    required this.onSendMessage,
  });

  @override
  State<SidePanelWidget> createState() => _SidePanelWidgetState();
}

class _SidePanelWidgetState extends State<SidePanelWidget> {
  int _lastSeenMessageCount = 0;

  @override
  void initState() {
    super.initState();
    widget.provider.messages.addListener(_onMessagesChanged);
    _lastSeenMessageCount = widget.provider.messages.value.length;
  }

  @override
  void dispose() {
    widget.provider.messages.removeListener(_onMessagesChanged);
    super.dispose();
  }

  void _onMessagesChanged() {
    if (widget.showChat) {
      // Auto-scroll to bottom when chat is visible
      _lastSeenMessageCount = widget.provider.messages.value.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.chatScrollController.hasClients) {
          widget.chatScrollController.animateTo(
            widget.chatScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
    if (mounted) setState(() {});
  }

  int get _unreadCount {
    final total = widget.provider.messages.value.length;
    if (widget.showChat) return 0;
    return (total - _lastSeenMessageCount).clamp(0, 99);
  }

  @override
  void didUpdateWidget(covariant SidePanelWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When switching to chat tab, mark as read & scroll to bottom
    if (widget.showChat && !oldWidget.showChat) {
      _lastSeenMessageCount = widget.provider.messages.value.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.chatScrollController.hasClients) {
          widget.chatScrollController.jumpTo(
            widget.chatScrollController.position.maxScrollExtent,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  widget.showParticipants,
                  widget.onShowParticipants,
                ),
                const SizedBox(width: 4),
                _buildPanelTab(
                  'Chat',
                  Icons.chat_bubble_outline_rounded,
                  widget.showChat,
                  widget.onShowChat,
                  badge: _unreadCount,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.divider),
          // Content
          Expanded(
            child: widget.showChat
                ? _buildChatArea()
                : _buildParticipantList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelTab(String label, IconData icon, bool active, VoidCallback onTap, {int badge = 0}) {
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
              if (badge > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge > 99 ? '99+' : '$badge',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParticipantList() {
    return ValueListenableBuilder<List<Participant>>(
      valueListenable: widget.provider.participants,
      builder: (_, participants, __) {
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
          separatorBuilder: (_, __) => const SizedBox(height: 8),
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

  Widget _buildChatArea() {
    return Column(
      children: [
        // Messages
        Expanded(
          child: ValueListenableBuilder<List<ChatMessage>>(
            valueListenable: widget.provider.messages,
            builder: (_, messages, __) {
              if (messages.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 36, color: AppTheme.textMuted.withValues(alpha: 0.4)),
                      const SizedBox(height: 8),
                      const Text(
                        'Start the conversation!',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
                      ),
                    ],
                  ),
                );
              }
              return ListView.builder(
                controller: widget.chatScrollController,
                padding: const EdgeInsets.all(AppTheme.spacingMD),
                itemCount: messages.length,
                itemBuilder: (_, i) {
                  final msg = messages[i];
                  final prevMsg = i > 0 ? messages[i - 1] : null;
                  final showSender = prevMsg == null || prevMsg.senderId != msg.senderId;
                  return _buildChatBubble(msg, showSender: showSender);
                },
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
                    controller: widget.chatController,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    maxLines: null,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(color: AppTheme.textMuted),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (_) => widget.onSendMessage(),
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
                  onPressed: widget.onSendMessage,
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

  Widget _buildChatBubble(ChatMessage msg, {bool showSender = true}) {
    final isMe = msg.isMe;
    return Padding(
      padding: EdgeInsets.only(
        bottom: showSender ? 8 : 2,
        top: showSender ? 4 : 0,
      ),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe && showSender)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ParticipantAvatar(name: msg.senderName, size: 28),
            )
          else if (!isMe)
            const SizedBox(width: 36), // Space for hidden avatar
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
                  bottomLeft: Radius.circular(isMe ? 16 : (showSender ? 4 : 16)),
                  bottomRight: Radius.circular(isMe ? (showSender ? 4 : 16) : 16),
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
                  if (!isMe && showSender)
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
                  const SizedBox(height: 3),
                  // Timestamp
                  Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Text(
                      _formatTimestamp(msg.timestamp),
                      style: TextStyle(
                        color: AppTheme.textMuted.withValues(alpha: 0.6),
                        fontSize: 10,
                      ),
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

  String _formatTimestamp(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) {
      final h = time.hour.toString().padLeft(2, '0');
      final m = time.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '${time.day}/${time.month} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }
}

/// Horizontal participant strip for narrow/mobile layouts.
class ParticipantStripWidget extends StatelessWidget {
  final RoomProvider provider;

  const ParticipantStripWidget({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Participant>>(
      valueListenable: provider.participants,
      builder: (_, participants, __) {
        if (participants.isEmpty) return const SizedBox.shrink();

        return Container(
          height: 72,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMD),
            itemCount: participants.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
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
}
