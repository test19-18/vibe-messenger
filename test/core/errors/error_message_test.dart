import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibe_messenger/core/errors/error_message.dart';

void main() {
  test('maps current Supabase auth error codes', () {
    expect(
      errorMessage(
        const AuthException(
          'Credentials rejected',
          code: 'invalid_credentials',
        ),
      ),
      'Неверный email или пароль.',
    );
  });

  test('maps a missing PostgREST table from the schema cache', () {
    expect(
      errorMessage(
        const PostgrestException(
          message: 'Could not find the table',
          code: 'PGRST205',
        ),
      ),
      'Таблица backend ещё не создана.',
    );
  });
}
