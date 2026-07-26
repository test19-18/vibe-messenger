import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/vibe_tokens.dart';

/// Timestamp, edit marker and delivery status shown in a bubble's bottom-right
/// corner.
///
/// Kept separate from the bubble so its width can be estimated up front and
/// reserved at the end of the message text — that is what keeps a short message
/// and its time on one line.
class MessageMeta extends StatelessWidget {
  const MessageMeta({
    required this.createdAt,
    required this.isMine,
    super.key,
    this.isEdited = false,
    this.isRead = false,
    this.isPinned = false,
    this.expiresAt,
    this.showStatus = true,
  });

  final DateTime createdAt;
  final bool isMine;
  final bool isEdited;
  final bool isRead;
  final bool isPinned;
  final DateTime? expiresAt;

  /// Delivery ticks only make sense on messages the current user sent.
  final bool showStatus;

  static const double _fontSize = 11;

  /// Rough width of the rendered row, used to reserve trailing space in the
  /// message text. Overshooting slightly is harmless; undershooting would let
  /// the text run under the timestamp.
  static double estimateWidth(
    BuildContext context, {
    required bool isMine,
    bool isEdited = false,
    bool isPinned = false,
    bool hasExpiry = false,
  }) {
    var width = 34.0; // "HH:mm"
    if (isMine) {
      width += 18; // delivery ticks
    }
    if (isEdited) {
      width += context.tr(ru: 'изм.', en: 'edited').length * 5.5 + 4;
    }
    if (isPinned) {
      width += 16;
    }
    if (hasExpiry) {
      width += 16;
    }
    // Gap between the last word and the timestamp, plus text scaling.
    return MediaQuery.textScalerOf(context).scale(width) + 8;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = tokens.bubbleMeta(isMine: isMine);
    final textStyle = TextStyle(
      color: color,
      fontSize: _fontSize,
      fontWeight: FontWeight.w500,
      height: 1,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (isPinned) ...[
          Icon(Icons.push_pin_rounded, size: 12, color: color),
          const SizedBox(width: 3),
        ],
        if (expiresAt != null) ...[
          Icon(Icons.local_fire_department_rounded, size: 13, color: color),
          const SizedBox(width: 3),
        ],
        if (isEdited) ...[
          Text(
            context.tr(ru: 'изм.', en: 'edited'),
            style: textStyle,
          ),
          const SizedBox(width: 4),
        ],
        Text(
          DateFormat('HH:mm', context.dateLocale).format(createdAt),
          style: textStyle,
        ),
        if (isMine && showStatus) ...[
          const SizedBox(width: 3),
          Icon(
            isRead ? Icons.done_all_rounded : Icons.done_rounded,
            size: 15,
            color: color,
          ),
        ],
      ],
    );
  }
}
