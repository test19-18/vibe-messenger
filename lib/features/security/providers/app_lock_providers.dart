import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_lock_service.dart';

class AppLockState {
  const AppLockState({required this.configuration, required this.locked});

  const AppLockState.disabled()
    : configuration = const AppLockConfiguration(
        pinEnabled: false,
        biometricEnabled: false,
      ),
      locked = false;

  final AppLockConfiguration configuration;
  final bool locked;
}

final appLockServiceProvider = Provider<AppLockService>((ref) {
  return AppLockService();
});

final appLockProvider =
    StateNotifierProvider<AppLockController, AsyncValue<AppLockState>>((ref) {
      final controller = AppLockController(ref.watch(appLockServiceProvider));
      controller.load();
      return controller;
    });

class AppLockController extends StateNotifier<AsyncValue<AppLockState>> {
  AppLockController(this._service)
    : super(const AsyncData(AppLockState.disabled()));

  final AppLockService _service;

  Future<void> load() async {
    final result = await AsyncValue.guard(() async {
      final configuration = await _service.loadConfiguration();
      return AppLockState(
        configuration: configuration,
        locked: configuration.enabled,
      );
    });
    if (mounted) {
      state = result;
    }
  }

  void lock() {
    final current = state.valueOrNull;
    if (current != null && current.configuration.enabled && !current.locked) {
      state = AsyncData(
        AppLockState(configuration: current.configuration, locked: true),
      );
    }
  }

  Future<bool> unlockWithPin(String pin) async {
    final verified = await _service.verifyPin(pin);
    if (verified && mounted) {
      final current = state.valueOrNull ?? const AppLockState.disabled();
      state = AsyncData(
        AppLockState(configuration: current.configuration, locked: false),
      );
    }
    return verified;
  }

  Future<bool> unlockWithBiometric() async {
    final authenticated = await _service.authenticateBiometric();
    if (authenticated && mounted) {
      final current = state.valueOrNull ?? const AppLockState.disabled();
      state = AsyncData(
        AppLockState(configuration: current.configuration, locked: false),
      );
    }
    return authenticated;
  }

  Future<void> setPin(String pin) async {
    await _service.setPin(pin);
    final configuration = await _service.loadConfiguration();
    if (mounted) {
      state = AsyncData(
        AppLockState(configuration: configuration, locked: false),
      );
    }
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _service.setBiometricEnabled(enabled);
    final configuration = await _service.loadConfiguration();
    if (mounted) {
      state = AsyncData(
        AppLockState(configuration: configuration, locked: false),
      );
    }
  }

  Future<void> disable() async {
    await _service.disable();
    if (mounted) {
      state = const AsyncData(AppLockState.disabled());
    }
  }
}
