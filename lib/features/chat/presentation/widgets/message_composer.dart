import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/vibe_tokens.dart';
import '../../domain/chat_message.dart';

/// Bottom input bar: attachment menu, rounded text field and a send button that
/// swaps to a microphone while the field is empty — the arrangement people
/// already have muscle memory for.
class MessageComposer extends StatefulWidget {
  const MessageComposer({
    required this.controller,
    required this.focusNode,
    required this.isSending,
    required this.onSend,
    required this.onChanged,
    super.key,
    this.replyTo,
    this.editing,
    this.onCancelContext,
    this.onAttach,
    this.onLocation,
    this.onContact,
    this.onPoll,
    this.onSchedule,
    this.onVoiceToggle,
    this.isRecording = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final VoidCallback onSend;
  final ValueChanged<String> onChanged;
  final ChatMessage? replyTo;
  final ChatMessage? editing;
  final VoidCallback? onCancelContext;
  final VoidCallback? onAttach;
  final VoidCallback? onLocation;
  final VoidCallback? onContact;
  final VoidCallback? onPoll;
  final VoidCallback? onSchedule;
  final VoidCallback? onVoiceToggle;
  final bool isRecording;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_syncHasText);
  }

  @override
  void didUpdateWidget(MessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncHasText);
      widget.controller.addListener(_syncHasText);
      _syncHasText();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncHasText);
    super.dispose();
  }

  /// Drives the send/microphone swap without rebuilding the whole chat.
  void _syncHasText() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void _format(String prefix, String suffix) {
    final selection = widget.controller.selection;
    if (!selection.isValid) {
      return;
    }
    final selected = selection.textInside(widget.controller.text);
    final replacement = '$prefix$selected$suffix';
    widget.controller.value = widget.controller.value
        .replaced(selection, replacement)
        .copyWith(
          selection: TextSelection.collapsed(
            offset: selection.start + replacement.length,
          ),
        );
    widget.onChanged(widget.controller.text);
  }

  void _handleAttachmentAction(String value) {
    switch (value) {
      case 'file':
        widget.onAttach?.call();
      case 'location':
        widget.onLocation?.call();
      case 'contact':
        widget.onContact?.call();
      case 'poll':
        widget.onPoll?.call();
      case 'schedule':
        widget.onSchedule?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final contextMessage = widget.editing ?? widget.replyTo;
    // While recording, the microphone stays the primary action.
    final showSend = _hasText && !widget.isRecording;

    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.composer,
          border: Border(top: BorderSide(color: tokens.divider, width: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (contextMessage != null)
                _ComposerContext(
                  message: contextMessage,
                  isEditing: widget.editing != null,
                  onCancel: widget.onCancelContext,
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  PopupMenuButton<String>(
                    tooltip: context.tr(ru: 'Вложения', en: 'Attachments'),
                    icon: const Icon(Icons.attach_file_rounded),
                    onSelected: _handleAttachmentAction,
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'file',
                        child: _MenuRow(
                          icon: Icons.image_outlined,
                          label: context.tr(
                            ru: 'Фото или документ',
                            en: 'Photo or file',
                          ),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'location',
                        child: _MenuRow(
                          icon: Icons.location_on_outlined,
                          label: context.tr(ru: 'Геопозиция', en: 'Location'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'contact',
                        child: _MenuRow(
                          icon: Icons.person_outline_rounded,
                          label: context.tr(ru: 'Контакт', en: 'Contact'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'poll',
                        child: _MenuRow(
                          icon: Icons.poll_outlined,
                          label: context.tr(ru: 'Опрос', en: 'Poll'),
                        ),
                      ),
                      if (widget.onSchedule != null)
                        PopupMenuItem(
                          value: 'schedule',
                          child: _MenuRow(
                            icon: Icons.schedule_send_outlined,
                            label: context.tr(
                              ru: 'Отложить сообщение',
                              en: 'Schedule message',
                            ),
                          ),
                        ),
                    ],
                  ),
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 42),
                      decoration: BoxDecoration(
                        color: tokens.surfaceElevated,
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                        border: Border.all(color: tokens.separator, width: 0.5),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('message_composer_field'),
                              controller: widget.controller,
                              focusNode: widget.focusNode,
                              minLines: 1,
                              maxLines: 5,
                              maxLength: 4000,
                              buildCounter:
                                  (
                                    context, {
                                    required currentLength,
                                    required isFocused,
                                    maxLength,
                                  }) => null,
                              textCapitalization: TextCapitalization.sentences,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              onChanged: widget.onChanged,
                              style: Theme.of(context).textTheme.bodyLarge,
                              decoration: InputDecoration(
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                                contentPadding: const EdgeInsets.fromLTRB(
                                  14,
                                  11,
                                  4,
                                  11,
                                ),
                                hintText: widget.isRecording
                                    ? context.tr(
                                        ru: 'Идёт запись…',
                                        en: 'Recording…',
                                      )
                                    : context.tr(
                                        ru: 'Сообщение',
                                        en: 'Message',
                                      ),
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: context.tr(
                              ru: 'Форматирование',
                              en: 'Formatting',
                            ),
                            icon: Icon(
                              Icons.text_format_rounded,
                              color: tokens.textSecondary,
                            ),
                            onSelected: (value) {
                              switch (value) {
                                case 'bold':
                                  _format('**', '**');
                                case 'italic':
                                  _format('_', '_');
                                case 'code':
                                  _format('`', '`');
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'bold',
                                child: Text(
                                  context.tr(
                                    ru: 'Жирный **текст**',
                                    en: 'Bold **text**',
                                  ),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'italic',
                                child: Text(
                                  context.tr(
                                    ru: 'Курсив _текст_',
                                    en: 'Italic _text_',
                                  ),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'code',
                                child: Text(
                                  context.tr(
                                    ru: 'Код `текст`',
                                    en: 'Code `text`',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _PrimaryAction(
                    showSend: showSend,
                    isSending: widget.isSending,
                    isRecording: widget.isRecording,
                    isEditing: widget.editing != null,
                    onSend: widget.onSend,
                    onVoiceToggle: widget.onVoiceToggle,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round send button, or the microphone when there is nothing to send.
class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.showSend,
    required this.isSending,
    required this.isRecording,
    required this.isEditing,
    required this.onSend,
    required this.onVoiceToggle,
  });

  final bool showSend;
  final bool isSending;
  final bool isRecording;
  final bool isEditing;
  final VoidCallback onSend;
  final VoidCallback? onVoiceToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final background = isRecording
        ? tokens.danger
        : showSend
        ? tokens.accent
        : Colors.transparent;
    final foreground = isRecording || showSend
        ? Colors.white
        : tokens.textSecondary;

    final label = isRecording
        ? context.tr(ru: 'Остановить запись', en: 'Stop recording')
        : showSend
        ? (isEditing
              ? context.tr(ru: 'Сохранить', en: 'Save')
              : context.tr(ru: 'Отправить', en: 'Send'))
        : context.tr(ru: 'Голосовое сообщение', en: 'Voice message');

    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: isSending ? null : (showSend ? onSend : onVoiceToggle),
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            width: AppSizes.minTapTarget,
            height: AppSizes.minTapTarget,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
            ),
            child: isSending
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    isRecording
                        ? Icons.stop_rounded
                        : showSend
                        ? (isEditing ? Icons.check_rounded : Icons.send_rounded)
                        : Icons.mic_none_rounded,
                    color: foreground,
                    size: 22,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Reply / edit banner above the input row.
class _ComposerContext extends StatelessWidget {
  const _ComposerContext({
    required this.message,
    required this.isEditing,
    required this.onCancel,
  });

  final ChatMessage message;
  final bool isEditing;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 4, 6),
      child: Row(
        children: [
          Icon(
            isEditing ? Icons.edit_rounded : Icons.reply_rounded,
            color: tokens.accent,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.xs),
          Container(width: 2, height: 30, color: tokens.accent),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isEditing
                      ? context.tr(ru: 'Редактирование', en: 'Editing')
                      : context.tr(ru: 'Ответ', en: 'Reply'),
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  message.visibleBody,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded),
            iconSize: 20,
            color: tokens.textSecondary,
            tooltip: context.tr(ru: 'Отменить', en: 'Cancel'),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: context.tokens.textSecondary),
        const SizedBox(width: AppSpacing.sm),
        Flexible(child: Text(label)),
      ],
    );
  }
}
