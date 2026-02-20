import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../providers/room_provider.dart';
import '../services/socket_service.dart';
import 'common_widgets.dart';

/// Side panel containing participants list and chat area.
class SidePanelWidget extends StatelessWidget {
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
                  showParticipants,
                  onShowParticipants,
                ),
                const SizedBox(width: 4),
                _buildPanelTab(
                  'Chat',
                  Icons.chat_bubble_outline_rounded,
                  showChat,
                  onShowChat,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.divider),
          // Content
          Expanded(
            child: showChat
                ? _buildChatArea()
                : _buildParticipantList(),
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

  Widget _buildParticipantList() {
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

  Widget _buildChatArea() {
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
                controller: chatScrollController,
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
                    controller: chatController,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(color: AppTheme.textMuted),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (_) => onSendMessage(),
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
                  onPressed: onSendMessage,
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
}

/// Horizontal participant strip for narrow/mobile layouts.
class ParticipantStripWidget extends StatelessWidget {
  final RoomProvider provider;

  const ParticipantStripWidget({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
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
}
