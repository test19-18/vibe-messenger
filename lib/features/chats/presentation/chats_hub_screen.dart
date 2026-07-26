import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_message.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_tokens.dart';
import '../../../core/widgets/async_state_view.dart';
import '../domain/chat_folder.dart';
import '../domain/conversation_summary.dart';
import '../providers/conversation_providers.dart';
import 'widgets/conversation_tile.dart';

class ChatsHubScreen extends ConsumerStatefulWidget {
  const ChatsHubScreen({super.key});

  @override
  ConsumerState<ChatsHubScreen> createState() => _ChatsHubScreenState();
}

class _ChatsHubScreenState extends ConsumerState<ChatsHubScreen> {
  final _searchController = TextEditingController();
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        _query = '';
      }
    });
  }

  /// Title and last-message search over the already-loaded list, so typing
  /// filters instantly instead of waiting on a round trip.
  List<ConversationSummary> _applyQuery(List<ConversationSummary> items) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return items;
    }
    return items
        .where(
          (item) =>
              item.visibleTitle.toLowerCase().contains(query) ||
              (item.lastMessage?.toLowerCase().contains(query) ?? false),
        )
        .toList();
  }

  Future<void> _createFolder() async {
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

  Future<void> _deleteFolder(ChatFolder folder) async {
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
              style: TextStyle(color: context.tokens.danger),
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
    ConversationSummary conversation,
  ) async {
    final folders =
        ref.read(chatFoldersProvider).valueOrNull ?? const <ChatFolder>[];
    await showModalBottomSheet<void>(
      context: context,
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

  Future<void> _showComposeSheet() async {
    await showModalBottomSheet<void>(
      context: context,
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
              title: Text(context.tr(ru: 'Создать группу', en: 'Create group')),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/groups/new');
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: Text(context.tr(ru: 'Новая папка', en: 'New folder')),
              onTap: () {
                Navigator.pop(sheetContext);
                _createFolder();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
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
      backgroundColor: tokens.background,
      appBar: AppBar(
        titleSpacing: _searching ? 0 : null,
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: context.tr(ru: 'Поиск чатов', en: 'Search chats'),
                ),
                style: Theme.of(context).textTheme.bodyLarge,
              )
            : Text(context.tr(ru: 'Чаты', en: 'Chats')),
        actions: [
          IconButton(
            onPressed: _toggleSearch,
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            tooltip: _searching
                ? context.tr(ru: 'Закрыть поиск', en: 'Close search')
                : context.tr(ru: 'Поиск', en: 'Search'),
          ),
          if (!_searching)
            IconButton(
              onPressed: () => ref.invalidate(conversationsProvider),
              icon: const Icon(Icons.refresh_rounded),
              tooltip: context.tr(ru: 'Обновить', en: 'Refresh'),
            ),
          const SizedBox(width: AppSpacing.xxs),
        ],
        bottom: _FolderTabs(
          filter: filter,
          folderId: folderId,
          folders: folders,
          onFilterSelected: (value) {
            ref.read(chatListFilterProvider.notifier).state = value;
            ref.read(selectedChatFolderProvider.notifier).state = null;
          },
          onFolderSelected: (folder) {
            ref.read(chatListFilterProvider.notifier).state =
                ChatListFilter.all;
            ref.read(selectedChatFolderProvider.notifier).state = folder.id;
          },
          onFolderLongPress: _deleteFolder,
        ),
      ),
      body: AsyncStateView<List<ConversationSummary>>(
        value: conversations,
        isEmpty: (items) => _applyQuery(items).isEmpty,
        emptyTitle: _query.isEmpty
            ? context.tr(ru: 'Здесь пока тихо', en: 'Nothing here yet')
            : context.tr(ru: 'Ничего не найдено', en: 'No matches'),
        emptyMessage: _query.isEmpty
            ? context.tr(
                ru: 'Создайте личный чат или группу.',
                en: 'Start a direct chat or create a group.',
              )
            : context.tr(
                ru: 'Попробуйте другой запрос.',
                en: 'Try a different search.',
              ),
        onRetry: () => ref.invalidate(conversationsProvider),
        dataBuilder: (context, items) {
          final visible = _applyQuery(items);
          return RefreshIndicator(
            onRefresh: () => ref.refresh(conversationsProvider.future),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSizes.contentMaxWidth,
                ),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  // Leaves room for the compose button over the last row.
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 0.5,
                    indent: AppSizes.chatListSeparatorInset,
                    color: tokens.separator,
                  ),
                  itemBuilder: (context, index) {
                    final conversation = visible[index];
                    return ConversationTile(
                      conversation: conversation,
                      onTap: () => context.pushNamed(
                        'conversation',
                        pathParameters: {'conversationId': conversation.id},
                        queryParameters: {
                          'title': conversation.visibleTitle,
                          'group': '${conversation.isGroup}',
                        },
                      ),
                      onLongPress: () => _showConversationActions(conversation),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showComposeSheet,
        tooltip: context.tr(ru: 'Новый чат', en: 'New chat'),
        child: const Icon(Icons.edit_rounded),
      ),
    );
  }
}

/// Scrollable strip of chat filters and user folders under the app bar.
class _FolderTabs extends StatelessWidget implements PreferredSizeWidget {
  const _FolderTabs({
    required this.filter,
    required this.folderId,
    required this.folders,
    required this.onFilterSelected,
    required this.onFolderSelected,
    required this.onFolderLongPress,
  });

  final ChatListFilter filter;
  final String? folderId;
  final List<ChatFolder> folders;
  final ValueChanged<ChatListFilter> onFilterSelected;
  final ValueChanged<ChatFolder> onFolderSelected;
  final ValueChanged<ChatFolder> onFolderLongPress;

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final labels = <ChatListFilter, String>{
      ChatListFilter.all: context.tr(ru: 'Все', en: 'All'),
      ChatListFilter.unread: context.tr(ru: 'Непрочитанные', en: 'Unread'),
      ChatListFilter.direct: context.tr(ru: 'Личные', en: 'Direct'),
      ChatListFilter.groups: context.tr(ru: 'Группы', en: 'Groups'),
      ChatListFilter.archived: context.tr(ru: 'Архив', en: 'Archive'),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.divider, width: 0.5)),
      ),
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          children: [
            for (final entry in labels.entries)
              _Tab(
                label: entry.value,
                selected: filter == entry.key && folderId == null,
                onTap: () => onFilterSelected(entry.key),
              ),
            for (final folder in folders)
              _Tab(
                label: folder.name,
                selected: folderId == folder.id,
                onTap: () => onFolderSelected(folder),
                onLongPress: () => onFolderLongPress(folder),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single tab with an underline indicator that slides in on selection.
class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            // The underline matches the label width, so it needs the column to
            // be sized by its widest child rather than by the viewport.
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? tokens.accent : tokens.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    height: 3,
                    decoration: BoxDecoration(
                      color: selected ? tokens.accent : Colors.transparent,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
