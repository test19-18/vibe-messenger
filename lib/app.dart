import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/calls/presentation/incoming_call_overlay.dart';
import 'features/security/presentation/app_lock_gate.dart';
import 'features/settings/domain/app_preferences.dart';
import 'features/settings/providers/presence_providers.dart';
import 'features/settings/providers/settings_providers.dart';

class VibeApp extends ConsumerWidget {
  const VibeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final preferences =
        ref.watch(appPreferencesProvider).valueOrNull ?? const AppPreferences();
    ref.watch(presenceHeartbeatProvider);

    return MaterialApp.router(
      title: 'Вайб',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: switch (preferences.theme) {
        AppThemePreference.system => ThemeMode.system,
        AppThemePreference.light => ThemeMode.light,
        AppThemePreference.dark => ThemeMode.dark,
      },
      locale: Locale(preferences.locale),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(preferences.textScale));
        return MediaQuery(
          data: mediaQuery,
          child: TickerMode(
            enabled: !preferences.reduceMotion,
            child: IncomingCallOverlay(
              child: AppLockGate(child: child ?? const SizedBox.shrink()),
            ),
          ),
        );
      },
      routerConfig: router,
    );
  }
}
