/// Local notifications service (flutter_local_notifications wrapper).
///
/// Creates two Android notification channels (messages + incoming calls),
/// shows foreground notifications when FCM data messages arrive while the
/// app is in the foreground, and handles notification taps.
///
/// This service is intentionally thin: it does not decide *what* to show —
/// the [NotificationsService] makes that decision and delegates the actual
/// display here. This separation keeps the local-notification plugin usage
/// isolated and testable.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../domain/notification_channels.dart';

class LocalNotificationsService {
  LocalNotificationsService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Initializes the plugin and creates Android notification channels.
  ///
  /// Returns `false` if initialization fails (e.g. on a non-Android platform
  /// without proper setup). The caller should treat `false` as "local
  /// notifications unavailable" and continue gracefully.
  Future<bool> initialize() async {
    if (_initialized) {
      return true;
    }

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/vibe_launcher_icon'),
    );

    try {
      final result = await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );
      _initialized = result ?? false;
    } catch (error) {
      debugPrint('[LocalNotifications] init failed: $error');
      _initialized = false;
    }

    if (_initialized && defaultTargetPlatform == TargetPlatform.android) {
      await _createAndroidChannels();
    }

    return _initialized;
  }

  /// Creates the two Android notification channels with appropriate
  /// importance levels.
  Future<void> _createAndroidChannels() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) {
      return;
    }

    // Messages channel — high importance (heads-up).
    const messageChannel = AndroidNotificationChannel(
      kMessageChannelId,
      kMessageChannelName,
      description: kMessageChannelDescription,
      importance: Importance.high,
    );

    // Incoming calls channel — maximum importance (full-screen / heads-up).
    const callChannel = AndroidNotificationChannel(
      kCallChannelId,
      kCallChannelName,
      description: kCallChannelDescription,
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    );

    try {
      await androidPlugin.createNotificationChannel(messageChannel);
      await androidPlugin.createNotificationChannel(callChannel);
    } catch (error) {
      debugPrint('[LocalNotifications] channel creation failed: $error');
    }
  }

  /// Requests the Android 13+ POST_NOTIFICATIONS permission.
  ///
  /// Returns `true` if granted. On older Android versions, returns `true`
  /// (permission is granted at install time).
  Future<bool> requestNotificationPermission() async {
    if (!_initialized) {
      return false;
    }
    if (defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) {
      return false;
    }
    try {
      final result = await androidPlugin.requestNotificationsPermission();
      return result ?? false;
    } catch (error) {
      debugPrint('[LocalNotifications] permission request failed: $error');
      return false;
    }
  }

  /// Shows a chat-message notification on the messages channel.
  Future<void> showMessageNotification({
    required String title,
    required String body,
    required int notificationId,
  }) async {
    if (!_initialized) {
      return;
    }
    const androidDetails = AndroidNotificationDetails(
      kMessageChannelId,
      kMessageChannelName,
      channelDescription: kMessageChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
    );
    const details = NotificationDetails(android: androidDetails);
    try {
      await _plugin.show(
        id: notificationId,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (error) {
      debugPrint('[LocalNotifications] show message failed: $error');
    }
  }

  /// Shows an incoming-call notification on the calls channel with
  /// maximum priority (full-screen on lock screen).
  Future<void> showIncomingCallNotification({
    required String callerName,
    required bool isVideo,
    required int notificationId,
  }) async {
    if (!_initialized) {
      return;
    }
    const androidDetails = AndroidNotificationDetails(
      kCallChannelId,
      kCallChannelName,
      channelDescription: kCallChannelDescription,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
    );
    const details = NotificationDetails(android: androidDetails);
    final title = isVideo ? 'Видеозвонок' : 'Входящий звонок';
    try {
      await _plugin.show(
        id: notificationId,
        title: title,
        body: '$callerName звонит',
        notificationDetails: details,
      );
    } catch (error) {
      debugPrint('[LocalNotifications] show call failed: $error');
    }
  }

  /// Cancels a single notification (e.g. when a call is cancelled).
  Future<void> cancel(int notificationId) async {
    if (!_initialized) {
      return;
    }
    try {
      await _plugin.cancel(id: notificationId);
    } catch (error) {
      debugPrint('[LocalNotifications] cancel failed: $error');
    }
  }

  /// Cancels all notifications.
  Future<void> cancelAll() async {
    if (!_initialized) {
      return;
    }
    try {
      await _plugin.cancelAll();
    } catch (error) {
      debugPrint('[LocalNotifications] cancelAll failed: $error');
    }
  }

  /// Notification tap callback — exposed via [tapEventStream] so the
  /// notifications provider can react (navigate to conversation, etc.).
  void Function(NotificationResponse)? onTap;

  void _onNotificationTap(NotificationResponse response) {
    debugPrint(
      '[LocalNotifications] tap: id=${response.id}, payload=${response.payload}',
    );
    onTap?.call(response);
  }
}
