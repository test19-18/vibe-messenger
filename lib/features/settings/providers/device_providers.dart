import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_message.dart';
import '../../../core/providers/backend_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/device_repository.dart';
import '../domain/user_device.dart';

final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  return DeviceRepository(ref.watch(supabaseClientProvider));
});

final devicesProvider = FutureProvider.autoDispose<List<UserDevice>>((
  ref,
) async {
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null) {
    throw const BackendUnavailableException('Сессия не найдена.');
  }
  return ref.watch(deviceRepositoryProvider).listDevices(userId);
});

final deviceMutationProvider =
    StateNotifierProvider.autoDispose<
      DeviceMutationController,
      AsyncValue<void>
    >(
      (ref) => DeviceMutationController(
        ref.watch(deviceRepositoryProvider),
        onChanged: () => ref.invalidate(devicesProvider),
      ),
    );

class DeviceMutationController extends StateNotifier<AsyncValue<void>> {
  DeviceMutationController(this.repository, {required this.onChanged})
    : super(const AsyncData(null));

  final DeviceRepository repository;
  final void Function() onChanged;

  Future<bool> disable(String id) => _run(() => repository.disableDevice(id));

  Future<bool> remove(String id) => _run(() => repository.removeDevice(id));

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(action);
    if (!mounted) {
      return false;
    }
    state = result;
    if (!result.hasError) {
      onChanged();
    }
    return !result.hasError;
  }
}
