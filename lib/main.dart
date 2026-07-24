import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/providers/backend_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final backend = await AppConfig.initializeBackend();

  runApp(
    ProviderScope(
      overrides: [backendBootstrapProvider.overrideWithValue(backend)],
      child: const VibeApp(),
    ),
  );
}
