import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/vibe_tokens.dart';
import '../../../../core/widgets/bubble_shape.dart';
import '../../../../core/widgets/service_pill.dart';
import '../../domain/chat_message.dart';
import '../../domain/message_details.dart';
import 'formatted_message_text.dart';
import 'message_meta.dart';

class EnhancedMessageBubble extends StatelessWidget {
  const EnhancedMessageBubble({
    required this.message,
    required this.isMine,
    required this.selected,
    required this.isRead,
    required this.reactions,
    required this.currentUserId,
    required this.onTap,
    required this.onLongPress,
    required this.onReaction,
    required this.onVote,
    required this.onDownload,
    super.key,
    this.replyMessage,
    this.attachment,
    this.poll,
    this.pinned = false,
    this.showTail = true,
    this.isFirstInGroup = true,
  });

  final ChatMessage message;
  final ChatMessage? replyMessage;
  final MessageAttachment? attachment;
  final PollDetails? poll;
  final bool isMine;
  final bool selected;
  final bool isRead;
  final bool pinned;
  final List<MessageReaction> reactions;
  final String? currentUserId;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReaction;
  final ValueChanged<PollOption> onVote;
  final Future<Uint8List> Function(MessageAttachment attachment) onDownload;

  /// Last message of a same-sender streak — only that one grows a tail.
  final bool showTail;

  /// First message of a streak gets the wider gap above it.
  final bool isFirstInGroup;

  bool get _isTextLike => message.kind == MessageKind.text || message.isDeleted;

  @override
  Widget build(BuildContext context) {
    // System events read as conversation-level notices, not as anyone's message.
    if (message.kind == MessageKind.system && !message.isDeleted) {
      return ServicePill(label: message.visibleBody);
    }

    final tokens = context.tokens;
    final foreground = message.isDeleted
        ? tokens.bubbleMeta(isMine: isMine)
        : tokens.bubbleForeground(isMine: isMine);

    final grouped = <String, List<MessageReaction>>{};
    for (final reaction in reactions) {
      grouped.putIfAbsent(reaction.emoji, () => []).add(reaction);
    }

    final metaWidth = MessageMeta.estimateWidth(
      context,
      isMine: isMine,
      isEdited: message.isEdited,
      isPinned: pinned,
      hasExpiry: message.expiresAt != null,
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (replyMessage != null && !message.isDeleted) ...[
          _ReplyPreview(message: replyMessage!, isMine: isMine),
          const SizedBox(height: 5),
        ],
        if (message.isDeleted)
          Padding(
            padding: EdgeInsets.only(right: metaWidth),
            child: Text(
              message.visibleBody,
              style: TextStyle(color: foreground, fontStyle: FontStyle.italic),
            ),
          )
        else
          _MessagePayload(
            message: message,
            attachment: attachment,
            poll: poll,
            foreground: foreground,
            isMine: isMine,
            // Only flowing text can wrap around the timestamp; other payloads
            // reserve a whole line for it instead.
            trailingGap: _isTextLike ? metaWidth : 0,
            onVote: onVote,
            onDownload: onDownload,
          ),
        if (!_isTextLike) SizedBox(height: 14, width: metaWidth),
        if (grouped.isNotEmpty) ...[
          const SizedBox(height: 6),
          _Reactions(
            grouped: grouped,
            isMine: isMine,
            currentUserId: currentUserId,
            onReaction: onReaction,
          ),
        ],
      ],
    );

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      decoration: ShapeDecoration(
        shape: BubbleShape(
          side: isMine ? BubbleTailSide.right : BubbleTailSide.left,
          hasTail: showTail,
        ),
        color: isMine ? null : tokens.bubbleIn,
        gradient: isMine
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [tokens.bubbleOut, tokens.bubbleOutEnd],
              )
            : null,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: tokens.brightness == Brightness.dark ? 0.22 : 0.07,
            ),
            blurRadius: 1.5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: Stack(
          children: [
            body,
            Positioned(
              right: 0,
              bottom: 0,
              child: MessageMeta(
                createdAt: message.createdAt,
                isMine: isMine,
                isEdited: message.isEdited,
                isRead: isRead,
                isPinned: pinned,
                expiresAt: message.expiresAt,
                showStatus: !message.isDeleted,
              ),
            ),
          ],
        ),
      ),
    );

    return Semantics(
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ColoredBox(
          // Selection tints the whole row rather than recolouring the bubble,
          // so the sender's own colour stays readable while selecting.
          color: selected ? tokens.selectionOverlay : Colors.transparent,
          child: Padding(
            padding: EdgeInsets.only(
              top: isFirstInGroup ? 6 : 1.5,
              bottom: 1.5,
              left: isMine ? AppSpacing.xl : AppSpacing.xs,
              right: isMine ? AppSpacing.xs : AppSpacing.xl,
            ),
            child: Align(
              alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
              child: bubble,
            ),
          ),
        ),
      ),
    );
  }
}

