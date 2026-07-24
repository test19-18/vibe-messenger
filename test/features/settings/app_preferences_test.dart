import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_messenger/features/settings/domain/app_preferences.dart';

void main() {
  test('maps backend columns and local JSON settings', () {
    final preferences = AppPreferences.fromMap({
      'locale': 'en',
      'theme': 'light',
      'send_read_receipts': false,
      'show_typing_status': false,
      'show_last_seen': false,
      'push_enabled': false,
      'push_message_preview': false,
      'auto_download_media': false,
      'settings': {
        'text_scale': 1.25,
        'animations_enabled': false,
        'power_saving': true,
        'cache_media': false,
      },
    });

    expect(preferences.locale, 'en');
    expect(preferences.theme, AppThemePreference.light);
    expect(preferences.textScale, 1.25);
    expect(preferences.reduceMotion, isTrue);
    expect(preferences.autoDownloadMedia, isFalse);
    expect(preferences.cacheMedia, isFalse);
    expect(preferences.toBackendMap()['settings'], isA<Map<String, dynamic>>());
  });

  test('defensively clamps text scale and locale', () {
    final preferences = AppPreferences.fromMap({
      'locale': 'de',
      'settings': {'text_scale': 4},
    });

    expect(preferences.locale, 'ru');
    expect(preferences.textScale, 1.35);
  });
}
