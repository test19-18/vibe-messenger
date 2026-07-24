/// FCM (Firebase Cloud Messaging) service.
///
/// Wraps `firebase_messaging` token management and foreground message
/// handling. The background/isolate handler is a separate top-level function
/// (see [backgroundFcmHandler] at the bottom of this file).
///
/// **Security:** This service never handles service-account credentials.
/// It only acquires the client-side FCM registration token and listens for
/// data messages. The token is registered in `call_devices` via the
/// `register_call_device` RPC under existing Supabase RLS.
library;

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../domain/fcm_payload.dart';

/// Status of the FCM subsystem.
enum FcmStatus { ready, pending, unavailable }

/// Result of an FCM token acquisition attempt.
@immutable
class FcmTokenResult {
  const FcmTokenResult({required this.status, this.token, this.message});

  final FcmStatus status;
  final String? token;
  final String? message;

  bool get hasToken => status == FcmStatus.ready && token != null;
}

/// Service that manages FCM token lifecycle and foreground messages.
///
/// This class is safe to construct even when Firebase is not initialized —
/// all operations catch plugin exceptions and return pending/unavailable
/// results instead of crashing.
class FcmService {
  FcmService();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  String? _currentToken;

  /// Stream of parsed FCM payloads received while the app is in the
  /// foreground. The notifications provider listens to this.
  final StreamController<FcmPayload> _foregroundPayloadController =
      StreamController<FcmPayload>.broadcast();

  Stream<FcmPayload> get foregroundPayloads =>
      _foregroundPayloadController.stream;

  /// Stream of raw FCM messages for debugging or advanced use.
  final StreamController<RemoteMessage> _foregroundMessageController =
      StreamController<RemoteMessage>.broadcast();

  Stream<RemoteMessage> get foregroundMessages =>
      _foregroundMessageController.stream;

  /// Requests the notification permission (Android 13+ POST_NOTIFICATIONS +
  /// iOS alert/badge/sound). On Firebase, this also enables FCM token
  /// delivery.
  ///
  /// Returns a [NotificationSettings] result, or `null` if the plugin is
  /// unavailable.
  Future<NotificationSettings?> requestPermission() async {
    try {
      return await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (error) {
      debugPrint('[FCM] requestPermission failed: $error');
      return null;
    }
  }

  /// Acquires the FCM registration token.
  ///
  /// Returns `FcmTokenResult.pending` if Firebase is not configured.
  Future<FcmTokenResult> getToken() async {
    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) {
        return const FcmTokenResult(
          status: FcmStatus.pending,
          message: 'FCM token недоступен — Firebase не настроен.',
        );
      }
      _currentToken = token;
      return FcmTokenResult(status: FcmStatus.ready, token: token);
    } catch (error) {
      debugPrint('[FCM] getToken failed: $error');
      return FcmTokenResult(
        status: FcmStatus.unavailable,
        message: 'Не удалось получить FCM token: $error',
      );
    }
  }

  /// Returns the cached token (without re-fetching), or `null`.
  String? get cachedToken => _currentToken;

  /// Stream of token refresh events.
  Stream<String> get tokenRefreshStream {
    try {
      return _messaging.onTokenRefresh;
    } catch (error) {
      debugPrint('[FCM] onTokenRefresh failed: $error');
      return const Stream.empty();
    }
  }

  /// Begins listening for foreground FCM messages and token refresh.
  ///
  /// Call this after Firebase is initialized and the app is ready to handle
  /// incoming payloads.
  void startForegroundListener() {
    try {
      FirebaseMessaging.onMessage.listen((message) {
        _foregroundMessageController.add(message);
        final payload = FcmPayload.fromData(message.data);
        if (payload != null) {
          _foregroundPayloadController.add(payload);
        }
      });
    } catch (error) {
      debugPrint('[FCM] onMessage listener failed: $error');
    }
  }

  /// Subscribes to the background message handler and the notification
  /// tap stream (for when the user opens the app by tapping a notification).
  void setupOnMessageOpenedApp({
    required void Function(FcmPayload?) onPayload,
  }) {
    try {
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        onPayload(FcmPayload.fromData(message.data));
      });
    } catch (error) {
      debugPrint('[FCM] onMessageOpenedApp listener failed: $error');
    }
  }

  /// Gets the initial message that launched the app (cold start from a
  /// notification tap).
  Future<FcmPayload?> getInitialMessage() async {
    try {
      final message = await _messaging.getInitialMessage();
      if (message == null) {
        return null;
      }
      return FcmPayload.fromData(message.data);
    } catch (error) {
      debugPrint('[FCM] getInitialMessage failed: $error');
      return null;
    }
  }

  /// Manually deletes the FCM token (used when the user disables push or
  /// signs out).
  Future<void> deleteToken() async {
    try {
      await _messaging.deleteToken();
      _currentToken = null;
    } catch (error) {
      debugPrint('[FCM] deleteToken failed: $error');
    }
  }

  void dispose() {
    _foregroundPayloadController.close();
    _foregroundMessageController.close();
  }
}

// =============================================================================
// Top-level background FCM handler
// =============================================================================

/// **Top-level** background message handler for FCM.
///
/// This function MUST be top-level (not a class method or closure) so that
/// the Dart VM can find it in a background isolate. It must NOT access any
/// UI widgets, providers, or context. It can only perform lightweight,
/// side-effect-free work such as logging or writing to platform channels.
///
/// The actual notification display for data messages in the background is
/// handled by the system notification tray when the server includes a
/// `notification` block, or by a separate background isolate notification
/// manager. For now, we log the payload for debugging.
///
/// To register this handler, call `FirebaseMessaging.onBackgroundMessage(
///   backgroundFcmHandler,
/// )` in `main()` after Firebase initialization.
@pragma('vm:entry-point')
Future<void> backgroundFcmHandler(RemoteMessage message) async {
  // IMPORTANT: No UI access here. This runs in a separate isolate.
  // We only log the payload type for debugging.
  final payload = FcmPayload.fromData(message.data);
  if (kDebugMode) {
    debugPrint(
      '[FCM background] type=${message.data['type']}, '
      'parsed=${payload?.type.name}',
    );
  }

  // If this is a call_cancelled payload, we cannot directly dismiss UI
  // from here (no UI access). The foreground listener will handle it
  // when the app resumes. For background notifications with a
  // `notification` block, the system tray handles dismissal.
  //
  // For incoming_call payloads in the background, the server should include
  // a high-priority `notification` block so the system tray shows it.
  // The client full-screen intent is handled by the notification channel
  // configuration (kCallChannelId with fullScreenIntent: true).
}
