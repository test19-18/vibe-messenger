import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/error_message.dart';
import '../domain/app_preferences.dart';

class SettingsRepository {
  const SettingsRepository(this._client);

  static const _localKey = 'vibe.app_preferences.v1';
  final SupabaseClient? _client;

  Future<AppPreferences> load(String? userId) async {
    final local = await _loadLocal();
    if (_client == null || userId == null) {
      return local;
    }
    try {
      final row = await _client
          .from('user_settings')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) {
        return local;
      }
      final remote = AppPreferences.fromMap(row);
      await _saveLocal(remote);
      return remote;
    } catch (_) {
      return local;
    }
  }

  Future<void> save(AppPreferences preferences, String? userId) async {
    await _saveLocal(preferences);
    if (_client == null || userId == null) {
      return;
    }
    final updated = await _client
        .from('user_settings')
        .update(preferences.toBackendMap())
        .eq('user_id', userId)
        .select('user_id')
        .maybeSingle();
    if (updated == null) {
      await _client.from('user_settings').insert({
        'user_id': userId,
        ...preferences.toBackendMap(),
      });
    }
  }

  Future<AppPreferences> _loadLocal() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final encoded = preferences.getString(_localKey);
      if (encoded == null) {
        return const AppPreferences();
      }
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        return const AppPreferences();
      }
      return AppPreferences.fromMap(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return const AppPreferences();
    }
  }

  Future<void> _saveLocal(AppPreferences value) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_localKey, jsonEncode(value.toMap()));
    } catch (error) {
      if (_client == null) {
        throw BackendUnavailableException(
          'Не удалось сохранить настройки: $error',
        );
      }
    }
  }
}
