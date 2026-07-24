/// Notifications provider — coordinates Firebase init, FCM token lifecycle,
/// foreground message handling, and navigation/call event dispatch.
///
/// This is the single entry point for the notifications feature. It wires
/// together [FcmService], [LocalNotificationsService], and
/// [NotificationsRepository], and exposes events to the existing router and
/// call providers via a [PushEventController].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/providers/backend_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../settings/providers/settings_providers.dart';
import '../data/notifications_repository.dart';
import '../domain/fcm_payload.dart';
import '../domain/notification_channels.dart';
import '../services/fcm_service.dart';
import '../services/firebase_init_service.dart';
import '../services/local_notifications_service.dart';

// Re-export the settings preferences provider so consumers of the
// notifications provider don't need a separate import.
export '../../settings/providers/settings_providers.dart'
    show appPreferencesProvider;

// ---------------------------------------------------------------------------
// Infrastructure providers
// ---------------------------------------------------------------------------

/// Firebase initialization result — overridden in main().
final firebaseInitResultProvider = Provider<FirebaseInitResult>((ref) {
  // Default: pending. main() overrides with the actual result.
  return FirebaseInitResult.pending('Firebase не инициализирован.');
});

/// Whether Firebase is ready for FCM operations.
final firebaseReadyProvider = Provider<bool>((ref) {
  return ref.watch(firebaseInitResultProvider).isReady;
});

final fcmServiceProvider = Provider<FcmService>((ref) {
  final service = FcmService();
  ref.onDispose(service.dispose);
  return service;
});

final localNotificationsServiceProvider = Provider<LocalNotificationsService>((
  ref,
) {
  return LocalNotificationsService();
});

final notificationsRepositoryProvider = Provider<NotificationsRepository>((
  ref,
) {
  return NotificationsRepository(ref.watch(supabaseClientProvider));
});

// ---------------------------------------------------------------------------
// Push event bus — exposes navigation/call events to the router and call
// providers. The router provider and call providers listen to this stream
// to react to notification taps and incoming-call pushes.
// ---------------------------------------------------------------------------

/// Types of events the push system can emit to the rest of the app.
enum PushEventType {
  /// User tapped a message notification — navigate to the conversation.
  openConversation,

  /// User tapped an incoming-call notification — show the call UI.
  openCall,

  /// An incoming_call FCM payload arrived in the foreground — ring the call.
  incomingCall,

  /// A call_cancelled FCM payload arrived — dismiss the incoming call UI.
  callCancelled,
}

/// A push event carrying the relevant payload for the router/call providers.
class PushEvent {
  const PushEvent({
    required this.type,
    this.conversationId,
    this.callId,
    this.roomName,
    this.callerId,
    this.callerName,
    this.isVideo,
  });

  final PushEventType type;
  final String? conversationId;
  final String? callId;
  final String? roomName;
  final String? callerId;
  final String? callerName;
  final bool? isVideo;

  factory PushEvent.fromMessagePayload(MessagePayload payload) {
    return PushEvent(
      type: PushEventType.openConversation,
      conversationId: payload.conversationId,
    );
  }

  factory PushEvent.fromIncomingCallPayload(IncomingCallPayload payload) {
    return PushEvent(
      type: PushEventType.incomingCall,
      callId: payload.callId,
      roomName: payload.roomName,
      callerId: payload.callerId,
      callerName: payload.callerName,
      isVideo: payload.isVideo,
      conversationId: payload.conversationId.isNotEmpty
          ? payload.conversationId
          : null,
    );
  }

  factory PushEvent.fromCallCancelledPayload(CallCancelledPayload payload) {
    return PushEvent(type: PushEventType.callCancelled, callId: payload.callId);
  }
}

/// A simple broadcast controller for push events.
///
/// The router provider and call providers watch [pushEventsProvider] and
/// react to events. This avoids tight coupling between the notifications
/// feature and the router/call feature — they communicate only through
/// this event bus.
class PushEventController {
  PushEventController();

  final StreamController<PushEvent> _controller =
      StreamController<PushEvent>.broadcast();

