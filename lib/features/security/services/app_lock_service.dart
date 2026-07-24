import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLockConfiguration {
  const AppLockConfiguration({
    required this.pinEnabled,
    required this.biometricEnabled,
  });

  final bool pinEnabled;
  final bool biometricEnabled;

  bool get enabled => pinEnabled || biometricEnabled;
}

class AppLockService {
  AppLockService({LocalAuthentication? localAuthentication})
    : _localAuthentication = localAuthentication ?? LocalAuthentication();

  static const _pinHashKey = 'vibe.lock.pin_hash.v1';
  static const _pinSaltKey = 'vibe.lock.pin_salt.v1';
  static const _biometricKey = 'vibe.lock.biometric.v1';

  final LocalAuthentication _localAuthentication;

  Future<AppLockConfiguration> loadConfiguration() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return AppLockConfiguration(
        pinEnabled: preferences.getString(_pinHashKey)?.isNotEmpty == true,
        biometricEnabled: preferences.getBool(_biometricKey) ?? false,
      );
    } catch (_) {
      return const AppLockConfiguration(
        pinEnabled: false,
        biometricEnabled: false,
      );
    }
  }

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      throw const FormatException('PIN должен содержать 4–8 цифр.');
    }
    final random = Random.secure();
    final salt = base64UrlEncode(
      List<int>.generate(18, (_) => random.nextInt(256)),
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_pinSaltKey, salt);
    await preferences.setString(_pinHashKey, _hash(pin, salt));
  }

  Future<bool> verifyPin(String pin) async {
    final preferences = await SharedPreferences.getInstance();
    final salt = preferences.getString(_pinSaltKey);
    final expected = preferences.getString(_pinHashKey);
    if (salt == null || expected == null) {
      return false;
    }
    return _constantTimeEquals(_hash(pin, salt), expected);
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    if (enabled) {
      final configuration = await loadConfiguration();
      if (!configuration.pinEnabled) {
        throw const FormatException('Сначала установите резервный PIN.');
      }
      final supported = await _localAuthentication.isDeviceSupported();
      if (!supported) {
        throw const FormatException('Биометрия недоступна на этом устройстве.');
      }
      final authenticated = await authenticateBiometric();
      if (!authenticated) {
        throw const FormatException('Биометрия не подтверждена.');
      }
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_biometricKey, enabled);
  }

  Future<bool> authenticateBiometric() async {
    try {
      return await _localAuthentication.authenticate(
        localizedReason: 'Подтвердите вход в Вайб',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> disable() async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove(_pinHashKey),
      preferences.remove(_pinSaltKey),
      preferences.setBool(_biometricKey, false),
    ]);
  }

  String _hash(String pin, String salt) {
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }
}
