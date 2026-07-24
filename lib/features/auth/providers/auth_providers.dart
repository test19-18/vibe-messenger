import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/backend_providers.dart';
import '../data/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

final authSessionProvider = StreamProvider<Session?>((ref) {
  return ref.watch(authRepositoryProvider).sessionChanges();
});

final currentUserProvider = Provider<User?>((ref) {
  final session = ref.watch(authSessionProvider).valueOrNull;
  return session?.user ?? ref.watch(authRepositoryProvider).currentUser;
});

enum AuthAction { signIn, signUp, resendConfirmation, resetPassword, signOut }

final authControllerProvider = StateNotifierProvider.autoDispose
    .family<AuthController, AsyncValue<void>, AuthAction>((ref, _) {
      return AuthController(ref.watch(authRepositoryProvider));
    });

class AuthController extends StateNotifier<AsyncValue<void>> {
  AuthController(this._repository) : super(const AsyncData(null));

  final AuthRepository _repository;

  Future<bool> signIn({required String email, required String password}) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final response = await _repository.signIn(
        email: email,
        password: password,
      );
      if (response.session == null) {
        throw const AuthException('Сессия не была создана.');
      }
    });
    if (mounted) {
      state = result;
    }
    return !result.hasError;
  }

  Future<AuthResponse?> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    AuthResponse? response;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final signedUp = await _repository.signUp(
        email: email,
        password: password,
        displayName: displayName,
      );
      if (signedUp.user == null) {
        throw const AuthException('Аккаунт не был создан.');
      }
      response = signedUp;
    });
    if (mounted) {
      state = result;
    }
    return result.hasError ? null : response;
  }

  Future<bool> resendSignupConfirmation(String email) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => _repository.resendSignupConfirmation(email),
    );
    if (mounted) {
      state = result;
    }
    return !result.hasError;
  }

  Future<bool> resetPassword(String email) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => _repository.resetPassword(email),
    );
    if (mounted) {
      state = result;
    }
    return !result.hasError;
  }

  Future<bool> signOut() async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(_repository.signOut);
    if (mounted) {
      state = result;
    }
    return !result.hasError;
  }

  void clearError() {
    state = const AsyncData(null);
  }
}
