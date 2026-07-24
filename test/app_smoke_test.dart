import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_messenger/app.dart';
import 'package:vibe_messenger/core/config/app_config.dart';
import 'package:vibe_messenger/core/providers/backend_providers.dart';

void main() {
  testWidgets('unconfigured app safely routes to the login screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendBootstrapProvider.overrideWithValue(
            const BackendBootstrap(
              status: BackendStatus.unconfigured,
              message: 'Backend не настроен для теста.',
            ),
          ),
        ],
        child: const VibeApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('С возвращением'), findsOneWidget);
    expect(find.text('Backend не настроен для теста.'), findsOneWidget);
  });
}
