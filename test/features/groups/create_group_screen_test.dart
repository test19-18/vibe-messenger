import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_messenger/core/config/app_config.dart';
import 'package:vibe_messenger/core/providers/backend_providers.dart';
import 'package:vibe_messenger/core/theme/app_theme.dart';
import 'package:vibe_messenger/features/groups/presentation/create_group_screen.dart';

void main() {
  testWidgets('group creation validates an empty title locally', (
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
          home: const CreateGroupScreen(),
        ),
      ),
    );

    await tester.tap(find.text('Create group'));
    await tester.pump();

    expect(find.text('Enter a name'), findsOneWidget);
  });
}
