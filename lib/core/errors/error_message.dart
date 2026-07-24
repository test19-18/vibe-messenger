import 'package:supabase_flutter/supabase_flutter.dart';

String errorMessage(Object error) {
  if (error is BackendUnavailableException) {
    return error.message;
  }
  if (error is AuthException) {
    final message = error.message.toLowerCase();
    if (error.code == 'invalid_credentials' ||
        message.contains('invalid login credentials')) {
      return 'Неверный email или пароль.';
    }
    if (error.code == 'email_not_confirmed' ||
        message.contains('email not confirmed')) {
      return 'Подтвердите email по ссылке из письма.';
    }
    if (error.code == 'user_already_exists' ||
        message.contains('user already registered')) {
      return 'Аккаунт с таким email уже существует.';
    }
    if (error.code == 'weak_password' ||
        message.contains('password should be')) {
      return 'Пароль слишком короткий.';
    }
    return error.message;
  }
  if (error is PostgrestException) {
    if (error.code == '42P01' || error.code == 'PGRST205') {
      return 'Таблица backend ещё не создана.';
    }
    if (error.code == '42501') {
      return 'Операция запрещена политикой доступа.';
    }
    return error.message;
  }
  if (error is FormatException) {
    final message = error.message;
    return message.isNotEmpty ? message : 'Проверьте введённые данные.';
  }
  if (error is RealtimeSubscribeException) {
    return 'Не удалось подключиться к обновлениям в реальном времени.';
  }
  return 'Что-то пошло не так. Попробуйте ещё раз.';
}

class BackendUnavailableException implements Exception {
  const BackendUnavailableException([
    this.message = 'Backend пока не настроен.',
  ]);

  final String message;

  @override
  String toString() => message;
}