  Stream<PushEvent> get events => _controller.stream;

  void emit(PushEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  void dispose() {
    _controller.close();
  }
}

final pushEventControllerProvider = Provider<PushEventController>((ref) {
  final controller = PushEventController();
  ref.onDispose(controller.dispose);
  return controller;
});

/// Stream of push events for the router/call providers to listen to.
final pushEventsProvider = StreamProvider<PushEvent>((ref) {
  return ref.watch(pushEventControllerProvider).events;
});

// ---------------------------------------------------------------------------
// Notifications controller — the main coordinator
// ---------------------------------------------------------------------------

/// State of the notifications subsystem.
@immutable
class NotificationsState {
  const NotificationsState({
    this.firebaseReady = false,
    this.fcmToken,
    this.notificationPermissionGranted = false,
    this.deviceRegistered = false,
    this.lastError,
  });

  final bool firebaseReady;
  final String? fcmToken;
  final bool notificationPermissionGranted;
  final bool deviceRegistered;
  final String? lastError;

  /// Honest status for the settings UI.
  String get statusLabel {
    if (!firebaseReady) {
      return 'Firebase ожидает настройки (google-services.json). '
          'Push-уведомления временно недоступны.';
    }
    if (!notificationPermissionGranted) {
      return 'Разрешение на уведомления не предоставлено.';
    }
    if (fcmToken == null) {
      return 'FCM token не получен.';
    }
    if (!deviceRegistered) {
      return 'Устройство не зарегистрировано для push.';
    }
    return 'Push-уведомления активны.';
  }

  /// Whether push is fully operational.
  bool get isFullyOperational =>
      firebaseReady &&
      notificationPermissionGranted &&
      fcmToken != null &&
      deviceRegistered;

  NotificationsState copyWith({
    bool? firebaseReady,
    String? fcmToken,
    bool? notificationPermissionGranted,
    bool? deviceRegistered,
    String? lastError,
  }) {
    return NotificationsState(
      firebaseReady: firebaseReady ?? this.firebaseReady,
      fcmToken: fcmToken ?? this.fcmToken,
      notificationPermissionGranted:
          notificationPermissionGranted ?? this.notificationPermissionGranted,
      deviceRegistered: deviceRegistered ?? this.deviceRegistered,
      lastError: lastError,
    );
  }
}

/// The main notifications coordinator.
///
/// Lifecycle:
/// 1. [initialize] — called from app startup after Firebase init.
///    Creates local notification channels, requests permission if push is
///    enabled, registers the FCM token.
/// 2. [onLogin] — called when the user signs in. Registers the device token.
/// 3. [onLogout] — called when the user signs out. Deletes the device token.
/// 4. Foreground messages are handled automatically via the FCM service
///    listener, which shows local notifications and emits push events.
class NotificationsController extends StateNotifier<NotificationsState> {
  NotificationsController({
    required this.fcmService,
    required this.localNotifications,
    required this.repository,
    required this.firebaseReady,
    required this.pushEvents,
  }) : super(NotificationsState(firebaseReady: firebaseReady));

  final FcmService fcmService;
  final LocalNotificationsService localNotifications;
  final NotificationsRepository repository;
  final bool firebaseReady;
  final PushEventController pushEvents;

  StreamSubscription<FcmPayload>? _foregroundSub;
  StreamSubscription<String>? _tokenRefreshSub;

