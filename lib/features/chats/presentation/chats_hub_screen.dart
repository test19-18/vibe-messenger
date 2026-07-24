import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/error_message.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/async_state_view.dart';
import '../domain/chat_folder.dart';
import '../domain/conversation_summary.dart';
import '../providers/conversation_providers.dart';

class ChatsHubScreen extends ConsumerWidget {
  const ChatsHubScreen({super.key});

  Future<void> _createFolder(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final create = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr(ru: 'Новая папка', en: 'New folder')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: InputDecoration(
            labelText: context.tr(ru: 'Название', en: 'Name'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr(ru: 'Отмена', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr(ru: 'Создать', en: 'Create')),
          ),
        ],
      ),
    );
    if (create == true && controller.text.trim().isNotEmpty) {
      await ref
          .read(conversationSettingsMutationProvider.notifier)
          .createFolder(controller.text);
    }
    controller.dispose();
  }

  Future<void> _deleteFolder(
    BuildContext context,
    WidgetRef ref,
    ChatFolder folder,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr(ru: 'Удалить папку?', en: 'Delete folder?')),
        content: Text(folder.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr(ru: 'Отмена', en: 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              context.tr(ru: 'Удалить', en: 'Delete'),
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(conversationSettingsMutationProvider.notifier)
          .deleteFolder(folder.id);
      if (ref.read(selectedChatFolderProvider) == folder.id) {
        ref.read(selectedChatFolderProvider.notifier).state = null;
      }
    }
  }

  Future<void> _showConversationActions(
    BuildContext context,
    WidgetRef ref,
    ConversationSummary conversation,
  ) async {
    final folders =
        ref.read(chatFoldersProvider).valueOrNull ?? const <ChatFolder>[];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  conversation.isPinned
                      ? Icons.push_pin_outlined
                      : Icons.push_pin_rounded,
                ),
                title: Text(
                  conversation.isPinned
                      ? context.tr(ru: 'Открепить', en: 'Unpin')
                      : context.tr(ru: 'Закрепить', en: 'Pin'),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  ref
                      .read(conversationSettingsMutationProvider.notifier)
                      .update(conversation, pinned: !conversation.isPinned);
                },
              ),
              ListTile(
                leading: Icon(
                  conversation.isMuted
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                ),
                title: Text(
                  conversation.isMuted
                      ? context.tr(ru: 'Включить звук', en: 'Unmute')
                      : context.tr(
                          ru: 'Без звука на 8 часов',
                          en: 'Mute for 8 hours',
                        ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  ref
                      .read(conversationSettingsMutationProvider.notifier)
                      .update(
                        conversation,
                        clearMute: conversation.isMuted,
                        muteUntil: conversation.isMuted
                            ? null
                            : DateTime.now().add(const Duration(hours: 8)),
                      );
                },
              ),
              ListTile(
                leading: Icon(
                  conversation.isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
                title: Text(
                  conversation.isArchived
                      ? context.tr(ru: 'Вернуть из архива', en: 'Unarchive')
                      : context.tr(ru: 'В архив', en: 'Archive'),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  ref
                      .read(conversationSettingsMutationProvider.notifier)
                      .update(conversation, archived: !conversation.isArchived);
                },
              ),
              if (folders.isNotEmpty)
                ExpansionTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(context.tr(ru: 'Папки', en: 'Folders')),
                  children: folders
                      .map(
                        (folder) => CheckboxListTile(
                          value: conversation.folderIds.contains(folder.id),
                          title: Text(folder.name),
                          onChanged: (value) => ref
                              .read(
                                conversationSettingsMutationProvider.notifier,
                              )
                              .setFolder(
                                conversation: conversation,
                                folder: folder,
                                selected: value ?? false,
                              ),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(filteredConversationsProvider);
    final folders =
        ref.watch(chatFoldersProvider).valueOrNull ?? const <ChatFolder>[];
    final filter = ref.watch(chatListFilterProvider);
    final folderId = ref.watch(selectedChatFolderProvider);

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

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(ru: 'Чаты', en: 'Chats')),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(conversationsProvider),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: context.tr(ru: 'Обновить', en: 'Refresh'),
          ),
          IconButton(
            onPressed: () => _createFolder(context, ref),
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: context.tr(ru: 'Новая папка', en: 'New folder'),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              children: [
                _FilterChip(
                  label: context.tr(ru: 'Все', en: 'All'),
                  selected: filter == ChatListFilter.all && folderId == null,
                  onSelected: () {
                    ref.read(chatListFilterProvider.notifier).state =
                        ChatListFilter.all;
                    ref.read(selectedChatFolderProvider.notifier).state = null;
                  },
                ),
                _FilterChip(
                  label: context.tr(ru: 'Непрочитанные', en: 'Unread'),
                  selected: filter == ChatListFilter.unread && folderId == null,
                  onSelected: () {
                    ref.read(chatListFilterProvider.notifier).state =
                        ChatListFilter.unread;
                    ref.read(selectedChatFolderProvider.notifier).state = null;
                  },
                ),
                _FilterChip(
                  label: context.tr(ru: 'Личные', en: 'Direct'),
                  selected: filter == ChatListFilter.direct && folderId == null,
                  onSelected: () {
                    ref.read(chatListFilterProvider.notifier).state =
                        ChatListFilter.direct;
                    ref.read(selectedChatFolderProvider.notifier).state = null;
                  },
                ),
                _FilterChip(
                  label: context.tr(ru: 'Группы', en: 'Groups'),
                  selected: filter == ChatListFilter.groups && folderId == null,
                  onSelected: () {
                    ref.read(chatListFilterProvider.notifier).state =
                        ChatListFilter.groups;
                    ref.read(selectedChatFolderProvider.notifier).state = null;
                  },
                ),
                _FilterChip(
                  label: context.tr(ru: 'Архив', en: 'Archive'),
                  selected:
                      filter == ChatListFilter.archived && folderId == null,
                  onSelected: () {
                    ref.read(chatListFilterProvider.notifier).state =
                        ChatListFilter.archived;
                    ref.read(selectedChatFolderProvider.notifier).state = null;
                  },
                ),
                for (final folder in folders)
                  _FilterChip(
                    label: folder.name,
                    selected: folderId == folder.id,
                    onSelected: () {
                      ref.read(chatListFilterProvider.notifier).state =
                          ChatListFilter.all;
                      ref.read(selectedChatFolderProvider.notifier).state =
                          folder.id;
                    },
                    onLongPress: () => _deleteFolder(context, ref, folder),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncStateView<List<ConversationSummary>>(
              value: conversations,
              isEmpty: (items) => items.isEmpty,
              emptyTitle: context.tr(
                ru: 'Здесь пока тихо',
                en: 'Nothing here yet',
              ),
              emptyMessage: context.tr(
                ru: 'Создайте личный чат или группу.',
                en: 'Start a direct chat or create a group.',
              ),
              onRetry: () => ref.invalidate(conversationsProvider),
              dataBuilder: (context, items) => RefreshIndicator(
                onRefresh: () => ref.refresh(conversationsProvider.future),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                    110,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.xs),
                  itemBuilder: (context, index) {
                    final conversation = items[index];
                    return _ConversationTile(
                      conversation: conversation,
                      onTap: () => context.pushNamed(
                        'conversation',
                        pathParameters: {'conversationId': conversation.id},
                        queryParameters: {
                          'title': conversation.visibleTitle,
                          'group': '${conversation.isGroup}',
                        },
                      ),
                      onLongPress: () =>
                          _showConversationActions(context, ref, conversation),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (sheetContext) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1_rounded),
                  title: Text(
                    context.tr(ru: 'Новый личный чат', en: 'New direct chat'),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    context.go('/contacts');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.group_add_rounded),
                  title: Text(
                    context.tr(ru: 'Создать группу', en: 'Create group'),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    context.push('/groups/new');
                  },
                ),
              ],
            ),
          ),
        ),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onSelected(),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.onTap,
    required this.onLongPress,
  });

  final ConversationSummary conversation;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final timestamp = conversation.lastMessageAt ?? conversation.updatedAt;
    final now = DateTime.now();
    final sameDay =
        now.year == timestamp.year &&
        now.month == timestamp.month &&
        now.day == timestamp.day;
    final time = sameDay
        ? DateFormat('HH:mm').format(timestamp)
        : DateFormat('dd.MM').format(timestamp);
    final draft = conversation.draft?.trim();
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        leading: AppAvatar(
          label: conversation.visibleTitle,
          imageUrl: conversation.visibleAvatarUrl,
          seed: conversation.id,
          radius: 27,
        ),
        title: Row(
          children: [
            if (conversation.isPinned)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.push_pin_rounded, size: 15),
              ),
            Expanded(
              child: Text(
                conversation.visibleTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (conversation.isMuted)
              const Icon(Icons.volume_off_rounded, size: 16),
            const SizedBox(width: AppSpacing.xs),
            Text(time, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        subtitle: Text(
          draft?.isNotEmpty == true
              ? '${context.tr(ru: 'Черновик', en: 'Draft')}: $draft'
              : conversation.lastMessage ??
                    context.tr(ru: 'Новая беседа', en: 'New conversation'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: draft?.isNotEmpty == true
              ? const TextStyle(color: AppColors.danger)
              : null,
        ),
        trailing: conversation.unreadCount == 0
            ? null
            : Badge(
                label: Text(
                  conversation.unreadCount > 99
                      ? '99+'
                      : '${conversation.unreadCount}',
                ),
              ),
      ),
    );
  }
}
