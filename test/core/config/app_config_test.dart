import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_messenger/core/config/app_config.dart';

void main() {
  test('uses a unique Android callback URI for Supabase email flows', () {
    expect(AppConfig.authCallbackUrl, 'ru.vibe.messenger://auth/callback');
    expect(Uri.parse(AppConfig.authCallbackUrl).scheme, 'ru.vibe.messenger');
    expect(Uri.parse(AppConfig.authCallbackUrl).host, 'auth');
  });
}
