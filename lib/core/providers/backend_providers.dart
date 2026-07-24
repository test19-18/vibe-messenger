import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

final backendBootstrapProvider = Provider<BackendBootstrap>((ref) {
  throw UnimplementedError(
    'backendBootstrapProvider must be overridden in main or tests',
  );
});

final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  return ref.watch(backendBootstrapProvider).client;
});
