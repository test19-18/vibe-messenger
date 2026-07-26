import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/vibe_tokens.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../domain/conversation_summary.dart';

/// A single row of the chat list.
///
/// Layout follows the two-line messenger convention: title and timestamp on the
/// first line, message preview and unread badge on the second, with the badge
/// muted when the chat is silenced.
class ConversationTile extends StatelessWidget {
  const ConversationTile({
    required this.conversation,
    required this.onTap,
    super.key,
    this.onLongPress,
    this.selected = false,
  });

  final ConversationSummary conversation;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final draft = conversation.draft?.trim();
    final hasDraft = draft != null && draft.isNotEmpty;
    final unread = conversation.unreadCount;
    final peer = conversation.peer;

    final preview = hasDraft
        ? draft
        : conversation.lastMessage ??
              context.tr(ru: 'Нет сообщений', en: 'No messages yet');

    return Semantics(
      button: true,
      selected: selected,
      label: unread > 0
          ? '${conversation.visibleTitle}, '
                '${context.tr(ru: 'непрочитанных', en: 'unread')}: $unread'
          : conversation.visibleTitle,
      child: Material(
        color: selected ? tokens.accentSoft : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AppAvatar(
                  label: conversation.visibleTitle,
                  imageUrl: conversation.visibleAvatarUrl,
                  seed: conversation.id,
                  radius: AppSizes.chatListAvatar / 2,
                  // Only a live "online" reads as information; a permanent
                  // grey dot on every row is just noise.
                  showPresence:
                      !conversation.isGroup && (peer?.isOnline ?? false),
                  isOnline: true,
                  presenceRingColor: tokens.background,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (conversation.isGroup)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.groups_rounded,
                                size: 16,
                                color: tokens.textSecondary,
                              ),
                            ),
                          // Title takes the slack so the timestamp stays
                          // pinned to the right edge of the row.
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    conversation.visibleTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (conversation.isMuted)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Icon(
                                      Icons.volume_off_rounded,
                                      size: 16,
                                      color: tokens.textTertiary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            formatChatListTimestamp(
                              conversation.lastMessageAt ??
                                  conversation.updatedAt,
                              locale: context.dateLocale,
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12.5,
                              color: tokens.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  if (hasDraft)
                                    TextSpan(
                                      text:
                                          '${context.tr(ru: 'Черновик', en: 'Draft')}: ',
                                      style: TextStyle(color: tokens.danger),
                                    ),
                                  TextSpan(text: preview),
                                ],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 14.5,
                                color: tokens.textSecondary,
                                height: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          _TrailingMarks(
                            unread: unread,
                            muted: conversation.isMuted,
                            pinned: conversation.isPinned,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Unread badge, or a pin when the chat is pinned and fully read.
class _TrailingMarks extends StatelessWidget {
  const _TrailingMarks({
    required this.unread,
    required this.muted,
    required this.pinned,
  });

  final int unread;
  final bool muted;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (unread > 0) {
      return Container(
        constraints: const BoxConstraints(minWidth: 22),
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: muted ? tokens.badgeMuted : tokens.badge,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Text(
          unread > 99 ? '99+' : '$unread',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: tokens.onBadge,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      );
    }
    if (pinned) {
      return Icon(Icons.push_pin_rounded, size: 17, color: tokens.textTertiary);
    }
    return const SizedBox.shrink();
  }
}

/// Time today, weekday within the last week, then a date — the progression
/// people expect from a chat list.
String formatChatListTimestamp(
  DateTime timestamp, {
  String? locale,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final startOfToday = DateTime(reference.year, reference.month, reference.day);
  final startOfMessage = DateTime(
    timestamp.year,
    timestamp.month,
    timestamp.day,
  );
  final daysApart = startOfToday.difference(startOfMessage).inDays;

  if (daysApart <= 0) {
    return DateFormat('HH:mm', locale).format(timestamp);
  }
  if (daysApart < 7) {
    return DateFormat('E', locale).format(timestamp);
  }
  if (timestamp.year == reference.year) {
    return DateFormat('d MMM', locale).format(timestamp);
  }
  return DateFormat('dd.MM.yy', locale).format(timestamp);
}
