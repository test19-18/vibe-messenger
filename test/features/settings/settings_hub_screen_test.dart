import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_messenger/core/config/app_config.dart';
import 'package:vibe_messenger/core/providers/backend_providers.dart';
import 'package:vibe_messenger/core/theme/app_theme.dart';
import 'package:vibe_messenger/features/settings/presentation/settings_hub_screen.dart';

void main() {
  testWidgets('settings hub exposes privacy, appearance and device features', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendBootstrapProvider.overrideWithValue(
            const BackendBootstrap(
              status: BackendStatus.unconfigured,
              message: 'test backend',
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          locale: const Locale('en'),
          home: const SettingsHubScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Devices and sessions'),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Devices and sessions'), findsOneWidget);
    expect(find.text('App lock'), findsOneWidget);
  });
}
