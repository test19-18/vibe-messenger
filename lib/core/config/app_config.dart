import 'package:supabase_flutter/supabase_flutter.dart';

enum BackendStatus { ready, unconfigured, failed }

class BackendBootstrap {
  const BackendBootstrap({
    required this.status,
    required this.message,
    this.client,
  }) : assert(
         status != BackendStatus.ready || client != null,
         'A ready backend must expose a SupabaseClient.',
       );

  final BackendStatus status;
  final String message;
  final SupabaseClient? client;

  bool get isReady => status == BackendStatus.ready && client != null;
}

abstract final class AppConfig {
  // Both values are public client configuration. Authorization is enforced by
  // Supabase RLS; privileged service-role credentials must never be embedded.
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://rcioqqtpslawjstrbqyh.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_65s8V94B0rQB_C6FQyZT_Q_13QAltS4',
  );

  static bool get isSupabaseConfigured =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  static Future<BackendBootstrap> initializeBackend() async {
    if (!isSupabaseConfigured) {
      return const BackendBootstrap(
        status: BackendStatus.unconfigured,
        message:
            'Backend не настроен. Добавьте SUPABASE_URL и '
            'SUPABASE_ANON_KEY через --dart-define.',
      );
    }

    try {
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabaseAnonKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );
      return BackendBootstrap(
        status: BackendStatus.ready,
        message: 'Supabase подключён',
        client: Supabase.instance.client,
      );
    } catch (error) {
      return BackendBootstrap(
        status: BackendStatus.failed,
        message: 'Не удалось инициализировать backend: $error',
      );
    }
  }
}
