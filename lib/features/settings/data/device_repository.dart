import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/error_message.dart';
import '../domain/user_device.dart';

class DeviceRepository {
  const DeviceRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _requiredClient =>
      _client ?? (throw const BackendUnavailableException());

  Future<List<UserDevice>> listDevices(String userId) async {
    final rows = await _requiredClient
        .from('user_devices')
        .select(
          'id,user_id,platform,device_name,app_version,last_seen_at,'
          'disabled_at,created_at',
        )
        .eq('user_id', userId)
        .order('last_seen_at', ascending: false);
    return rows.map(UserDevice.fromMap).toList();
  }

  Future<String> registerDeviceToken({
    required String platform,
    required String token,
    String? deviceName,
    String? appVersion,
  }) async {
    final response = await _requiredClient.rpc(
      'register_device',
      params: {
        '_platform': platform,
        '_fcm_token': token.trim(),
        '_device_name': deviceName?.trim(),
        '_app_version': appVersion?.trim(),
      },
    );
    if (response is! String) {
      throw const FormatException(
        'Backend не вернул идентификатор устройства.',
      );
    }
    return response;
  }

  Future<void> disableDevice(String deviceId) async {
    await _requiredClient
        .from('user_devices')
        .update({'disabled_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', deviceId);
  }

  Future<void> removeDevice(String deviceId) async {
    await _requiredClient.from('user_devices').delete().eq('id', deviceId);
  }
}
