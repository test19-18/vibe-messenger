import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class TypingService {
  TypingService({
    required this.client,
    required this.conversationId,
    required this.currentUserId,
  }) {
    _connect();
    _expiryTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _removeExpired(),
    );
  }

  final SupabaseClient? client;
  final String conversationId;
  final String? currentUserId;
  final _controller = StreamController<Set<String>>.broadcast();
  final _expiresAt = <String, DateTime>{};
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  Timer? _expiryTimer;
  bool _lastSentTyping = false;

  Stream<Set<String>> get users async* {
    yield const <String>{};
    yield* _controller.stream;
  }

  void _connect() {
    final backendClient = client;
    if (backendClient == null || currentUserId == null) {
      return;
    }

    _subscription = backendClient
        .from('conversation_typing')
        .stream(primaryKey: ['conversation_id', 'user_id'])
        .eq('conversation_id', conversationId)
        .listen(
          _handleRows,
          onError: (Object error, StackTrace stackTrace) {
            _expiresAt.clear();
            _emit();
          },
        );
  }

  void _handleRows(List<Map<String, dynamic>> rows) {
    final now = DateTime.now();
    _expiresAt.clear();
    for (final row in rows) {
      final userId = _string(row['user_id']);
      final expiresAt = _date(row['expires_at']);
      final isTyping = row['is_typing'] as bool? ?? false;
      if (userId != null &&
          userId != currentUserId &&
          isTyping &&
          expiresAt != null &&
          expiresAt.isAfter(now)) {
        _expiresAt[userId] = expiresAt;
      }
    }
    _emit();
  }

  Future<void> setTyping(bool isTyping) async {
    final backendClient = client;
    final userId = currentUserId;
    if (backendClient == null ||
        userId == null ||
        _lastSentTyping == isTyping) {
      return;
    }
    _lastSentTyping = isTyping;
    try {
      if (isTyping) {
        final expiresAt = DateTime.now()
            .toUtc()
            .add(const Duration(seconds: 12))
            .toIso8601String();
        final updated = await backendClient
            .from('conversation_typing')
            .update({'is_typing': true, 'expires_at': expiresAt})
            .eq('conversation_id', conversationId)
            .eq('user_id', userId)
            .select('user_id')
            .maybeSingle();
        if (updated == null) {
          await backendClient.from('conversation_typing').insert({
            'conversation_id': conversationId,
            'user_id': userId,
            'is_typing': true,
            'expires_at': expiresAt,
          });
        }
      } else {
        await backendClient
            .from('conversation_typing')
            .delete()
            .eq('conversation_id', conversationId)
            .eq('user_id', userId);
      }
    } catch (_) {
      _lastSentTyping = !isTyping;
    }
  }

  void _removeExpired() {
    final now = DateTime.now();
    final before = _expiresAt.length;
    _expiresAt.removeWhere((key, value) => !value.isAfter(now));
    if (before != _expiresAt.length) {
      _emit();
    }
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(Set.unmodifiable(_expiresAt.keys));
    }
  }

  void dispose() {
    _expiryTimer?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(setTyping(false).catchError((_) {}));
    unawaited(_controller.close());
  }
}

String? _string(Object? value) => value is String ? value : null;

DateTime? _date(Object? value) {
  if (value is DateTime) {
    return value.toLocal();
  }
  if (value is String) {
    return DateTime.tryParse(value)?.toLocal();
  }
  return null;
}