/// Quoted message stripe shown above a reply.
class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final accent = tokens.bubbleAccent(isMine: isMine);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.xs),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Text(
        message.visibleBody,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: tokens.bubbleForeground(isMine: isMine).withValues(alpha: 0.9),
          fontSize: 13,
          height: 1.2,
        ),
      ),
    );
  }
}

/// Reaction chips under the message body.
class _Reactions extends StatelessWidget {
  const _Reactions({
    required this.grouped,
    required this.isMine,
    required this.currentUserId,
    required this.onReaction,
  });

  final Map<String, List<MessageReaction>> grouped;
  final bool isMine;
  final String? currentUserId;
  final ValueChanged<String> onReaction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final accent = tokens.bubbleAccent(isMine: isMine);
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: grouped.entries.map((entry) {
        final selectedByMe = entry.value.any(
          (reaction) => reaction.userId == currentUserId,
        );
        return InkWell(
          onTap: () => onReaction(entry.key),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: selectedByMe ? 0.28 : 0.12),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              '${entry.key} ${entry.value.length}',
              style: TextStyle(
                color: tokens.bubbleForeground(isMine: isMine),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _MessagePayload extends StatelessWidget {
  const _MessagePayload({
    required this.message,
    required this.attachment,
    required this.poll,
    required this.foreground,
    required this.isMine,
    required this.trailingGap,
    required this.onVote,
    required this.onDownload,
  });

  final ChatMessage message;
  final MessageAttachment? attachment;
  final PollDetails? poll;
  final Color foreground;
  final bool isMine;
  final double trailingGap;
  final ValueChanged<PollOption> onVote;
  final Future<Uint8List> Function(MessageAttachment attachment) onDownload;

  @override
  Widget build(BuildContext context) {
    switch (message.kind) {
      case MessageKind.image:
        return _ImagePayload(
          message: message,
          attachment: attachment,
          foreground: foreground,
        );
      case MessageKind.file:
      case MessageKind.video:
      case MessageKind.audio:
        return _FilePayload(
          message: message,
          attachment: attachment,
          isMine: isMine,
          onDownload: onDownload,
        );
      case MessageKind.voice:
        return _VoicePayload(attachment: attachment, isMine: isMine);
      case MessageKind.location:
        final latitude = message.metadata['latitude'];
        final longitude = message.metadata['longitude'];
        return _AttachmentRow(
          icon: Icons.location_on_rounded,
          isMine: isMine,
          title: message.body.isEmpty
              ? context.tr(ru: 'Геопозиция', en: 'Location')
              : message.body,
          subtitle: '$latitude, $longitude',
          onTap: () =>
              Clipboard.setData(ClipboardData(text: '$latitude,$longitude')),
        );
      case MessageKind.contact:
        return _AttachmentRow(
          icon: Icons.person_rounded,
          isMine: isMine,
          title: '${message.metadata['name'] ?? message.body}',
          subtitle: '${message.metadata['value'] ?? ''}',
        );
      case MessageKind.poll:
        final value = poll;
        if (value == null) {
          return Text(message.visibleBody, style: TextStyle(color: foreground));
        }
        return _PollPayload(
          poll: value,
          foreground: foreground,
          isMine: isMine,
          onVote: onVote,
        );
      case MessageKind.text:
      case MessageKind.system:
        return FormattedMessageText(
          text: message.visibleBody,
          trailingGap: trailingGap,
          style: TextStyle(color: foreground, fontSize: 16, height: 1.25),
        );
    }
  }
}

/// Shared layout for non-media attachments: round icon, title, caption.
class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    required this.icon,
    required this.title,
    required this.isMine,
    this.subtitle,
    this.leading,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isMine;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final foreground = tokens.bubbleForeground(isMine: isMine);
    final accent = tokens.bubbleAccent(isMine: isMine);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading ??
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: Colors.white),
              ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.bubbleMeta(isMine: isMine),
                      fontSize: 12.5,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PollPayload extends StatelessWidget {
  const _PollPayload({
    required this.poll,
    required this.foreground,
    required this.isMine,
    required this.onVote,
  });

  final PollDetails poll;
  final Color foreground;
  final bool isMine;
  final ValueChanged<PollOption> onVote;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final accent = tokens.bubbleAccent(isMine: isMine);
    final total = poll.options.fold<int>(
      0,
      (sum, option) => sum + option.voteCount,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          poll.question,
          style: TextStyle(
            color: foreground,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          poll.isAnonymous
              ? context.tr(ru: 'Анонимный опрос', en: 'Anonymous poll')
              : context.tr(ru: 'Открытый опрос', en: 'Public poll'),
          style: TextStyle(
            color: tokens.bubbleMeta(isMine: isMine),
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final option in poll.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: poll.isClosed ? null : () => onVote(option),
              borderRadius: BorderRadius.circular(AppRadii.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        option.selectedByMe
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 18,
                        color: option.selectedByMe
                            ? accent
                            : tokens.bubbleMeta(isMine: isMine),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          option.text,
                          style: TextStyle(color: foreground, fontSize: 15),
                        ),
                      ),
                      Text(
                        total == 0
                            ? '0%'
                            : '${(option.voteCount * 100 / total).round()}%',
                        style: TextStyle(
                          color: tokens.bubbleMeta(isMine: isMine),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : option.voteCount / total,
                      minHeight: 4,
                      backgroundColor: accent.withValues(alpha: 0.18),
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Text(
          '${context.tr(ru: 'Голосов', en: 'Votes')}: $total'
          '${poll.isClosed ? ' · ${context.tr(ru: 'завершён', en: 'closed')}' : ''}',
          style: TextStyle(
            color: tokens.bubbleMeta(isMine: isMine),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _ImagePayload extends StatelessWidget {
  const _ImagePayload({
    required this.message,
    required this.attachment,
    required this.foreground,
  });

  final ChatMessage message;
  final MessageAttachment? attachment;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final url = attachment?.signedUrl;
    final placeholder = SizedBox(
      width: 220,
      height: 150,
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 40,
          color: foreground.withValues(alpha: 0.6),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (url == null)
          placeholder
        else
          GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => Dialog.fullscreen(
                backgroundColor: Colors.black,
                child: Stack(
                  children: [
                    Center(child: InteractiveViewer(child: Image.network(url))),
                    SafeArea(
                      child: IconButton.filled(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: context.tr(ru: 'Закрыть', en: 'Close'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.sm),
              child: Image.network(
                url,
                width: 250,
                height: 190,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : SizedBox(
                        width: 250,
                        height: 190,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: progress.expectedTotalBytes == null
                                ? null
                                : progress.cumulativeBytesLoaded /
                                      progress.expectedTotalBytes!,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        if (message.body.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            message.body,
            style: TextStyle(color: foreground, fontSize: 15.5, height: 1.25),
          ),
        ],
      ],
    );
  }
}

class _FilePayload extends StatefulWidget {
  const _FilePayload({
    required this.message,
    required this.attachment,
    required this.isMine,
    required this.onDownload,
  });

  final ChatMessage message;
  final MessageAttachment? attachment;
  final bool isMine;
  final Future<Uint8List> Function(MessageAttachment attachment) onDownload;

  @override
  State<_FilePayload> createState() => _FilePayloadState();
}

class _FilePayloadState extends State<_FilePayload> {
  bool _busy = false;

  Future<void> _open() async {
    final attachment = widget.attachment;
    if (attachment == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await widget.onDownload(attachment);
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/${attachment.fileName ?? attachment.id}',
      );
      await file.writeAsBytes(bytes, flush: true);
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                ru: 'Не удалось скачать или открыть файл.',
                en: 'Could not download or open the file.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final attachment = widget.attachment;
    return _AttachmentRow(
      icon: Icons.insert_drive_file_rounded,
      isMine: widget.isMine,
      title: attachment?.fileName ?? widget.message.visibleBody,
      subtitle: _fileSize(context, attachment?.byteSize),
      onTap: _busy ? null : _open,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: tokens.bubbleAccent(isMine: widget.isMine),
          shape: BoxShape.circle,
        ),
        child: _busy
            ? const Padding(
                padding: EdgeInsets.all(11),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(
                Icons.arrow_downward_rounded,
                size: 20,
                color: Colors.white,
              ),
      ),
    );
  }
}

class _VoicePayload extends StatefulWidget {
  const _VoicePayload({required this.attachment, required this.isMine});

  final MessageAttachment? attachment;
  final bool isMine;

  @override
  State<_VoicePayload> createState() => _VoicePayloadState();
}

class _VoicePayloadState extends State<_VoicePayload> {
  final AudioPlayer _player = AudioPlayer();
  bool _loading = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final url = widget.attachment?.signedUrl;
    if (url == null) {
      return;
    }
    if (_player.playing) {
      await _player.pause();
      return;
    }
    setState(() => _loading = true);
    try {
      if (_player.duration == null) {
        await _player.setUrl(url);
      }
      unawaited(_player.play());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final accent = tokens.bubbleAccent(isMine: widget.isMine);
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: true,
              label: playing
                  ? context.tr(ru: 'Пауза', en: 'Pause')
                  : context.tr(ru: 'Воспроизвести', en: 'Play'),
              child: InkWell(
                onTap: _loading ? null : _toggle,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(11),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                        ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _Waveform(
              seed: widget.attachment?.id ?? '',
              color: accent,
              progress: playing ? 1 : 0,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              _duration(widget.attachment?.durationMs),
              style: TextStyle(
                color: tokens.bubbleMeta(isMine: widget.isMine),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Static bar chart standing in for the real waveform.
///
/// Heights are derived from the attachment id so a clip always looks the same;
/// decoding audio just to draw a preview is not worth the cost here.
class _Waveform extends StatelessWidget {
  const _Waveform({
    required this.seed,
    required this.color,
    required this.progress,
  });

  final String seed;
  final Color color;
  final double progress;

  static const int _barCount = 24;

  @override
  Widget build(BuildContext context) {
    var hash = seed.isEmpty ? 7 : 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return SizedBox(
      height: 24,
      width: _barCount * 4.0,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_barCount, (index) {
          final magnitude = ((hash >> (index % 24)) ^ (index * 37)) % 100;
          final height = 5 + magnitude / 100 * 15;
          final played = index / _barCount <= progress;
          return Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Container(
              width: 2,
              height: height,
              decoration: BoxDecoration(
                color: color.withValues(alpha: played ? 1 : 0.4),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          );
        }),
      ),
    );
  }
}

String _fileSize(BuildContext context, int? bytes) {
  if (bytes == null) {
    return context.tr(ru: 'Файл', en: 'File');
  }
  if (bytes < 1024) {
    return '$bytes ${context.tr(ru: 'Б', en: 'B')}';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} ${context.tr(ru: 'КБ', en: 'KB')}';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} '
      '${context.tr(ru: 'МБ', en: 'MB')}';
}

String _duration(int? milliseconds) {
  final duration = Duration(milliseconds: milliseconds ?? 0);
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${duration.inMinutes}:$seconds';
}
