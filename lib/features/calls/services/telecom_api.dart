import 'package:flutter/services.dart';

/// Abstraction for native Core-Telecom / Connection Service integration.
///
/// On Android, this would wrap `TelecomManager` / `ConnectionService`
/// to integrate VoIP calls with the system phone UI, showing native
/// call notifications, lock-screen call controls, and audio routing
/// through the system's call audio focus.
///
/// On iOS, this would wrap `CallKit` (CXProvider) similarly.
///
/// **Current status:** This is a documented interface only. The native
/// implementation is not included. The Flutter side calls through a
/// `MethodChannel("vibe/telecom")` which, when the native handler is
/// registered, will bridge to platform APIs. Until then, all methods
/// return [TelecomResult.unsupported] gracefully.
///
/// Firebase push for incoming background calls is also pending — see
/// `docs/FEATURE_STATUS.md`.
abstract interface class TelecomApi {
  /// Display a native incoming-call UI (lock screen / notification).
  ///
  /// On Android, this would call `ConnectionService.addExistingConnection`
  /// or show a full-screen notification via `NotificationBuilder`.
  /// On iOS, this would call `CXProvider.reportNewIncomingCall`.
  Future<TelecomResult> displayIncomingCall({
    required String callId,
    required String callerName,
    required bool hasVideo,
  });

  /// End the native call UI.
  Future<TelecomResult> endCall({required String callId});

  /// Set the native call state (active, held, ended, etc.).
  Future<TelecomResult> setCallState({
    required String callId,
    required TelecomCallState state,
  });

  /// Configure audio routing for an active call (speaker, bluetooth, earpiece).
  Future<TelecomResult> setAudioRoute(TelecomAudioRoute route);

  /// Whether the native telecom integration is available on this platform.
  ///
  /// Returns false until the native MethodChannel handler is registered.
  Future<bool> isAvailable();
}

/// Result of a telecom operation.
enum TelecomResult { success, unsupported, error }

/// Call states for the native telecom UI.
enum TelecomCallState {
  active,
  held,
  dialing,
  alerting, // ringing on the remote side
  incoming,
  ended,
}

/// Audio output routes.
enum TelecomAudioRoute { earpiece, speaker, bluetooth, wiredHeadset }

/// MethodChannel-based implementation of [TelecomApi].
///
/// This is the default implementation. It communicates with the native
/// side via `MethodChannel("vibe/telecom")`. If no native handler is
/// registered, the channel call will fail and [TelecomResult.unsupported]
/// is returned.
class MethodChannelTelecomApi implements TelecomApi {
  const MethodChannelTelecomApi();

  static const _channel = MethodChannel('vibe/telecom');

  @override
  Future<TelecomResult> displayIncomingCall({
    required String callId,
    required String callerName,
    required bool hasVideo,
  }) async {
    return _invoke('displayIncomingCall', {
      'callId': callId,
      'callerName': callerName,
      'hasVideo': hasVideo,
    });
  }

  @override
  Future<TelecomResult> endCall({required String callId}) async {
    return _invoke('endCall', {'callId': callId});
  }

  @override
  Future<TelecomResult> setCallState({
    required String callId,
    required TelecomCallState state,
  }) async {
    return _invoke('setCallState', {'callId': callId, 'state': state.name});
  }

  @override
  Future<TelecomResult> setAudioRoute(TelecomAudioRoute route) async {
    return _invoke('setAudioRoute', {'route': route.name});
  }

  @override
  Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  Future<TelecomResult> _invoke(
    String method,
    Map<String, dynamic> args,
  ) async {
    try {
      await _channel.invokeMethod(method, args);
      return TelecomResult.success;
    } on PlatformException catch (_) {
      return TelecomResult.error;
    } on MissingPluginException catch (_) {
      // No native handler registered — the integration is pending.
      return TelecomResult.unsupported;
    }
  }
}
