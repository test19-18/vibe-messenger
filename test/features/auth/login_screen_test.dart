import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibe_messenger/core/config/app_config.dart';
import 'package:vibe_messenger/core/providers/backend_providers.dart';
import 'package:vibe_messenger/core/theme/app_theme.dart';
import 'package:vibe_messenger/features/auth/presentation/login_screen.dart';

void main() {
  late SupabaseClient client;

  setUp(() {
    client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
    );
  });

  tearDown(() => client.dispose());

  Widget buildSubject() {
    return ProviderScope(
      overrides: [
        backendBootstrapProvider.overrideWithValue(
          BackendBootstrap(
            status: BackendStatus.ready,
            message: 'test backend',
            client: client,
          ),
        ),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const LoginScreen()),
    );
  }

  testWidgets('shows branded login form', (tester) async {
    await tester.pumpWidget(buildSubject());

    expect(find.text('С возвращением'), findsOneWidget);
    expect(find.byKey(const Key('login_email_field')), findsOneWidget);
    expect(find.byKey(const Key('login_password_field')), findsOneWidget);
    expect(find.byKey(const Key('login_submit_button')), findsOneWidget);
    expect(find.text('Создать аккаунт'), findsOneWidget);
  });

  testWidgets('validates email and password before repository call', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());

    await tester.enterText(
      find.byKey(const Key('login_email_field')),
      'wrong-address',
    );
    await tester.enterText(
      find.byKey(const Key('login_password_field')),
      '123',
    );
    await tester.tap(find.byKey(const Key('login_submit_button')));
    await tester.pump();

    expect(find.text('Проверьте формат email'), findsOneWidget);
    expect(find.text('Минимум 8 символов'), findsOneWidget);
  });
}
