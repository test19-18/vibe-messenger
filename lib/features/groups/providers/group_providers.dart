import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/backend_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../chats/data/conversation_repository.dart';
import '../../chats/providers/conversation_providers.dart';
import '../data/group_repository.dart';
import '../domain/group_models.dart';

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return GroupRepository(ref.watch(supabaseClientProvider));
});

final groupDetailsProvider = FutureProvider.autoDispose
    .family<GroupDetails, String>((ref, conversationId) {
      return ref.watch(groupRepositoryProvider).getGroup(conversationId);
    });

final groupMembersProvider = FutureProvider.autoDispose
    .family<List<GroupMember>, String>((ref, conversationId) {
      return ref.watch(groupRepositoryProvider).listMembers(conversationId);
    });

final myGroupInvitationsProvider =
    FutureProvider.autoDispose<List<GroupInvitation>>((ref) async {
      final userId = ref.watch(currentUserProvider)?.id;
      if (userId == null) {
        return const [];
      }
      return ref.watch(groupRepositoryProvider).listUserInvitations(userId);
    });

final groupInvitationsProvider = FutureProvider.autoDispose
    .family<List<GroupInvitation>, String>((ref, conversationId) {
      return ref.watch(groupRepositoryProvider).listInvitations(conversationId);
    });

final groupJoinRequestsProvider = FutureProvider.autoDispose
    .family<List<GroupJoinRequest>, String>((ref, conversationId) {
      return ref
          .watch(groupRepositoryProvider)
          .listJoinRequests(conversationId);
    });

final groupMutationProvider = StateNotifierProvider.autoDispose
    .family<GroupMutationController, AsyncValue<String?>, String>((
      ref,
      conversationId,
    ) {
      return GroupMutationController(
        repository: ref.watch(groupRepositoryProvider),
        conversationId: conversationId,
        currentUserId: ref.watch(currentUserProvider)?.id,
        onChanged: () {
          ref.invalidate(groupDetailsProvider(conversationId));
          ref.invalidate(groupMembersProvider(conversationId));
          ref.invalidate(groupInvitationsProvider(conversationId));
          ref.invalidate(groupJoinRequestsProvider(conversationId));
          ref.invalidate(conversationsProvider);
        },
      );
    });

class GroupMutationController extends StateNotifier<AsyncValue<String?>> {
  GroupMutationController({
    required this.repository,
    required this.conversationId,
    required this.currentUserId,
    required this.onChanged,
  }) : super(const AsyncData(null));

  final GroupRepository repository;
  final String conversationId;
  final String? currentUserId;
  final void Function() onChanged;

  Future<bool> updateGroup({
    required String title,
    String? description,
    String? avatarPath,
    required bool isLocked,
    required bool joinRequestsEnabled,
  }) => _run(() async {
    await repository.updateGroup(
      conversationId: conversationId,
      title: title,
      description: description,
      avatarPath: avatarPath,
      isLocked: isLocked,
      joinRequestsEnabled: joinRequestsEnabled,
    );
    return null;
  });

  Future<bool> updateMember(String userId, {String? role, String? status}) =>
      _run(() async {
        await repository.updateMember(
          conversationId: conversationId,
          userId: userId,
          role: role,
          status: status,
        );
        return null;
      });

  Future<bool> transferOwnership(String userId) => _run(() async {
    await repository.transferOwnership(
      conversationId: conversationId,
      newOwnerId: userId,
    );
    return null;
  });

  Future<bool> invite(String userId) => _run(() async {
    final current = currentUserId;
    if (current == null) {
      throw const FormatException('Сессия не найдена.');
    }
    await repository.inviteUser(
      conversationId: conversationId,
      inviterId: current,
      inviteeId: userId,
    );
    return null;
  });

  Future<GroupInviteLink?> createLink({
    DateTime? expiresAt,
    int maxUses = 10,
  }) async {
    GroupInviteLink? link;
    final success = await _run(() async {
      link = await repository.createInviteLink(
        conversationId: conversationId,
        expiresAt: expiresAt,
        maxUses: maxUses,
      );
      return link?.token;
    });
    return success ? link : null;
  }

  Future<bool> reviewRequest(String id, {required bool approve}) =>
      _run(() async {
        await repository.reviewJoinRequest(id, approve: approve);
        return null;
      });

  Future<bool> saveMemberTag(String memberId, String? tag) => _run(() async {
    await repository.saveMemberTag(
      conversationId: conversationId,
      memberId: memberId,
      tag: tag,
    );
    return null;
  });

  Future<bool> _run(Future<String?> Function() operation) async {
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

final groupCreationProvider =
    StateNotifierProvider.autoDispose<
      GroupCreationController,
      AsyncValue<String?>
    >(
      (ref) => GroupCreationController(
        repository: ref.watch(conversationRepositoryProvider),
        onCreated: () => ref.invalidate(conversationsProvider),
      ),
    );

class GroupCreationController extends StateNotifier<AsyncValue<String?>> {
  GroupCreationController({required this.repository, required this.onCreated})
    : super(const AsyncData(null));

  final ConversationRepository repository;
  final void Function() onCreated;

  Future<String?> create(String title, String? description) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard<String?>(
      () => repository.createGroup(title: title, description: description),
    );
    if (!mounted) {
      return null;
    }
    state = result;
    if (!result.hasError) {
      onCreated();
    }
    return result.valueOrNull;
  }
}
