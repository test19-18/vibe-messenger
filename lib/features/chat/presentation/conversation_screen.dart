import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_tokens.dart';
import '../../../core/widgets/async_state_view.dart';
import '../../auth/providers/auth_providers.dart';
import '../domain/chat_message.dart';
import '../providers/message_providers.dart';
import 'widgets/message_bubble.dart';
import 'widgets/message_composer.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({
    required this.conversationId,
    super.key,
    this.title,
  });

  final String conversationId;
  final String? title;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _composerController = TextEditingController();
  final _composerFocusNode = FocusNode();
  ChatMessage? _replyTo;
  ChatMessage? _editing;
  Timer? _typingTimer;

  @override
  void dispose() {
    _typingTimer?.cancel();
    _composerController.dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  Future<void> _markRead() async {
    final userId = ref.read(currentUserProvider)?.id;
    if (userId == null) {
      return;
    }
    try {
      await ref
          .read(messageServiceProvider)
          .markRead(conversationId: widget.conversationId, userId: userId);
    } catch (_) {
      // Read receipts are best effort and must not block the conversation UI.
    }
  }

  void _handleTyping(String text) {
    final typing = ref.read(typingServiceProvider(widget.conversationId));
    _typingTimer?.cancel();
    unawaited(typing.setTyping(text.trim().isNotEmpty));
    if (text.trim().isNotEmpty) {
      _typingTimer = Timer(const Duration(milliseconds: 1400), () {
        unawaited(typing.setTyping(false));
      });
    }
  }

  Future<void> _submit() async {
    final controller = ref.read(
      messageMutationProvider(widget.conversationId).notifier,
    );
    final text = _composerController.text;
    final success = _editing == null
        ? await controller.send(text, replyToId: _replyTo?.id)
        : await controller.edit(_editing!, text);
    if (!mounted || !success) {
      return;
    }
    _composerController.clear();
    _typingTimer?.cancel();
    unawaited(
      ref.read(typingServiceProvider(widget.conversationId)).setTyping(false),
    );
    setState(() {
      _replyTo = null;
      _editing = null;
    });
  }

  void _startReply(ChatMessage message) {
    setState(() {
      _replyTo = message;
      _editing = null;
    });
    _composerFocusNode.requestFocus();
  }

  void _startEdit(ChatMessage message) {
    setState(() {
      _editing = message;
      _replyTo = null;
      _composerController.text = message.body;
      _composerController.selection = TextSelection.collapsed(
        offset: _composerController.text.length,
      );
    });
    _composerFocusNode.requestFocus();
  }

  void _clearComposerContext() {
    setState(() {
      _replyTo = null;
      _editing = null;
      _composerController.clear();
    });
  }

  Future<void> _showMessageActions(
    ChatMessage message, {
    required bool isMine,
  }) async {
    if (message.isDeleted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.tokens.surfaceElevated,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Ответить'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _startReply(message);
                },
              ),
              if (isMine)
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: const Text('Изменить'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _startEdit(message);
                  },
                ),
              if (isMine)
                ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: context.tokens.danger,
                  ),
                  title: Text(
                    'Удалить',
                    style: TextStyle(color: context.tokens.danger),
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _confirmDelete(message);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.tokens.surfaceElevated,
        title: const Text('Удалить сообщение?'),
        content: const Text('Вместо текста останется отметка об удалении.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Удалить',
              style: TextStyle(color: context.tokens.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await ref
        .read(messageMutationProvider(widget.conversationId).notifier)
        .delete(message);
  }

  @override
  Widget build(BuildContext context) {
    final messageState = ref.watch(messagesProvider(widget.conversationId));
    final mutationState = ref.watch(
      messageMutationProvider(widget.conversationId),
    );
    final typingUsers =
        ref.watch(typingUsersProvider(widget.conversationId)).valueOrNull ??
        const <String>{};
    final currentUserId = ref.watch(currentUserProvider)?.id;

    ref.listen<AsyncValue<List<ChatMessage>>>(
      messagesProvider(widget.conversationId),
      (previous, next) {
        if (next.hasValue && next.value!.isNotEmpty) {
          unawaited(_markRead());
        }
      },
    );
    ref.listen<AsyncValue<void>>(
      messageMutationProvider(widget.conversationId),
      (previous, next) {
        if (next.hasError && previous?.error != next.error) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(errorMessage(next.error!))));
        }
      },
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title?.trim().isNotEmpty == true
                  ? widget.title!
                  : 'Беседа',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              typingUsers.isNotEmpty ? 'печатает…' : 'в Вайбе',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: typingUsers.isNotEmpty
                    ? context.tokens.accent
                    : context.tokens.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'Меню беседы',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: AsyncStateView<List<ChatMessage>>(
              value: messageState,
              isEmpty: (messages) => messages.isEmpty,
              emptyTitle: 'Начните разговор',
              emptyMessage: 'Первое сообщение задаёт настроение.',
              onRetry: () =>
                  ref.invalidate(messagesProvider(widget.conversationId)),
              dataBuilder: (context, messages) {
                final byId = {
                  for (final message in messages) message.id: message,
                };
                return ListView.builder(
                  reverse: true,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[messages.length - 1 - index];
                    final isMine = message.senderId == currentUserId;
                    return MessageBubble(
                      message: message,
                      replyMessage: byId[message.replyToId],
                      isMine: isMine,
                      onLongPress: () =>
                          _showMessageActions(message, isMine: isMine),
                    );
                  },
                );
              },
            ),
          ),
          MessageComposer(
            controller: _composerController,
            focusNode: _composerFocusNode,
            isSending: mutationState.isLoading,
            replyTo: _replyTo,
            editing: _editing,
            onCancelContext: _clearComposerContext,
            onChanged: _handleTyping,
            onSend: _submit,
          ),
        ],
      ),
    );
  }
}
