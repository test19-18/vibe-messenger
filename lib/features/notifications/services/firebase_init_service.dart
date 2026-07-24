/// Safe Firebase initialization service.
///
/// Firebase requires `google-services.json` on Android (gitignored, provided
/// as a build secret). If the config is missing or `Firebase.initializeApp`
/// fails for any reason, this service returns a [FirebaseInitResult.pending]
/// instead of crashing. The app continues to function without push — the
/// settings UI shows an honest "Firebase pending" state.
///
/// **Security:** This service never touches service-account credentials.
/// Those are only needed on the server (Supabase Edge Function secret
/// `FIREBASE_SERVICE_ACCOUNT_JSON`). The client uses only the public Firebase
/// app configuration embedded in `google-services.json`.
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Result of a Firebase initialization attempt.
@immutable
class FirebaseInitResult {
  const FirebaseInitResult({required this.status, this.message, this.app});

  const FirebaseInitResult._pending(this.message)
    : status = FirebaseInitStatus.pending,
      app = null;

  const FirebaseInitResult._ready(this.app)
    : status = FirebaseInitStatus.ready,
      message = null;

  const FirebaseInitResult._failed(this.message)
    : status = FirebaseInitStatus.failed,
      app = null;

  factory FirebaseInitResult.pending(String message) =>
      FirebaseInitResult._pending(message);

  factory FirebaseInitResult.ready(FirebaseApp app) =>
      FirebaseInitResult._ready(app);

  factory FirebaseInitResult.failed(String message) =>
      FirebaseInitResult._failed(message);

  final FirebaseInitStatus status;
  final String? message;
  final FirebaseApp? app;

  bool get isReady => status == FirebaseInitStatus.ready && app != null;
}

enum FirebaseInitStatus { ready, pending, failed }

/// Attempts to initialize Firebase safely.
///
/// On Android, `Firebase.initializeApp()` reads the merged
/// `google-services.json` via the `firebase_options.dart` generated file or
/// the default `FirebaseOptions` from the platform. If `google-services.json`
/// is absent, the Gradle plugin skips registration and `initializeApp` will
/// throw a `MissingPluginException` or a `FirebaseException` with
/// `[core/no-options]`. We catch both and return a pending result.
///
/// This method must be called after `WidgetsFlutterBinding.ensureInitialized()`
/// and before `runApp`.
Future<FirebaseInitResult> initializeFirebase() async {
  try {
    // Default initialization uses the platform-native configuration injected
    // by the `com.google.gms.google-services` Gradle plugin (Android) or the
    // equivalent on iOS. We intentionally do NOT pass `FirebaseOptions` from
    // Dart code — the native config is the source of truth and avoids
    // embedding API keys in source.
    final app = await Firebase.initializeApp();
    return FirebaseInitResult.ready(app);
  } catch (error) {
    final message = error.toString();
    // Common failures:
    // - '[core/no-options]' — google-services.json not found
    // - 'MissingPluginException' — Firebase plugins not registered
    // - '[core/already-initialized]' — safe to ignore, treat as ready
    if (message.contains('already-initialized') ||
        message.contains('already initialized')) {
      try {
        final app = Firebase.app();
        return FirebaseInitResult.ready(app);
      } catch (_) {
        // Fall through to pending.
      }
    }
    debugPrint('[Firebase] initialization deferred: $message');
    return FirebaseInitResult.pending(
      'Firebase ожидает настройки google-services.json. '
      'Push-уведомления временно недоступны.',
    );
  }
}
