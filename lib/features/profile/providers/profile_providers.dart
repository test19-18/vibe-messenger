import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_message.dart';
import '../../../core/providers/backend_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/profile_repository.dart';
import '../domain/user_profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider));
});

final myProfileProvider = FutureProvider.autoDispose<UserProfile>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    throw const BackendUnavailableException('Сессия не найдена.');
  }
  final profile = await ref
      .watch(profileRepositoryProvider)
      .getProfile(user.id);
  return profile ?? UserProfile.fromAuthUser(user);
});

final contactsQueryProvider = StateProvider.autoDispose<String>((ref) => '');

final contactsProvider = FutureProvider.autoDispose<List<UserProfile>>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    throw const BackendUnavailableException('Сессия не найдена.');
  }
  final query = ref.watch(contactsQueryProvider);
  return ref
      .watch(profileRepositoryProvider)
      .listProfiles(currentUserId: user.id, query: query);
});

final profileEditorProvider =
    StateNotifierProvider.autoDispose<ProfileEditor, AsyncValue<UserProfile?>>(
      (ref) => ProfileEditor(
        ref.watch(profileRepositoryProvider),
        onSaved: () => ref.invalidate(myProfileProvider),
      ),
    );

class ProfileEditor extends StateNotifier<AsyncValue<UserProfile?>> {
  ProfileEditor(this._repository, {required this.onSaved})
    : super(const AsyncData(null));

  final ProfileRepository _repository;
  final void Function() onSaved;

  Future<String?> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => _repository.uploadAvatar(
        userId: userId,
        bytes: bytes,
        extension: extension,
        contentType: contentType,
      ),
    );
    if (!mounted) {
      return null;
    }
    if (result.hasError) {
      state = AsyncError(result.error!, result.stackTrace!);
      return null;
    }
    state = const AsyncData(null);
    return result.valueOrNull;
  }

  Future<bool> save(UserProfile profile) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => _repository.upsertProfile(profile),
    );
    if (!mounted) {
      return false;
    }
    state = result;
    if (!result.hasError) {
      onSaved();
    }
    return !result.hasError;
  }
}
