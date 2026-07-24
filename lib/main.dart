import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/providers/backend_providers.dart';
import 'features/notifications/providers/notifications_provider.dart';
import 'features/notifications/services/fcm_service.dart';
import 'features/notifications/services/firebase_init_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final backend = await AppConfig.initializeBackend();

  // Safely initialize Firebase. If google-services.json is absent or
  // initialization fails, this returns a pending result instead of crashing.
  // The app continues without push; the settings UI shows an honest state.
  final firebaseInit = await initializeFirebase();

  // Register the top-level background FCM handler. This MUST be done before
  // runApp and the handler MUST be a top-level function (no UI access).
  if (firebaseInit.isReady) {
    FirebaseMessaging.onBackgroundMessage(backgroundFcmHandler);
  }

  runApp(
    ProviderScope(
      overrides: [
        backendBootstrapProvider.overrideWithValue(backend),
        firebaseInitResultProvider.overrideWithValue(firebaseInit),
      ],
      child: const VibeApp(),
    ),
  );
}
