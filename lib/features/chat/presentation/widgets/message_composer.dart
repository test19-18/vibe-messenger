import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/chat_message.dart';

class MessageComposer extends StatelessWidget {
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
  final VoidCallback? onVoiceToggle;
  final bool isRecording;

  void _format(String prefix, String suffix) {
    final selection = controller.selection;
    if (!selection.isValid) {
      return;
    }
    final selected = selection.textInside(controller.text);
    final replacement = '$prefix$selected$suffix';
    controller.value = controller.value
        .replaced(selection, replacement)
        .copyWith(
          selection: TextSelection.collapsed(
            offset: selection.start + replacement.length,
          ),
        );
    onChanged(controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final contextMessage = editing ?? replyTo;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (contextMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  border: const Border(
                    left: BorderSide(color: AppColors.electricBlue, width: 3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      editing == null
                          ? Icons.reply_rounded
                          : Icons.edit_rounded,
                      color: AppColors.electricBlue,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            editing == null ? 'Ответ' : 'Редактирование',
                            style: const TextStyle(
                              color: AppColors.electricBlue,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            contextMessage.visibleBody,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onCancelContext,
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Отменить',
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                PopupMenuButton<String>(
                  tooltip: 'Вложения',
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onSelected: (value) {
                    switch (value) {
                      case 'file':
                        onAttach?.call();
                        break;
                      case 'location':
                        onLocation?.call();
                        break;
                      case 'contact':
                        onContact?.call();
                        break;
                      case 'poll':
                        onPoll?.call();
                        break;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'file',
                      child: Text('Фото или документ'),
                    ),
                    PopupMenuItem(value: 'location', child: Text('Геопозиция')),
                    PopupMenuItem(value: 'contact', child: Text('Контакт')),
                    PopupMenuItem(value: 'poll', child: Text('Опрос')),
                  ],
                ),
                Expanded(
                  child: TextField(
                    key: const Key('message_composer_field'),
                    controller: controller,
                    focusNode: focusNode,
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
                    onChanged: onChanged,
                    decoration: const InputDecoration(
                      hintText: 'Сообщение…',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: 13,
                      ),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Форматирование',
                  icon: const Icon(Icons.text_format_rounded),
                  onSelected: (value) {
                    switch (value) {
                      case 'bold':
                        _format('**', '**');
                        break;
                      case 'italic':
                        _format('_', '_');
                        break;
                      case 'code':
                        _format('`', '`');
                        break;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'bold',
                      child: Text('Жирный **текст**'),
                    ),
                    PopupMenuItem(
                      value: 'italic',
                      child: Text('Курсив _текст_'),
                    ),
                    PopupMenuItem(value: 'code', child: Text('Код `текст`')),
                  ],
                ),
                IconButton(
                  onPressed: isSending ? null : onVoiceToggle,
                  color: isRecording ? AppColors.danger : null,
                  icon: Icon(
                    isRecording
                        ? Icons.stop_circle_rounded
                        : Icons.mic_none_rounded,
                  ),
                  tooltip: isRecording
                      ? 'Остановить запись'
                      : 'Голосовое сообщение',
                ),
                const SizedBox(width: AppSpacing.xs),
                SizedBox(
                  width: 50,
                  height: 50,
                  child: FilledButton(
                    onPressed: isSending ? null : onSend,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                    child: isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            editing == null
                                ? Icons.arrow_upward_rounded
                                : Icons.check_rounded,
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
