import 'package:supabase_flutter/supabase_flutter.dart';

class PresenceRepository {
  const PresenceRepository(this._client);

  final SupabaseClient? _client;

  Future<void> heartbeat({required String userId, required bool online}) async {
    final client = _client;
    if (client == null) {
      return;
    }
    final onlineUntil = online
        ? DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 2))
              .toIso8601String()
        : null;
    final updated = await client
        .from('user_presence')
        .update({'online_until': onlineUntil})
        .eq('user_id', userId)
        .select('user_id')
        .maybeSingle();
    if (updated == null) {
      await client.from('user_presence').insert({
        'user_id': userId,
        'online_until': onlineUntil,
      });
    }
  }
}
