import 'package:flutter/services.dart';

enum ScreenProtectionMode { disabled, native, bestEffort }

abstract interface class ScreenProtectionApi {
  Future<bool> setProtected(bool enabled);
}

class MethodChannelScreenProtectionApi implements ScreenProtectionApi {
  const MethodChannelScreenProtectionApi({
    this._channel = const MethodChannel('vibe/screen_protection'),
  });

  final MethodChannel _channel;

  @override
  Future<bool> setProtected(bool enabled) async {
    final result = await _channel.invokeMethod<bool>('setProtectedContent', {
      'enabled': enabled,
    });
    return result ?? false;
  }
}

class ScreenProtectionService {
  ScreenProtectionService(this._api);

  final ScreenProtectionApi _api;
  final Set<Object> _owners = {};

  Future<ScreenProtectionMode> setProtectedFor(
    Object owner, {
    required bool enabled,
  }) async {
    if (enabled) {
      _owners.add(owner);
    } else {
      _owners.remove(owner);
    }
    return _apply(_owners.isNotEmpty);
  }

  Future<ScreenProtectionMode> _apply(bool enabled) async {
    if (!enabled) {
      try {
        await _api.setProtected(false);
      } on MissingPluginException {
        // The Flutter layer still removes its lifecycle privacy cover.
      } on PlatformException {
        // Native teardown is best effort when host wiring is unavailable.
      }
      return ScreenProtectionMode.disabled;
    }
    try {
      final applied = await _api.setProtected(true);
      return applied
          ? ScreenProtectionMode.native
          : ScreenProtectionMode.bestEffort;
    } on MissingPluginException {
      return ScreenProtectionMode.bestEffort;
    } on PlatformException {
      return ScreenProtectionMode.bestEffort;
    }
  }
}
