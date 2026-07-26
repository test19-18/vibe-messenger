import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/error_message.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_tokens.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/async_state_view.dart';
import '../../../core/widgets/chat_wallpaper.dart';
import '../../../core/widgets/service_pill.dart';
import '../../auth/providers/auth_providers.dart';
import '../../calls/domain/call_models.dart';
import '../../calls/providers/call_providers.dart';
import '../../chats/domain/conversation_summary.dart';
import '../../chats/domain/conversation_user_settings.dart';
import '../../chats/providers/conversation_providers.dart';
import '../../contacts/providers/contact_providers.dart';
import '../../security/providers/screen_protection_providers.dart';
import '../../security/services/screen_protection_service.dart';
import '../../settings/domain/app_preferences.dart';
import '../../settings/providers/settings_providers.dart';
import '../domain/chat_message.dart';
import '../domain/message_details.dart';
import '../domain/scheduled_message.dart';
import '../providers/message_providers.dart';
import '../services/voice_recording_service.dart';
import 'widgets/enhanced_message_bubble.dart';
import 'widgets/message_composer.dart';

class EnhancedConversationScreen extends ConsumerStatefulWidget {
  const EnhancedConversationScreen({
    required this.conversationId,
    super.key,
    this.title,
    this.isGroup = false,
  });

  final String conversationId;
  final String? title;
  final bool isGroup;

  @override
  ConsumerState<EnhancedConversationScreen> createState() =>
      _EnhancedConversationScreenState();
}

