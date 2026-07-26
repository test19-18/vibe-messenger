import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/vibe_tokens.dart';
import '../../domain/chat_message.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.isMine,
    super.key,
    this.replyMessage,
    this.onLongPress,
  });

  final ChatMessage message;
  final bool isMine;
  final ChatMessage? replyMessage;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = message.isDeleted
        ? context.tokens.surfaceElevated
        : isMine
        ? context.tokens.accent
        : context.tokens.surfaceElevated;
    final foreground = message.isDeleted
        ? context.tokens.textSecondary
        : context.tokens.textPrimary;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
          ),
          margin: EdgeInsets.only(
            left: isMine ? AppSpacing.xl : 0,
            right: isMine ? 0 : AppSpacing.xl,
            bottom: AppSpacing.xs,
          ),
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(AppRadii.md),
              topRight: const Radius.circular(AppRadii.md),
              bottomLeft: Radius.circular(isMine ? AppRadii.md : 5),
              bottomRight: Radius.circular(isMine ? 5 : AppRadii.md),
            ),
            border: isMine || message.isDeleted
                ? null
                : Border.all(color: context.tokens.separator),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (replyMessage != null && !message.isDeleted) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    border: const Border(
                      left: BorderSide(color: Colors.white, width: 3),
                    ),
                  ),
                  child: Text(
                    replyMessage!.visibleBody,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground.withValues(alpha: 0.82),
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              Text(
                message.visibleBody,
                style: TextStyle(
                  color: foreground,
                  fontSize: 16,
                  height: 1.28,
                  fontStyle: message.isDeleted
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (message.expiresAt != null) ...[
                    Icon(
                      Icons.timer_outlined,
                      size: 13,
                      color: foreground.withValues(alpha: 0.65),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      DateFormat('dd.MM HH:mm').format(message.expiresAt!),
                      style: TextStyle(
                        color: foreground.withValues(alpha: 0.65),
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  if (message.isEdited) ...[
                    Text(
                      'изменено',
                      style: TextStyle(
                        color: foreground.withValues(alpha: 0.65),
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    DateFormat('HH:mm').format(message.createdAt),
                    style: TextStyle(
                      color: foreground.withValues(alpha: 0.65),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isMine && !message.isDeleted) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.done_all_rounded,
                      size: 15,
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
