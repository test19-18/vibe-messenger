import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/backend_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/presence_repository.dart';

final presenceRepositoryProvider = Provider<PresenceRepository>((ref) {
  return PresenceRepository(ref.watch(supabaseClientProvider));
});

final presenceHeartbeatProvider = Provider<PresenceHeartbeat?>((ref) {
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null) {
    return null;
  }
  final heartbeat = PresenceHeartbeat(
    repository: ref.watch(presenceRepositoryProvider),
    userId: userId,
  )..start();
  ref.onDispose(heartbeat.dispose);
  return heartbeat;
});

class PresenceHeartbeat with WidgetsBindingObserver {
  PresenceHeartbeat({required this.repository, required this.userId});

  final PresenceRepository repository;
  final String userId;
  Timer? _timer;
  bool _disposed = false;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_send(true));
    _timer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_send(true)),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_send(true));
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(_send(false));
        return;
    }
  }

  Future<void> _send(bool online) async {
    if (_disposed) {
      return;
    }
    try {
      await repository.heartbeat(userId: userId, online: online);
    } catch (_) {
      // Presence is best effort and is retried by the next heartbeat.
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(repository.heartbeat(userId: userId, online: false));
  }
}