class _EnhancedConversationScreenState
    extends ConsumerState<EnhancedConversationScreen>
    with WidgetsBindingObserver {
  final _composerController = TextEditingController();
  final _composerFocusNode = FocusNode();
  final _selectedIds = <String>{};
  final _voiceRecorder = VoiceRecordingService();
  final _screenProtectionOwner = Object();
  ChatMessage? _replyTo;
  ChatMessage? _editing;
  Timer? _typingTimer;
  Timer? _draftTimer;
  bool _recording = false;
  bool _draftLoaded = false;
  bool _protectedContent = false;
  bool _privacyCover = false;
  ScreenProtectionMode _screenProtectionMode = ScreenProtectionMode.disabled;

  String? get _currentUserId => ref.read(currentUserProvider)?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_protectedContent || !mounted) {
      return;
    }
    final covered = state != AppLifecycleState.resumed;
    if (_privacyCover != covered) {
      setState(() => _privacyCover = covered);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _typingTimer?.cancel();
    _draftTimer?.cancel();
    unawaited(
      ref
          .read(screenProtectionServiceProvider)
          .setProtectedFor(_screenProtectionOwner, enabled: false),
    );
    unawaited(_voiceRecorder.dispose());
    _composerController.dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  Future<void> _applyProtectedContent(bool enabled) async {
    if (mounted && _protectedContent != enabled) {
      setState(() {
        _protectedContent = enabled;
        if (!enabled) {
          _privacyCover = false;
        }
      });
    }
    final mode = await ref
        .read(screenProtectionServiceProvider)
        .setProtectedFor(_screenProtectionOwner, enabled: enabled);
    if (mounted && _protectedContent == enabled) {
      setState(() => _screenProtectionMode = mode);
    }
  }

  Future<void> _markRead(List<ChatMessage> messages) async {
    final userId = _currentUserId;
    if (userId == null || messages.isEmpty) {
      return;
    }
    try {
      await ref
          .read(messageServiceProvider)
          .markRead(
            conversationId: widget.conversationId,
            userId: userId,
            lastReadMessageId: messages.last.id,
          );
    } catch (_) {
      // Read receipts are best effort and never block chat rendering.
    }
  }

  Future<void> _startCall(
    BuildContext context,
    WidgetRef ref,
    CallType type,
  ) async {
    if (widget.isGroup) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              ru: 'Звонки в группе пока не поддерживаются.',
              en: 'Group calls are not supported yet.',
            ),
          ),
        ),
      );
      return;
    }
    final userId = _currentUserId;
    if (userId == null) {
      return;
    }
    final conversations = ref.read(conversationsProvider).valueOrNull;
    final summary = conversations
        ?.where((item) => item.id == widget.conversationId)
        .firstOrNull;
    final calleeId = summary?.peer?.id;
    if (calleeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              ru: 'Не удалось определить собеседника.',
              en: 'Could not identify the call recipient.',
            ),
          ),
        ),
      );
      return;
    }
    final success = await ref
        .read(callInitiationProvider.notifier)
        .startCall(
          conversationId: widget.conversationId,
          calleeId: calleeId,
          type: type,
        );
    if (success && context.mounted) {
      context.push('/call');
    }
  }

  void _loadDraft(List<ConversationSummary>? conversations) {
    if (_draftLoaded || conversations == null) {
      return;
    }
    _draftLoaded = true;
    final summary = conversations
        .where((item) => item.id == widget.conversationId)
        .firstOrNull;
    final draft = summary?.draft;
    if (draft?.isNotEmpty == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _composerController.text.isNotEmpty) {
          return;
        }
        _composerController.text = draft!;
        _composerController.selection = TextSelection.collapsed(
          offset: draft.length,
        );
      });
    }
  }

  void _handleTyping(String text) {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_saveDraft(text));
    });
    final preferences =
        ref.read(appPreferencesProvider).valueOrNull ?? const AppPreferences();
    if (!preferences.showTypingStatus) {
      return;
    }
    final typing = ref.read(typingServiceProvider(widget.conversationId));
    _typingTimer?.cancel();
    unawaited(typing.setTyping(text.trim().isNotEmpty));
    if (text.trim().isNotEmpty) {
      _typingTimer = Timer(const Duration(milliseconds: 1400), () {
        unawaited(typing.setTyping(false));
      });
    }
  }

  Future<void> _saveDraft(String value) async {
    final userId = _currentUserId;
    if (userId == null) {
      return;
    }
    try {
      await ref
          .read(conversationRepositoryProvider)
          .updateConversationSettings(
            conversationId: widget.conversationId,
            userId: userId,
            draft: value,
          );
      ref.invalidate(conversationsProvider);
    } catch (_) {
      // Draft sync retries on the next edit and must not interrupt typing.
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
    _draftTimer?.cancel();
    unawaited(_saveDraft(''));
    unawaited(
      ref.read(typingServiceProvider(widget.conversationId)).setTyping(false),
    );
    setState(() {
      _replyTo = null;
      _editing = null;
    });
  }

  Future<void> _scheduleCurrentMessage() async {
    if (_editing != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              ru: 'Сначала завершите редактирование сообщения.',
              en: 'Finish editing the message first.',
            ),
          ),
        ),
      );
      return;
    }
    final body = _composerController.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              ru: 'Введите текст для отложенной отправки.',
              en: 'Enter text to schedule.',
            ),
          ),
        ),
      );
      return;
    }
    final now = DateTime.now();
    final initial = now.add(const Duration(minutes: 5));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) {
      return;
    }
    final scheduledFor = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    var silent = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            context.tr(ru: 'Отложить сообщение', en: 'Schedule message'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(DateFormat('dd.MM.yyyy HH:mm').format(scheduledFor)),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: silent,
                onChanged: (value) => setDialogState(() => silent = value),
                title: Text(
                  context.tr(
                    ru: 'Без уведомления (silent)',
                    en: 'Send silently',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.tr(ru: 'Отмена', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.tr(ru: 'Запланировать', en: 'Schedule')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final success = await ref
        .read(messageMutationProvider(widget.conversationId).notifier)
        .schedule(
          body: body,
          scheduledFor: scheduledFor,
          silent: silent,
          replyToId: _replyTo?.id,
        );
    if (!mounted || !success) {
      return;
    }
    _composerController.clear();
    _draftTimer?.cancel();
    unawaited(_saveDraft(''));
    setState(() => _replyTo = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(ru: 'Сообщение запланировано.', en: 'Message scheduled.'),
        ),
      ),
    );
  }

  Future<void> _showScheduledMessages() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Consumer(
        builder: (context, sheetRef, _) {
          final state = sheetRef.watch(
            scheduledMessagesProvider(widget.conversationId),
          );
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.65,
              child: state.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(errorMessage(error)),
                  ),
                ),
                data: (messages) {
                  if (messages.isEmpty) {
                    return Center(
                      child: Text(
                        context.tr(
                          ru: 'Нет отложенных сообщений.',
                          en: 'No scheduled messages.',
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      0,
                      AppSpacing.md,
                      AppSpacing.lg,
                    ),
                    itemCount: messages.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return ListTile(
                        leading: Icon(
                          message.silent
                              ? Icons.notifications_off_outlined
                              : Icons.schedule_send_rounded,
                        ),
                        title: Text(
                          message.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${DateFormat('dd.MM.yyyy HH:mm').format(message.scheduledFor)} · '
                          '${_scheduledStatusLabel(context, message.status)}',
                        ),
                        trailing: message.canCancel
                            ? IconButton(
                                onPressed: () => sheetRef
                                    .read(
                                      messageMutationProvider(
                                        widget.conversationId,
                                      ).notifier,
                                    )
                                    .cancelScheduled(message),
                                icon: Icon(
                                  Icons.cancel_outlined,
                                  color: context.tokens.danger,
                                ),
                                tooltip: context.tr(
                                  ru: 'Отменить',
                                  en: 'Cancel',
                                ),
                              )
                            : null,
                      );
                    },
                  );
                },
              ),
            ),
          );
        },
      ),
    );
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
    unawaited(_saveDraft(''));
  }

  void _toggleSelection(ChatMessage message) {
    setState(() {
      if (!_selectedIds.add(message.id)) {
        _selectedIds.remove(message.id);
      }
    });
  }

  Future<void> _copyMessages(List<ChatMessage> messages) async {
    final selected = messages
        .where((message) => _selectedIds.contains(message.id))
        .map((message) => message.visibleBody)
        .where((text) => text.isNotEmpty)
        .join('\n');
    if (selected.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: selected));
    }
    if (mounted) {
      setState(_selectedIds.clear);
    }
  }

  Future<void> _forwardMessages(List<ChatMessage> messages) async {
    final selected = messages
        .where((message) => _selectedIds.contains(message.id))
        .toList();
    final conversations = await ref.read(conversationsProvider.future);
    if (!mounted) {
      return;
    }
    final target = await showModalBottomSheet<ConversationSummary>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final conversation in conversations)
              ListTile(
                leading: Icon(
                  conversation.isGroup
                      ? Icons.group_rounded
                      : Icons.person_rounded,
                ),
                title: Text(conversation.visibleTitle),
                onTap: () => Navigator.pop(sheetContext, conversation),
              ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) {
      return;
    }
    final success = await ref
        .read(messageMutationProvider(widget.conversationId).notifier)
        .forward(selected, target.id);
    if (success && mounted) {
      setState(_selectedIds.clear);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(ru: 'Сообщения пересланы.', en: 'Messages forwarded.'),
          ),
        ),
      );
    }
  }

  Future<void> _showMessageActions(
    ChatMessage message, {
    required bool isMine,
    required List<MessageReaction> reactions,
    required bool pinned,
  }) async {
    if (message.isDeleted) {
      return;
    }
    final selectedEmoji = reactions
        .where(
          (reaction) =>
              reaction.messageId == message.id &&
              reaction.userId == _currentUserId,
        )
        .map((reaction) => reaction.emoji)
        .toSet();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Wrap(
                  spacing: AppSpacing.xs,
                  children: ['👍', '❤️', '😂', '😮', '😢', '🔥']
                      .map(
                        (emoji) => ActionChip(
                          label: Text(emoji),
                          backgroundColor: selectedEmoji.contains(emoji)
                              ? context.tokens.accentSoft
                              : null,
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            ref
                                .read(
                                  messageMutationProvider(
                                    widget.conversationId,
                                  ).notifier,
                                )
                                .toggleReaction(
                                  message: message,
                                  emoji: emoji,
                                  selected: selectedEmoji.contains(emoji),
                                );
                          },
                        ),
                      )
                      .toList(),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: Text(context.tr(ru: 'Ответить', en: 'Reply')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _startReply(message);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text(context.tr(ru: 'Копировать', en: 'Copy')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Clipboard.setData(ClipboardData(text: message.visibleBody));
                },
              ),
              ListTile(
                leading: const Icon(Icons.checklist_rounded),
                title: Text(context.tr(ru: 'Выбрать', en: 'Select')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _toggleSelection(message);
                },
              ),
              ListTile(
                leading: Icon(
                  pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                ),
                title: Text(
                  pinned
                      ? context.tr(ru: 'Открепить', en: 'Unpin')
                      : context.tr(ru: 'Закрепить', en: 'Pin'),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  ref
                      .read(
                        messageMutationProvider(widget.conversationId).notifier,
                      )
                      .setPinned(message, pinned: !pinned);
                },
              ),
              if (isMine && message.kind == MessageKind.text)
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: Text(context.tr(ru: 'Изменить', en: 'Edit')),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _startEdit(message);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: Text(
                  context.tr(ru: 'Удалить только у меня', en: 'Delete for me'),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDeleteForSelf(message);
                },
              ),
              if (isMine)
                ListTile(
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: context.tokens.danger,
                  ),
                  title: Text(
                    context.tr(ru: 'Удалить у всех', en: 'Delete for everyone'),
                    style: TextStyle(color: context.tokens.danger),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _confirmDelete(message);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(context.tr(ru: 'Пожаловаться', en: 'Report')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _reportMessage(message);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteForSelf(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          context.tr(ru: 'Удалить только у вас?', en: 'Delete only for you?'),
        ),
        content: Text(
          context.tr(
            ru: 'Сообщение останется у других участников и будет скрыто из вашей ленты.',
            en: 'The message remains visible to other members and is hidden from your timeline.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr(ru: 'Отмена', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr(ru: 'Удалить', en: 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(messageMutationProvider(widget.conversationId).notifier)
          .deleteForSelf(message);
    }
  }

  Future<void> _confirmDelete(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          context.tr(ru: 'Удалить у всех?', en: 'Delete for everyone?'),
        ),
        content: Text(
          context.tr(
            ru: 'Сообщение исчезнет у всех участников. Для личного скрытия используйте «Удалить только у меня».',
            en: 'The message will disappear for everyone. Use “Delete for me” to hide it only for yourself.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr(ru: 'Отмена', en: 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              context.tr(ru: 'Удалить', en: 'Delete'),
              style: TextStyle(color: context.tokens.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(messageMutationProvider(widget.conversationId).notifier)
          .delete(message);
    }
  }

  Future<void> _reportMessage(ChatMessage message) async {
    final reason = TextEditingController();
    final details = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          context.tr(ru: 'Жалоба на сообщение', en: 'Report message'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: reason,
              maxLength: 100,
              decoration: InputDecoration(
                labelText: context.tr(ru: 'Причина', en: 'Reason'),
              ),
            ),
            TextField(
              controller: details,
              maxLines: 3,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: context.tr(ru: 'Подробности', en: 'Details'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr(ru: 'Отмена', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr(ru: 'Отправить', en: 'Submit')),
          ),
        ],
      ),
    );
    if (submit == true && mounted) {
      final userId = _currentUserId;
      if (userId != null) {
        await ref
            .read(contactRepositoryProvider)
            .reportMessage(
              reporterId: userId,
              messageId: message.id,
              reason: reason.text,
              details: details.text,
            );
      }
    }
    reason.dispose();
    details.dispose();
  }

  Future<void> _searchMessages() async {
    final controller = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr(ru: 'Поиск сообщений', en: 'Search messages')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: context.tr(ru: 'Текст сообщения', en: 'Message text'),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(context.tr(ru: 'Найти', en: 'Search')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (query == null || query.trim().isEmpty || !mounted) {
      return;
    }
    try {
      final results = await ref
          .read(messageRepositoryProvider)
          .searchMessages(conversationId: widget.conversationId, query: query);
      if (!mounted) {
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: results.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Text(
                    context.tr(ru: 'Ничего не найдено.', en: 'No results.'),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final message = results[index];
                    return ListTile(
                      leading: const Icon(Icons.search_rounded),
                      title: Text(
                        message.visibleBody,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(message.createdAt.toLocal().toString()),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        setState(() => _selectedIds.add(message.id));
                      },
                    );
                  },
                ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(error))));
      }
    }
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'gif',
        'heic',
        'mp4',
        'mov',
        'webm',
        'mp3',
        'm4a',
        'aac',
        'ogg',
        'wav',
        'pdf',
        'zip',
        '7z',
        'txt',
        'csv',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'ppt',
        'pptx',
      ],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось прочитать выбранный файл.')),
        );
      }
      return;
    }
    final mime = _mimeFor(file.extension);
    final kind = mime.startsWith('image/')
        ? MessageKind.image
        : mime.startsWith('video/')
        ? MessageKind.video
        : mime.startsWith('audio/')
        ? MessageKind.audio
        : MessageKind.file;
    final success = await ref
        .read(messageMutationProvider(widget.conversationId).notifier)
        .uploadAttachment(
          bytes: bytes,
          fileName: file.name,
          mimeType: mime,
          kind: kind,
          body: _composerController.text,
          replyToId: _replyTo?.id,
        );
    if (success) {
      _composerController.clear();
      ref.invalidate(messageAttachmentsProvider(widget.conversationId));
    }
  }

  Future<void> _sendLocation() async {
    final latitude = TextEditingController();
    final longitude = TextEditingController();
    final label = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr(ru: 'Геопозиция', en: 'Location')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: latitude,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Latitude'),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller: longitude,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Longitude'),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller: label,
              decoration: InputDecoration(
                labelText: context.tr(ru: 'Подпись', en: 'Label'),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr(ru: 'Отправить', en: 'Send')),
          ),
        ],
      ),
    );
    if (submit == true) {
      final lat = double.tryParse(latitude.text.replaceAll(',', '.'));
      final lng = double.tryParse(longitude.text.replaceAll(',', '.'));
      if (lat != null && lng != null) {
        await ref
            .read(messageMutationProvider(widget.conversationId).notifier)
            .sendLocation(latitude: lat, longitude: lng, label: label.text);
      }
    }
    latitude.dispose();
    longitude.dispose();
    label.dispose();
  }

  Future<void> _sendContact() async {
    final name = TextEditingController();
    final value = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr(ru: 'Отправить контакт', en: 'Send contact')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(
                labelText: context.tr(ru: 'Имя', en: 'Name'),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller: value,
              decoration: InputDecoration(
                labelText: context.tr(
                  ru: 'Телефон или email',
                  en: 'Phone or email',
                ),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr(ru: 'Отправить', en: 'Send')),
          ),
        ],
      ),
    );
    if (submit == true) {
      await ref
          .read(messageMutationProvider(widget.conversationId).notifier)
          .sendContact(name: name.text, value: value.text);
    }
    name.dispose();
    value.dispose();
  }

  Future<void> _createPoll() async {
    final question = TextEditingController();
    final options = [TextEditingController(), TextEditingController()];
    var allowMultiple = false;
    var anonymous = false;
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.tr(ru: 'Новый опрос', en: 'New poll')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: question,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    labelText: context.tr(ru: 'Вопрос', en: 'Question'),
                  ),
                ),
                for (var index = 0; index < options.length; index++) ...[
                  TextField(
                    controller: options[index],
                    maxLength: 500,
                    decoration: InputDecoration(
                      labelText:
                          '${context.tr(ru: 'Вариант', en: 'Option')} ${index + 1}',
                    ),
                  ),
                ],
                if (options.length < 20)
                  TextButton.icon(
                    onPressed: () => setDialogState(
                      () => options.add(TextEditingController()),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(
                      context.tr(ru: 'Добавить вариант', en: 'Add option'),
                    ),
                  ),
                SwitchListTile.adaptive(
                  value: allowMultiple,
                  onChanged: (value) =>
                      setDialogState(() => allowMultiple = value),
                  title: Text(
                    context.tr(ru: 'Несколько ответов', en: 'Multiple answers'),
                  ),
                ),
                SwitchListTile.adaptive(
                  value: anonymous,
                  onChanged: (value) => setDialogState(() => anonymous = value),
                  title: Text(
                    context.tr(ru: 'Анонимный опрос', en: 'Anonymous poll'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.tr(ru: 'Создать', en: 'Create')),
            ),
          ],
        ),
      ),
    );
    if (submit == true && question.text.trim().isNotEmpty) {
      final values = options
          .map((controller) => controller.text.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      if (values.length >= 2) {
        await ref
            .read(pollMutationProvider(widget.conversationId).notifier)
            .create(
              question: question.text,
              options: values,
              allowMultiple: allowMultiple,
              maxSelections: allowMultiple ? values.length : 1,
              isAnonymous: anonymous,
            );
      }
    }
    question.dispose();
    for (final controller in options) {
      controller.dispose();
    }
  }

  Future<void> _toggleRecording() async {
    if (!_recording) {
      try {
        await _voiceRecorder.start();
        if (mounted) {
          setState(() => _recording = true);
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(errorMessage(error))));
        }
      }
      return;
    }
    final recording = await _voiceRecorder.stop();
    if (mounted) {
      setState(() => _recording = false);
    }
    if (recording == null) {
      return;
    }
    final success = await ref
        .read(messageMutationProvider(widget.conversationId).notifier)
        .uploadAttachment(
          bytes: recording.bytes,
          fileName: recording.fileName,
          mimeType: 'audio/mp4',
          kind: MessageKind.voice,
          durationMs: recording.duration.inMilliseconds,
          replyToId: _replyTo?.id,
        );
    if (success) {
      ref.invalidate(messageAttachmentsProvider(widget.conversationId));
    }
  }

  Future<void> _showChatSettings() async {
    ConversationUserSettings settings;
    try {
      settings = await ref.read(
        conversationUserSettingsProvider(widget.conversationId).future,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(error))));
      }
      return;
    }
    if (!mounted) {
      return;
    }
    int? autoDeleteSeconds = settings.autoDeleteSeconds;
    var protectedContent = settings.protectedContent;
    final values = <int?>[null, 3600, 86400, 604800, 2592000];
    if (!values.contains(autoDeleteSeconds)) {
      values.add(autoDeleteSeconds);
    }
    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.tr(
                    ru: 'Настройки этой беседы',
                    en: 'Conversation settings',
                  ),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<int?>(
                  initialValue: autoDeleteSeconds,
                  decoration: InputDecoration(
                    labelText: context.tr(
                      ru: 'Автоудаление моих новых сообщений',
                      en: 'Auto-delete my new messages',
                    ),
                  ),
                  items: [
                    for (final value in values)
                      DropdownMenuItem<int?>(
                        value: value,
                        child: Text(_autoDeleteLabel(context, value)),
                      ),
                  ],
                  onChanged: (value) =>
                      setSheetState(() => autoDeleteSeconds = value),
                ),
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: protectedContent,
                  onChanged: (value) =>
                      setSheetState(() => protectedContent = value),
                  title: Text(
                    context.tr(
                      ru: 'Защищённое содержимое',
                      en: 'Protected content',
                    ),
                  ),
                  subtitle: Text(
                    context.tr(
                      ru: 'Запрашивает FLAG_SECURE через platform channel; без Android wiring скрывает чат только при уходе приложения в фон.',
                      en: 'Requests FLAG_SECURE through a platform channel; without Android wiring it only covers the chat while the app is backgrounded.',
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: Text(context.tr(ru: 'Сохранить', en: 'Save')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (save != true || !mounted) {
      return;
    }
    final success = await ref
        .read(conversationSettingsMutationProvider.notifier)
        .updateExtensions(
          conversationId: widget.conversationId,
          autoDeleteSeconds: autoDeleteSeconds,
          clearAutoDelete: autoDeleteSeconds == null,
          protectedContent: protectedContent,
        );
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(ru: 'Настройки сохранены.', en: 'Settings saved.'),
          ),
        ),
      );
    }
  }

  Future<void> _showConversationMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            if (widget.isGroup)
              ListTile(
                leading: const Icon(Icons.groups_rounded),
                title: Text(
                  context.tr(ru: 'Управление группой', en: 'Manage group'),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push('/group/${widget.conversationId}');
                },
              ),
            ListTile(
              leading: const Icon(Icons.search_rounded),
              title: Text(context.tr(ru: 'Поиск', en: 'Search')),
              onTap: () {
                Navigator.pop(sheetContext);
                _searchMessages();
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(
                context.tr(ru: 'Пожаловаться на чат', en: 'Report chat'),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _reportConversation();
              },
            ),
            ListTile(
              leading: const Icon(Icons.schedule_send_outlined),
              title: Text(
                context.tr(
                  ru: 'Отложенные сообщения',
                  en: 'Scheduled messages',
                ),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _showScheduledMessages();
              },
            ),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: Text(
                context.tr(
                  ru: 'Автоудаление и защита экрана',
                  en: 'Auto-delete and screen protection',
                ),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _showChatSettings();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reportConversation() async {
    final reason = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          context.tr(ru: 'Жалоба на беседу', en: 'Report conversation'),
        ),
        content: TextField(
          controller: reason,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: context.tr(ru: 'Причина', en: 'Reason'),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr(ru: 'Отправить', en: 'Submit')),
          ),
        ],
      ),
    );
    if (submit == true) {
      final userId = _currentUserId;
      if (userId != null) {
        await ref
            .read(contactRepositoryProvider)
            .reportConversation(
              reporterId: userId,
              conversationId: widget.conversationId,
              reason: reason.text,
            );
      }
    }
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messageState = ref.watch(messagesProvider(widget.conversationId));
    final conversationSettings = ref
        .watch(conversationUserSettingsProvider(widget.conversationId))
        .valueOrNull;
    if (conversationSettings != null &&
        conversationSettings.protectedContent != _protectedContent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            conversationSettings.protectedContent != _protectedContent) {
          unawaited(
            _applyProtectedContent(conversationSettings.protectedContent),
          );
        }
      });
    }
    final mutationState = ref.watch(
      messageMutationProvider(widget.conversationId),
    );
    final typingUsers =
        ref.watch(typingUsersProvider(widget.conversationId)).valueOrNull ??
        const <String>{};
    final currentUserId = ref.watch(currentUserProvider)?.id;
    final reactions =
        ref
            .watch(messageReactionsProvider(widget.conversationId))
            .valueOrNull ??
        const <MessageReaction>[];
    final receipts =
        ref.watch(readReceiptsProvider(widget.conversationId)).valueOrNull ??
        const <ConversationReadReceipt>[];
    final pinnedIds =
        ref
            .watch(pinnedMessageIdsProvider(widget.conversationId))
            .valueOrNull ??
        const <String>{};
    final attachments =
        ref
            .watch(messageAttachmentsProvider(widget.conversationId))
            .valueOrNull ??
        const <String, MessageAttachment>{};
    final polls =
        ref
            .watch(conversationPollsProvider(widget.conversationId))
            .valueOrNull ??
        const <String, PollDetails>{};
    _loadDraft(ref.watch(conversationsProvider).valueOrNull);

    ref.listen<AsyncValue<List<ChatMessage>>>(
      messagesProvider(widget.conversationId),
      (previous, next) {
        final messages = next.valueOrNull;
        if (messages != null && messages.isNotEmpty) {
          unawaited(_markRead(messages));
          if (previous?.valueOrNull?.length != messages.length) {
            ref.invalidate(messageAttachmentsProvider(widget.conversationId));
            ref.invalidate(conversationPollsProvider(widget.conversationId));
          }
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
    ref.listen<AsyncValue<void>>(pollMutationProvider(widget.conversationId), (
      previous,
      next,
    ) {
      if (next.hasError && previous?.error != next.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(next.error!))));
      }
    });
    ref.listen<AsyncValue<void>>(conversationSettingsMutationProvider, (
      previous,
      next,
    ) {
      if (next.hasError && previous?.error != next.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(next.error!))));
      }
    });

    final selecting = _selectedIds.isNotEmpty;
    final messages = messageState.valueOrNull ?? const <ChatMessage>[];
    final tokens = context.tokens;
    final summary = ref
        .watch(conversationsProvider)
        .valueOrNull
        ?.where((item) => item.id == widget.conversationId)
        .firstOrNull;
    final title = widget.title?.trim().isNotEmpty == true
        ? widget.title!
        : context.tr(ru: 'Беседа', en: 'Conversation');

    final screen = Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: selecting
            ? IconButton(
                onPressed: () => setState(_selectedIds.clear),
                icon: const Icon(Icons.close_rounded),
                tooltip: context.tr(ru: 'Снять выделение', en: 'Clear'),
              )
            : null,
        title: selecting
            ? Text(
                '${_selectedIds.length}',
                style: Theme.of(context).textTheme.titleLarge,
              )
            : Row(
                children: [
                  AppAvatar(
                    label: title,
                    imageUrl: summary?.visibleAvatarUrl,
                    seed: widget.conversationId,
                    radius: 19,
                  ),
                  const SizedBox(width: AppSpacing.xs + 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          _presenceLabel(
                            context,
                            isTyping: typingUsers.isNotEmpty,
                            isGroup: widget.isGroup,
                            peerOnline: summary?.peer?.isOnline ?? false,
                            peerLastSeen: summary?.peer?.lastSeenAt,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontSize: 12.5,
                                color: typingUsers.isNotEmpty
                                    ? tokens.accent
                                    : tokens.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: selecting
            ? [
                IconButton(
                  onPressed: () => _copyMessages(messages),
                  icon: const Icon(Icons.copy_rounded),
                  tooltip: context.tr(ru: 'Копировать', en: 'Copy'),
                ),
                IconButton(
                  onPressed: () => _forwardMessages(messages),
                  icon: const Icon(Icons.forward_rounded),
                  tooltip: context.tr(ru: 'Переслать', en: 'Forward'),
                ),
              ]
            : [
                IconButton(
                  onPressed: () => _startCall(context, ref, CallType.audio),
                  icon: const Icon(Icons.phone_rounded),
                  tooltip: context.tr(ru: 'Аудиозвонок', en: 'Audio call'),
                ),
                IconButton(
                  onPressed: () => _startCall(context, ref, CallType.video),
                  icon: const Icon(Icons.videocam_rounded),
                  tooltip: context.tr(ru: 'Видеозвонок', en: 'Video call'),
                ),
                IconButton(
                  onPressed: _searchMessages,
                  icon: const Icon(Icons.search_rounded),
                  tooltip: context.tr(ru: 'Поиск', en: 'Search'),
                ),
                IconButton(
                  onPressed: _showConversationMenu,
                  icon: const Icon(Icons.more_vert_rounded),
                ),
              ],
      ),
      body: ChatWallpaper(
        child: Column(
          children: [
            if (conversationSettings?.autoDeleteEnabled == true ||
                conversationSettings?.protectedContent == true)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                color: tokens.warning.withValues(alpha: 0.16),
                child: Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 18,
                      color: tokens.textPrimary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        [
                          if (conversationSettings?.autoDeleteEnabled == true)
                            '${context.tr(ru: 'Автоудаление', en: 'Auto-delete')}: '
                                '${_autoDeleteLabel(context, conversationSettings!.autoDeleteSeconds)}',
                          if (conversationSettings?.protectedContent == true)
                            _screenProtectionMode == ScreenProtectionMode.native
                                ? context.tr(
                                    ru: 'Защита снимков экрана активна',
                                    en: 'Screenshot protection active',
                                  )
                                : context.tr(
                                    ru: 'Защита экрана best effort: нужен Android host wiring',
                                    en: 'Best-effort screen protection: Android host wiring required',
                                  ),
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            if (pinnedIds.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: tokens.appBar,
                  border: Border(
                    bottom: BorderSide(color: tokens.divider, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Container(width: 2.5, height: 28, color: tokens.accent),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.tr(
                              ru: 'Закреплённые сообщения',
                              en: 'Pinned messages',
                            ),
                            style: TextStyle(
                              color: tokens.accent,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${pinnedIds.length}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.push_pin_rounded,
                      size: 18,
                      color: tokens.textSecondary,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: AsyncStateView<List<ChatMessage>>(
                value: messageState,
                isEmpty: (items) => items.isEmpty,
                emptyTitle: context.tr(
                  ru: 'Начните разговор',
                  en: 'Start a conversation',
                ),
                emptyMessage: context.tr(
                  ru: 'Первое сообщение задаёт настроение.',
                  en: 'The first message sets the tone.',
                ),
                onRetry: () =>
                    ref.invalidate(messagesProvider(widget.conversationId)),
                dataBuilder: (context, items) {
                  final byId = {
                    for (final message in items) message.id: message,
                  };
                  final indexById = {
                    for (var index = 0; index < items.length; index++)
                      items[index].id: index,
                  };
                  final entries = _buildTimeline(items);
                  return ListView.builder(
                    reverse: true,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                      horizontal: AppSpacing.xs,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      // The list is reversed so newest sits at the bottom, but
                      // the timeline is built oldest-first for grouping.
                      final entry = entries[entries.length - 1 - index];
                      final dayStart = entry.dayHeader;
                      if (dayStart != null) {
                        return ServicePill(
                          label: _formatDayHeader(context, dayStart),
                        );
                      }
                      final message = entry.message!;
                      final isMine = message.senderId == currentUserId;
                      final messageReactions = reactions
                          .where((reaction) => reaction.messageId == message.id)
                          .toList();
                      final read =
                          isMine &&
                          receipts.any((receipt) {
                            if (receipt.userId == currentUserId) {
                              return false;
                            }
                            final marker = receipt.lastReadMessageId;
                            if (marker != null &&
                                indexById[marker] != null &&
                                indexById[message.id] != null) {
                              return indexById[marker]! >=
                                  indexById[message.id]!;
                            }
                            return receipt.lastReadAt.isAfter(
                              message.createdAt,
                            );
                          });
                      return EnhancedMessageBubble(
                        message: message,
                        replyMessage: byId[message.replyToId],
                        attachment: attachments[message.id],
                        poll: polls[message.id],
                        isMine: isMine,
                        selected: _selectedIds.contains(message.id),
                        isRead: read,
                        pinned: pinnedIds.contains(message.id),
                        showTail: entry.showTail,
                        isFirstInGroup: entry.isFirstInGroup,
                        reactions: messageReactions,
                        currentUserId: currentUserId,
                        onTap: selecting
                            ? () => _toggleSelection(message)
                            : () {},
                        onLongPress: () => selecting
                            ? _toggleSelection(message)
                            : _showMessageActions(
                                message,
                                isMine: isMine,
                                reactions: reactions,
                                pinned: pinnedIds.contains(message.id),
                              ),
                        onReaction: (emoji) => ref
                            .read(
                              messageMutationProvider(
                                widget.conversationId,
                              ).notifier,
                            )
                            .toggleReaction(
                              message: message,
                              emoji: emoji,
                              selected: messageReactions.any(
                                (reaction) =>
                                    reaction.emoji == emoji &&
                                    reaction.userId == currentUserId,
                              ),
                            ),
                        onVote: (option) {
                          final poll = polls[message.id];
                          if (poll != null) {
                            ref
                                .read(
                                  pollMutationProvider(
                                    widget.conversationId,
                                  ).notifier,
                                )
                                .vote(poll, option);
                          }
                        },
                        onDownload: (attachment) => ref
                            .read(messageRepositoryProvider)
                            .downloadAttachment(attachment),
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
              onAttach: _pickAttachment,
              onLocation: _sendLocation,
              onContact: _sendContact,
              onPoll: _createPoll,
              onSchedule: _scheduleCurrentMessage,
              onVoiceToggle: _toggleRecording,
              isRecording: _recording,
            ),
          ],
        ),
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        screen,
        if (_protectedContent && _privacyCover)
          ColoredBox(
            color: tokens.background,
            child: Center(
              child: Icon(Icons.shield_rounded, size: 56, color: tokens.accent),
            ),
          ),
      ],
    );
  }
}

/// One row of the conversation: either a day separator or a message.
class _TimelineEntry {
  const _TimelineEntry.day(this.dayHeader)
    : message = null,
      showTail = false,
      isFirstInGroup = false;

  const _TimelineEntry.message(
    this.message, {
    required this.showTail,
    required this.isFirstInGroup,
  }) : dayHeader = null;

  final DateTime? dayHeader;
  final ChatMessage? message;

  /// Last message of a same-sender streak — the one that draws the tail.
  final bool showTail;

  /// First message of a streak — gets the wider gap above it.
  final bool isFirstInGroup;
}

/// Messages a sender posts in quick succession render as one block.
const Duration _groupingWindow = Duration(minutes: 5);

/// Expands a chronological message list into rows, inserting a day separator
/// whenever the calendar date changes.
List<_TimelineEntry> _buildTimeline(List<ChatMessage> messages) {
  final entries = <_TimelineEntry>[];
  DateTime? currentDay;

  bool grouped(ChatMessage a, ChatMessage b) =>
      a.senderId == b.senderId &&
      a.kind != MessageKind.system &&
      b.kind != MessageKind.system &&
      b.createdAt.difference(a.createdAt).abs() <= _groupingWindow;

  for (var index = 0; index < messages.length; index++) {
    final message = messages[index];
    final day = DateTime(
      message.createdAt.year,
      message.createdAt.month,
      message.createdAt.day,
    );
    final startsNewDay = currentDay == null || day != currentDay;
    if (startsNewDay) {
      entries.add(_TimelineEntry.day(day));
      currentDay = day;
    }

    final previous = index == 0 ? null : messages[index - 1];
    final next = index == messages.length - 1 ? null : messages[index + 1];
    final nextStartsNewDay =
        next != null &&
        DateTime(
              next.createdAt.year,
              next.createdAt.month,
              next.createdAt.day,
            ) !=
            day;

    entries.add(
      _TimelineEntry.message(
        message,
        isFirstInGroup:
            startsNewDay || previous == null || !grouped(previous, message),
        showTail: next == null || nextStartsNewDay || !grouped(message, next),
      ),
    );
  }
  return entries;
}

/// "Today" / "Yesterday" / a date, matching the chat-list timestamp ladder.
String _formatDayHeader(BuildContext context, DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final daysApart = today.difference(day).inDays;
  if (daysApart == 0) {
    return context.tr(ru: 'Сегодня', en: 'Today');
  }
  if (daysApart == 1) {
    return context.tr(ru: 'Вчера', en: 'Yesterday');
  }
  final locale = context.dateLocale;
  return day.year == now.year
      ? DateFormat('d MMMM', locale).format(day)
      : DateFormat('d MMMM yyyy', locale).format(day);
}

/// Subtitle under the conversation title.
String _presenceLabel(
  BuildContext context, {
  required bool isTyping,
  required bool isGroup,
  required bool peerOnline,
  DateTime? peerLastSeen,
}) {
  if (isTyping) {
    return context.tr(ru: 'печатает…', en: 'typing…');
  }
  if (isGroup) {
    return context.tr(ru: 'группа', en: 'group');
  }
  if (peerOnline) {
    return context.tr(ru: 'в сети', en: 'online');
  }
  if (peerLastSeen == null) {
    return context.tr(ru: 'не в сети', en: 'offline');
  }
  final elapsed = DateTime.now().difference(peerLastSeen);
  if (elapsed.inMinutes < 1) {
    return context.tr(ru: 'был(а) только что', en: 'last seen just now');
  }
  if (elapsed.inHours < 1) {
    return context.tr(
      ru: 'был(а) ${elapsed.inMinutes} мин назад',
      en: 'last seen ${elapsed.inMinutes} min ago',
    );
  }
  if (elapsed.inDays < 1) {
    return context.tr(
      ru: 'был(а) ${elapsed.inHours} ч назад',
      en: 'last seen ${elapsed.inHours} h ago',
    );
  }
  final locale = context.dateLocale;
  return context.tr(
    ru: 'был(а) ${DateFormat('d MMM', locale).format(peerLastSeen)}',
    en: 'last seen ${DateFormat('d MMM', locale).format(peerLastSeen)}',
  );
}

String _mimeFor(String? extension) {
  return switch (extension?.toLowerCase()) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'heic' => 'image/heic',
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    'mp3' => 'audio/mpeg',
    'm4a' => 'audio/mp4',
    'aac' => 'audio/aac',
    'ogg' => 'audio/ogg',
    'wav' => 'audio/wav',
    'pdf' => 'application/pdf',
    'zip' => 'application/zip',
    '7z' => 'application/x-7z-compressed',
    'txt' => 'text/plain',
    'csv' => 'text/csv',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt' => 'application/vnd.ms-powerpoint',
    'pptx' =>
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    _ => 'text/plain',
  };
}

String _scheduledStatusLabel(
  BuildContext context,
  ScheduledMessageStatus status,
) {
  return switch (status) {
    ScheduledMessageStatus.pending => context.tr(ru: 'ожидает', en: 'pending'),
    ScheduledMessageStatus.cancelled => context.tr(
      ru: 'отменено',
      en: 'cancelled',
    ),
    ScheduledMessageStatus.delivered => context.tr(
      ru: 'отправлено',
      en: 'delivered',
    ),
    ScheduledMessageStatus.failed => context.tr(ru: 'ошибка', en: 'failed'),
  };
}

String _autoDeleteLabel(BuildContext context, int? seconds) {
  return switch (seconds) {
    null => context.tr(ru: 'Выключено', en: 'Off'),
    3600 => context.tr(ru: '1 час', en: '1 hour'),
    86400 => context.tr(ru: '1 день', en: '1 day'),
    604800 => context.tr(ru: '7 дней', en: '7 days'),
    2592000 => context.tr(ru: '30 дней', en: '30 days'),
    _ => context.tr(ru: '$seconds сек.', en: '$seconds sec.'),
  };
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
