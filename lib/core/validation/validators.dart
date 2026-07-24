abstract final class Validators {
  static final RegExp _emailPattern = RegExp(
    r'^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$',
    caseSensitive: false,
  );
  static final RegExp _usernamePattern = RegExp(r'^[a-z0-9_][a-z0-9_.]{2,31}$');

  static String? email(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return 'Введите email';
    }
    if (!_emailPattern.hasMatch(normalized)) {
      return 'Проверьте формат email';
    }
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return 'Введите пароль';
    }
    if (value.length < 8) {
      return 'Минимум 8 символов';
    }
    return null;
  }

  static String? username(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return null;
    }
    if (!_usernamePattern.hasMatch(normalized)) {
      return '3–32 символа: a–z, 0–9, _, .';
    }
    return null;
  }

  static String? displayName(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return 'Введите имя';
    }
    if (normalized.length > 48) {
      return 'Не больше 48 символов';
    }
    return null;
  }
}