  /// Initializes the notifications subsystem.
  ///
  /// [pushEnabled] — whether the user has push enabled in preferences.
  /// [userId] — the current user's ID (for token registration).
  Future<void> initialize({required bool pushEnabled, String? userId}) async {
    if (!firebaseReady) {
      state = state.copyWith(
        firebaseReady: false,
        lastError: 'Firebase не настроен.',
      );
      return;
    }

    state = state.copyWith(firebaseReady: true);

    // 1. Initialize local notifications (creates Android channels).
    final localReady = await localNotifications.initialize();

    // 2. Start foreground FCM listener.
    fcmService.startForegroundListener();

    // 3. Listen for foreground payloads.
    _foregroundSub = fcmService.foregroundPayloads.listen(_onForegroundPayload);

    // 4. Listen for token refresh.
    _tokenRefreshSub = fcmService.tokenRefreshStream.listen((newToken) {
      _onTokenRefresh(newToken, userId);
    });

    // 5. Handle notification taps (cold start + foreground).
    fcmService.setupOnMessageOpenedApp(
      onPayload: (payload) => _onNotificationTapPayload(payload),
    );

    // Check for initial message (cold start from notification).
    final initialPayload = await fcmService.getInitialMessage();
    if (initialPayload != null) {
      _onNotificationTapPayload(initialPayload);
    }

    if (!pushEnabled || userId == null) {
      return;
    }

    // 6. Request notification permission.
    if (localReady) {
      final granted = await localNotifications.requestNotificationPermission();
      state = state.copyWith(notificationPermissionGranted: granted);
    }

    // 7. Acquire and register the FCM token.
    await _acquireAndRegisterToken(userId: userId);
  }

  /// Called when the user signs in (or app starts with an existing session).
  Future<void> onLogin({
    required String userId,
    required bool pushEnabled,
  }) async {
    if (!firebaseReady || !pushEnabled) {
      return;
    }

    // Ensure permission is requested.
    final granted = await localNotifications.requestNotificationPermission();
    state = state.copyWith(notificationPermissionGranted: granted);

    if (granted) {
      await _acquireAndRegisterToken(userId: userId);
    }
  }

  /// Called when the user signs out — deletes the FCM token from the server.
  Future<void> onLogout() async {
    final token = state.fcmToken ?? fcmService.cachedToken;
    if (token != null) {
      try {
        await repository.deleteCallDeviceByToken(token);
      } catch (error) {
        debugPrint('[Notifications] onLogout delete failed: $error');
      }
      await fcmService.deleteToken();
    }
    state = state.copyWith(fcmToken: null, deviceRegistered: false);
  }

  /// Called when the user toggles push in settings.
  Future<void> setPushEnabled({
    required bool enabled,
    required String? userId,
  }) async {
    if (!enabled) {
      await onLogout();
      return;
    }
    if (userId != null) {
      await onLogin(userId: userId, pushEnabled: true);
    }
  }

  /// Requests the POST_NOTIFICATIONS permission (Android 13+).
  Future<bool> requestNotificationPermission() async {
    if (!firebaseReady) {
      return false;
    }
    // Use permission_handler for the system-level permission, then
    // local_notifications for the plugin-level permission.
    final systemStatus = await Permission.notification.request();
    final systemGranted = systemStatus.isGranted;
    if (systemGranted) {
      await localNotifications.requestNotificationPermission();
    }
    state = state.copyWith(notificationPermissionGranted: systemGranted);
    return systemGranted;
  }

  // -- Internal --

  Future<void> _acquireAndRegisterToken({required String userId}) async {
    final tokenResult = await fcmService.getToken();
    if (!tokenResult.hasToken) {
      state = state.copyWith(fcmToken: null, lastError: tokenResult.message);
      return;
    }

    state = state.copyWith(fcmToken: tokenResult.token);

    try {
      await repository.registerCallDevice(
        fcmToken: tokenResult.token!,
        deviceName: _deviceName(),
      );
      state = state.copyWith(deviceRegistered: true, lastError: null);
    } catch (error) {
      debugPrint('[Notifications] registerCallDevice failed: $error');
      state = state.copyWith(
        deviceRegistered: false,
        lastError: 'Не удалось зарегистрировать устройство: $error',
      );
    }
  }

  void _onTokenRefresh(String newToken, String? userId) {
    state = state.copyWith(fcmToken: newToken);
    if (userId != null) {
      // Re-register with the new token.
      repository
          .registerCallDevice(fcmToken: newToken, deviceName: _deviceName())
          .then((_) {
            if (mounted) {
              state = state.copyWith(deviceRegistered: true);
            }
          })
          .catchError((error) {
            debugPrint('[Notifications] token refresh register failed: $error');
          });
    }
  }

