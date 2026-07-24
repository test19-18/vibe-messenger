/// Notifications repository — manages FCM token registration in `call_devices`
/// under existing Supabase RLS.
///
/// Uses the `register_call_device` SECURITY DEFINER RPC (already defined in
/// migration `202607240004_calls.sql`) to upsert the FCM token. The RPC
/// enforces `auth.uid() = user_id` and handles the `on conflict (fcm_token)`
/// upsert. Direct table operations (delete/disable) use the RLS policies
/// `call_devices_delete_self` and `call_devices_update_self`.
///
/// This repository follows the same pattern as [DeviceRepository] in the
/// settings feature: it takes a nullable `SupabaseClient` and throws
/// [BackendUnavailableException] when the client is null.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/error_message.dart';

/// Platform string for `call_devices.platform` (matches `device_platform`
/// enum: 'android', 'ios', 'web', 'desktop').
String get currentPlatform => Platform.isAndroid
    ? 'android'
    : Platform.isIOS
    ? 'ios'
    : kIsWeb
    ? 'web'
    : 'desktop';

/// Repository for FCM token lifecycle in `call_devices`.
class NotificationsRepository {
  const NotificationsRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _requiredClient =>
      _client ?? (throw const BackendUnavailableException());

  /// Registers (upserts) the FCM token via the `register_call_device` RPC.
  ///
  /// Returns the device UUID from the `call_devices` table. The RPC uses
  /// `auth.uid()` internally, so no user ID is passed from the client.
  Future<String> registerCallDevice({
    required String fcmToken,
    String? deviceName,
    String? appVersion,
  }) async {
    final response = await _requiredClient.rpc(
      'register_call_device',
      params: {
        '_platform': currentPlatform,
        '_fcm_token': fcmToken.trim(),
        '_device_name': deviceName?.trim(),
        '_app_version': appVersion?.trim(),
      },
    );
    if (response is! String) {
      throw const FormatException(
        'Backend не вернул идентификатор устройства для звонков.',
      );
    }
    return response;
  }

  /// Deletes the `call_devices` row for the given FCM token.
  ///
  /// Uses the `call_devices_delete_self` RLS policy (user_id = auth.uid()).
  /// This is called when the user disables push or signs out.
  Future<void> deleteCallDeviceByToken(String fcmToken) async {
    await _requiredClient
        .from('call_devices')
        .delete()
        .eq('fcm_token', fcmToken.trim());
  }

  /// Disables the `call_devices` row for the given FCM token (soft-delete
  /// via `disabled_at` timestamp). Uses the `call_devices_update_self` RLS
  /// policy.
  Future<void> disableCallDeviceByToken(String fcmToken) async {
    await _requiredClient
        .from('call_devices')
        .update({'disabled_at': DateTime.now().toUtc().toIso8601String()})
        .eq('fcm_token', fcmToken.trim());
  }
}

/// Whether the current platform supports FCM (Android or iOS).
bool get isFcmSupportedPlatform => Platform.isAndroid || Platform.isIOS;
