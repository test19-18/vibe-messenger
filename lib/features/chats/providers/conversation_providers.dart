import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_message.dart';
import '../../../core/providers/backend_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/conversation_repository.dart';
import '../domain/chat_folder.dart';
import '../domain/conversation_summary.dart';

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  return ConversationRepository(ref.watch(supabaseClientProvider));
});

final conversationsProvider =
    FutureProvider.autoDispose<List<ConversationSummary>>((ref) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) {
        throw const BackendUnavailableException('Сессия не найдена.');
      }
      return ref
          .watch(conversationRepositoryProvider)
          .listConversations(user.id);
    });

enum ChatListFilter { all, unread, direct, groups, archived }

final chatListFilterProvider = StateProvider.autoDispose<ChatListFilter>(
  (ref) => ChatListFilter.all,
);

final selectedChatFolderProvider = StateProvider.autoDispose<String?>(
  (ref) => null,
);

final chatFoldersProvider = FutureProvider.autoDispose<List<ChatFolder>>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    throw const BackendUnavailableException('Сессия не найдена.');
  }
  return ref.watch(conversationRepositoryProvider).listFolders(user.id);
});

final filteredConversationsProvider =
    FutureProvider.autoDispose<List<ConversationSummary>>((ref) async {
      final items = await ref.watch(conversationsProvider.future);
      final filter = ref.watch(chatListFilterProvider);
      final folderId = ref.watch(selectedChatFolderProvider);
      return items.where((conversation) {
        if (folderId != null && !conversation.folderIds.contains(folderId)) {
          return false;
        }
        return switch (filter) {
          ChatListFilter.all => !conversation.isArchived,
          ChatListFilter.unread =>
            !conversation.isArchived && conversation.unreadCount > 0,
          ChatListFilter.direct =>
            !conversation.isArchived && !conversation.isGroup,
          ChatListFilter.groups =>
            !conversation.isArchived && conversation.isGroup,
          ChatListFilter.archived => conversation.isArchived,
        };
      }).toList();
    });

final conversationSettingsMutationProvider =
    StateNotifierProvider.autoDispose<
      ConversationSettingsController,
      AsyncValue<void>
    >((ref) {
      return ConversationSettingsController(
        repository: ref.watch(conversationRepositoryProvider),
        userId: ref.watch(currentUserProvider)?.id,
        onChanged: () {
          ref.invalidate(conversationsProvider);
          ref.invalidate(chatFoldersProvider);
        },
      );
    });

final directConversationControllerProvider =
    StateNotifierProvider.autoDispose<
      DirectConversationController,
      AsyncValue<String?>
    >((ref) {
      return DirectConversationController(
        ref.watch(conversationRepositoryProvider),
        onCreated: () => ref.invalidate(conversationsProvider),
      );
    });

class ConversationSettingsController extends StateNotifier<AsyncValue<void>> {
  ConversationSettingsController({
    required this.repository,
    required this.userId,
    required this.onChanged,
  }) : super(const AsyncData(null));

  final ConversationRepository repository;
  final String? userId;
  final void Function() onChanged;

  String get _userId =>
      userId ?? (throw const BackendUnavailableException('Нет сессии.'));

  Future<bool> update(
    ConversationSummary conversation, {
    bool? archived,
    bool? pinned,
    DateTime? muteUntil,
    bool clearMute = false,
    String? notificationLevel,
    String? customTitle,
    String? draft,
  }) {
    return _run(
      () => repository.updateConversationSettings(
        conversationId: conversation.id,
        userId: _userId,
        archived: archived,
        pinned: pinned,
        muteUntil: muteUntil,
        clearMute: clearMute,
        notificationLevel: notificationLevel,
        customTitle: customTitle,
        draft: draft,
      ),
    );
  }

  Future<bool> createFolder(String name) {
    return _run(() async {
      await repository.createFolder(userId: _userId, name: name);
    });
  }

  Future<bool> deleteFolder(String folderId) {
    return _run(() => repository.deleteFolder(folderId));
  }

  Future<bool> setFolder({
    required ConversationSummary conversation,
    required ChatFolder folder,
    required bool selected,
  }) {
    return _run(
      () => repository.setConversationFolder(
        folderId: folder.id,
        conversationId: conversation.id,
        userId: _userId,
        selected: selected,
      ),
    );
  }

  Future<bool> _run(Future<void> Function() operation) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(operation);
    if (!mounted) {
      return false;
    }
    state = result;
    if (!result.hasError) {
      onChanged();
    }
    return !result.hasError;
  }
}

class DirectConversationController extends StateNotifier<AsyncValue<String?>> {
  DirectConversationController(this._repository, {required this.onCreated})
    : super(const AsyncData(null));

  final ConversationRepository _repository;
  final void Function() onCreated;

  Future<String?> create({
    required String currentUserId,
    required String otherUserId,
  }) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => _repository.createDirectConversation(
        currentUserId: currentUserId,
        otherUserId: otherUserId,
      ),
    );
    if (!mounted) {
      return null;
    }
    state = result;
    if (!result.hasError) {
      onCreated();
      return result.valueOrNull;
    }
    return null;
  }
}