  void _onForegroundPayload(FcmPayload payload) {
    switch (payload) {
      case MessagePayload(
        :final conversationId,
        :final senderName,
        :final bodyPreview,
      ):
        // Show a local notification for the message.
        final id = _notificationIdForConversation(conversationId);
        localNotifications.showMessageNotification(
          notificationId: id,
          title: senderName.isNotEmpty ? senderName : 'Новое сообщение',
          body: bodyPreview.isNotEmpty ? bodyPreview : '',
        );
      case IncomingCallPayload():
        // Show a high-priority call notification.
        localNotifications.showIncomingCallNotification(
          notificationId: kCallNotificationId,
          callerName: payload.callerName.isNotEmpty
              ? payload.callerName
              : 'Неизвестный',
          isVideo: payload.isVideo,
        );
        // Emit the incoming-call event so the call providers can ring.
        pushEvents.emit(PushEvent.fromIncomingCallPayload(payload));
      case CallCancelledPayload():
        // Cancel the call notification.
        localNotifications.cancel(kCallNotificationId);
        // Emit the cancel event so the call providers can dismiss the UI.
        pushEvents.emit(PushEvent.fromCallCancelledPayload(payload));
    }
  }

  void _onNotificationTapPayload(FcmPayload? payload) {
    if (payload == null) {
      return;
    }
    switch (payload) {
      case MessagePayload():
        pushEvents.emit(PushEvent.fromMessagePayload(payload));
      case IncomingCallPayload():
        pushEvents.emit(
          PushEvent(
            type: PushEventType.openCall,
            callId: payload.callId,
            roomName: payload.roomName,
            callerId: payload.callerId,
            callerName: payload.callerName,
            isVideo: payload.isVideo,
            conversationId: payload.conversationId.isNotEmpty
                ? payload.conversationId
                : null,
          ),
        );
      case CallCancelledPayload():
        pushEvents.emit(PushEvent.fromCallCancelledPayload(payload));
    }
  }

  int _notificationIdForConversation(String conversationId) {
    // Derive a stable int from the conversation ID hash.
    return conversationId.hashCode.abs() % 100000 +
        kMessageNotificationIdOffset;
  }

  String _deviceName() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'Android';
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'iOS';
    }
    return 'Unknown';
  }

  @override
  void dispose() {
    _foregroundSub?.cancel();
    _tokenRefreshSub?.cancel();
    super.dispose();
  }
}

/// Provider for the notifications controller.
///
/// Initializes automatically when the user is signed in and Firebase is ready.
final notificationsProvider =
    StateNotifierProvider<NotificationsController, NotificationsState>((ref) {
      final firebaseReady = ref.watch(firebaseReadyProvider);
      final fcmService = ref.watch(fcmServiceProvider);
      final localNotifications = ref.watch(localNotificationsServiceProvider);
      final repository = ref.watch(notificationsRepositoryProvider);
      final pushEvents = ref.watch(pushEventControllerProvider);
      final userId = ref.watch(currentUserProvider)?.id;
      final pushEnabled = ref.watch(appPreferencesPushEnabledProvider);

      final controller = NotificationsController(
        fcmService: fcmService,
        localNotifications: localNotifications,
        repository: repository,
        firebaseReady: firebaseReady,
        pushEvents: pushEvents,
      );

      // Auto-initialize when Firebase is ready and user is signed in.
      if (firebaseReady && userId != null) {
        controller.initialize(pushEnabled: pushEnabled, userId: userId);
      } else if (firebaseReady) {
        // Firebase ready but no user — still set up listeners.
        controller.initialize(pushEnabled: false, userId: null);
      }

      return controller;
    });

/// Reads just the pushEnabled flag from app preferences (avoids circular
/// dependency on the full preferences controller).
final appPreferencesPushEnabledProvider = Provider<bool>((ref) {
  // Watch the preferences and extract pushEnabled.
  final prefs = ref.watch(appPreferencesProvider);
  return prefs.valueOrNull?.pushEnabled ?? true;
});
