/// Notification channel identifiers for Android.
///
/// Two separate channels are required so the user can configure importance,
/// sound, and vibration independently for chat messages and incoming calls.
/// Incoming calls use maximum importance (heads-up / full-screen) while
/// messages use high importance (heads-up).
library;

/// Channel for chat message notifications.
const kMessageChannelId = 'vibe_messages';
const kMessageChannelName = 'Сообщения';
const kMessageChannelDescription = 'Уведомления о новых сообщениях';

/// Channel for incoming call notifications (high-priority, full-screen).
const kCallChannelId = 'vibe_incoming_calls';
const kCallChannelName = 'Входящие звонки';
const kCallChannelDescription = 'Уведомления о входящих звонках';

/// Notification IDs (each notification must have a unique int id).
const kMessageNotificationIdOffset = 1000;
const kCallNotificationId = 2001;

/// Method channel for the Dart-side background handler to request navigation
/// when the app is launched/resumed by a notification tap. The main activity
/// picks this up and the router provider reacts to it.
const kNotificationNavigationChannel = 'vibe/notification_navigation';
