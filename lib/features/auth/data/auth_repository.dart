import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/error_message.dart';

class AuthRepository {
  const AuthRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _requiredClient =>
      _client ?? (throw const BackendUnavailableException());

  Session? get currentSession => _client?.auth.currentSession;

  User? get currentUser => _client?.auth.currentUser;

  Stream<Session?> sessionChanges() async* {
    yield currentSession;
    final client = _client;
    if (client == null) {
      return;
    }
    yield* client.auth.onAuthStateChange
        .map((state) => state.session)
        .distinct(
          (previous, next) => previous?.accessToken == next?.accessToken,
        );
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _requiredClient.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String displayName,
  }) {
    return _requiredClient.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': displayName.trim()},
    );
  }

  Future<void> resetPassword(String email) {
    return _requiredClient.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> signOut() => _requiredClient.auth.signOut();
}
