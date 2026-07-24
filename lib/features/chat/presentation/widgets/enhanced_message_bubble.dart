import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/chat_message.dart';
import '../../domain/message_details.dart';
import 'formatted_message_text.dart';

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

  @override
  Widget build(BuildContext context) {
    final bubbleColor = selected
        ? AppColors.purple.withValues(alpha: 0.55)
        : message.isDeleted
        ? AppColors.surfaceHigh
        : isMine
        ? AppColors.electricBlue
        : AppColors.surfaceHigh;
    final foreground = message.isDeleted
        ? AppColors.textSecondary
        : AppColors.textPrimary;
    final grouped = <String, List<MessageReaction>>{};
    for (final reaction in reactions) {
      grouped.putIfAbsent(reaction.emoji, () => []).add(reaction);
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.82,
          ),
          margin: EdgeInsets.only(
            left: isMine ? AppSpacing.xl : 0,
            right: isMine ? 0 : AppSpacing.xl,
            bottom: AppSpacing.xs,
          ),
          padding: const EdgeInsets.fromLTRB(12, 9, 10, 7),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(AppRadii.md),
              topRight: const Radius.circular(AppRadii.md),
              bottomLeft: Radius.circular(isMine ? AppRadii.md : 5),
              bottomRight: Radius.circular(isMine ? 5 : AppRadii.md),
            ),
            border: isMine && !selected
                ? null
                : Border.all(
                    color: selected ? AppColors.purple : AppColors.divider,
                  ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (pinned)
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Icon(Icons.push_pin_rounded, size: 14),
                ),
              if (replyMessage != null && !message.isDeleted) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
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
              if (message.isDeleted)
                Text(
                  message.visibleBody,
                  style: TextStyle(
                    color: foreground,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else ...[
                _MessagePayload(
                  message: message,
                  attachment: attachment,
                  poll: poll,
                  foreground: foreground,
                  onVote: onVote,
                  onDownload: onDownload,
                ),
              ],
              if (grouped.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: selectedByMe
                              ? Colors.white.withValues(alpha: 0.25)
                              : Colors.black.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: Text('${entry.key} ${entry.value.length}'),
                      ),
                    );
                  }).toList(),
                ),
              ],
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
                      context.tr(ru: 'изменено', en: 'edited'),
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
                      isRead ? Icons.done_all_rounded : Icons.done_rounded,
                      size: 15,
                      color: isRead
                          ? AppColors.cyan
                          : Colors.white.withValues(alpha: 0.72),
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

class _MessagePayload extends StatelessWidget {
  const _MessagePayload({
    required this.message,
    required this.attachment,
    required this.poll,
    required this.foreground,
    required this.onVote,
    required this.onDownload,
  });

  final ChatMessage message;
  final MessageAttachment? attachment;
  final PollDetails? poll;
  final Color foreground;
  final ValueChanged<PollOption> onVote;
  final Future<Uint8List> Function(MessageAttachment attachment) onDownload;

  @override
  Widget build(BuildContext context) {
    switch (message.kind) {
      case MessageKind.image:
        return _ImagePayload(message: message, attachment: attachment);
      case MessageKind.file:
      case MessageKind.video:
      case MessageKind.audio:
        return _FilePayload(
          message: message,
          attachment: attachment,
          onDownload: onDownload,
        );
      case MessageKind.voice:
        return _VoicePayload(attachment: attachment);
      case MessageKind.location:
        final latitude = message.metadata['latitude'];
        final longitude = message.metadata['longitude'];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.location_on_rounded, color: Colors.white),
          title: Text(message.body.isEmpty ? 'Геопозиция' : message.body),
          subtitle: Text('$latitude, $longitude'),
          onTap: () =>
              Clipboard.setData(ClipboardData(text: '$latitude,$longitude')),
        );
      case MessageKind.contact:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.contact_page_rounded, color: Colors.white),
          title: Text('${message.metadata['name'] ?? message.body}'),
          subtitle: Text('${message.metadata['value'] ?? ''}'),
        );
      case MessageKind.poll:
        final value = poll;
        if (value == null) {
          return Text(message.visibleBody);
        }
        final total = value.options.fold<int>(
          0,
          (sum, option) => sum + option.voteCount,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value.question,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final option in value.options)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: InkWell(
                  onTap: value.isClosed ? null : () => onVote(option),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: option.selectedByMe
                          ? Colors.white.withValues(alpha: 0.24)
                          : Colors.black.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          option.selectedByMe
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(child: Text(option.text)),
                        Text('${option.voteCount}'),
                      ],
                    ),
                  ),
                ),
              ),
            Text(
              '${value.isAnonymous ? 'Анонимно' : 'Открыто'} · $total голосов'
              '${value.isClosed ? ' · закрыт' : ''}',
              style: TextStyle(
                color: foreground.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
          ],
        );
      case MessageKind.text:
      case MessageKind.system:
        return FormattedMessageText(
          text: message.visibleBody,
          style: TextStyle(color: foreground, fontSize: 16, height: 1.28),
        );
    }
  }
}

class _ImagePayload extends StatelessWidget {
  const _ImagePayload({required this.message, required this.attachment});

  final ChatMessage message;
  final MessageAttachment? attachment;

  @override
  Widget build(BuildContext context) {
    final url = attachment?.signedUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (url == null)
          const SizedBox(
            width: 220,
            height: 140,
            child: Center(child: Icon(Icons.broken_image_outlined, size: 42)),
          )
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
                width: 240,
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(
                  width: 220,
                  height: 140,
                  child: Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
          ),
        if (message.body.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(message.body),
        ],
      ],
    );
  }
}

class _FilePayload extends StatefulWidget {
  const _FilePayload({
    required this.message,
    required this.attachment,
    required this.onDownload,
  });

  final ChatMessage message;
  final MessageAttachment? attachment;
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
          const SnackBar(content: Text('Не удалось скачать или открыть файл.')),
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
    final attachment = widget.attachment;
    return ListTile(
      onTap: _busy ? null : _open,
      contentPadding: EdgeInsets.zero,
      leading: _busy
          ? const CircularProgressIndicator()
          : const Icon(Icons.insert_drive_file_rounded, color: Colors.white),
      title: Text(attachment?.fileName ?? widget.message.visibleBody),
      subtitle: Text(_fileSize(attachment?.byteSize)),
    );
  }
}

class _VoicePayload extends StatefulWidget {
  const _VoicePayload({required this.attachment});

  final MessageAttachment? attachment;

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
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.filledTonal(
              onPressed: _loading ? null : _toggle,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(_duration(widget.attachment?.durationMs)),
          ],
        );
      },
    );
  }
}

String _fileSize(int? bytes) {
  if (bytes == null) {
    return 'Файл';
  }
  if (bytes < 1024) {
    return '$bytes Б';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} КБ';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
}

String _duration(int? milliseconds) {
  final duration = Duration(milliseconds: milliseconds ?? 0);
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${duration.inMinutes}:$seconds';
}
