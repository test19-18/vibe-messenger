import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_message.dart';
import '../../../core/providers/backend_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/contact_repository.dart';
import '../domain/contact_relationship.dart';

final contactRepositoryProvider = Provider<ContactRepository>((ref) {
  return ContactRepository(ref.watch(supabaseClientProvider));
});

final contactRelationshipsProvider =
    FutureProvider.autoDispose<List<ContactRelationship>>((ref) async {
      final userId = ref.watch(currentUserProvider)?.id;
      if (userId == null) {
        throw const BackendUnavailableException('Сессия не найдена.');
      }
      return ref.watch(contactRepositoryProvider).listRelationships(userId);
    });

final blockedUsersProvider = FutureProvider.autoDispose<List<BlockedUser>>((
  ref,
) async {
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null) {
    throw const BackendUnavailableException('Сессия не найдена.');
  }
  return ref.watch(contactRepositoryProvider).listBlockedUsers(userId);
});

final contactMutationProvider =
    StateNotifierProvider.autoDispose<
      ContactMutationController,
      AsyncValue<void>
    >(
      (ref) => ContactMutationController(
        repository: ref.watch(contactRepositoryProvider),
        currentUserId: ref.watch(currentUserProvider)?.id,
        onChanged: () {
          ref.invalidate(contactRelationshipsProvider);
          ref.invalidate(blockedUsersProvider);
        },
      ),
    );

class ContactMutationController extends StateNotifier<AsyncValue<void>> {
  ContactMutationController({
    required this.repository,
    required this.currentUserId,
    required this.onChanged,
  }) : super(const AsyncData(null));

  final ContactRepository repository;
  final String? currentUserId;
  final void Function() onChanged;

  String get _userId =>
      currentUserId ?? (throw const BackendUnavailableException('Нет сессии.'));

  Future<bool> sendRequest(String otherUserId) => _run(
    () =>
        repository.sendRequest(requesterId: _userId, addresseeId: otherUserId),
  );

  Future<bool> updateStatus(String id, ContactStatus status) =>
      _run(() => repository.updateStatus(id, status));

  Future<bool> remove(String id) => _run(() => repository.removeContact(id));

  Future<bool> block(String otherUserId) =>
      _run(() => repository.block(blockerId: _userId, blockedId: otherUserId));

  Future<bool> unblock(String otherUserId) => _run(
    () => repository.unblock(blockerId: _userId, blockedId: otherUserId),
  );

  Future<bool> reportUser(
    String otherUserId,
    String reason, {
    String? details,
  }) => _run(
    () => repository.reportUser(
      reporterId: _userId,
      userId: otherUserId,
      reason: reason,
      details: details,
    ),
  );

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(action);
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
