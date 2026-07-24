import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibe_messenger/features/security/services/app_lock_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'stores a PIN verifier and validates without plaintext persistence',
    () async {
      final service = AppLockService();

      await service.setPin('2468');

      expect(await service.verifyPin('2468'), isTrue);
      expect(await service.verifyPin('1111'), isFalse);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getKeys(), isNotEmpty);
      expect(
        preferences.getKeys().any((key) => preferences.get(key) == '2468'),
        isFalse,
      );
    },
  );
}
