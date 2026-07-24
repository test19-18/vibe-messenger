import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/backend_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/settings_repository.dart';
import '../domain/app_preferences.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(supabaseClientProvider));
});

final appPreferencesProvider =
    StateNotifierProvider<AppPreferencesController, AsyncValue<AppPreferences>>(
      (ref) {
        final controller = AppPreferencesController(
          repository: ref.watch(settingsRepositoryProvider),
          userId: ref.watch(currentUserProvider)?.id,
        );
        controller.load();
        return controller;
      },
    );

class AppPreferencesController
    extends StateNotifier<AsyncValue<AppPreferences>> {
  AppPreferencesController({required this.repository, required this.userId})
    : super(const AsyncData(AppPreferences()));

  final SettingsRepository repository;
  final String? userId;

  Future<void> load() async {
    final result = await AsyncValue.guard(() => repository.load(userId));
    if (mounted) {
      state = result;
    }
  }

  Future<bool> save(AppPreferences preferences) async {
    state = AsyncData(preferences);
    try {
      await repository.save(preferences, userId);
      return true;
    } catch (error, stackTrace) {
      if (mounted) {
        state = AsyncError(error, stackTrace);
      }
      return false;
    }
  }
}
