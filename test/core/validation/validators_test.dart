import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_messenger/core/validation/validators.dart';

void main() {
  group('Validators.email', () {
    test('accepts a normalized valid email', () {
      expect(Validators.email('  hello+vibe@example.com  '), isNull);
      expect(Validators.email('USER@EXAMPLE.RU'), isNull);
    });

    test('rejects empty and malformed values', () {
      expect(Validators.email(''), 'Введите email');
      expect(Validators.email(null), 'Введите email');
      expect(Validators.email('not-an-email'), 'Проверьте формат email');
      expect(Validators.email('name@localhost'), 'Проверьте формат email');
    });
  });
}
