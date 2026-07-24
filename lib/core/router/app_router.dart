import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/chat/presentation/enhanced_conversation_screen.dart';
import '../../features/chats/presentation/chats_hub_screen.dart';
import '../../features/contacts/presentation/contacts_hub_screen.dart';
import '../../features/groups/presentation/create_group_screen.dart';
import '../../features/groups/presentation/group_access_screen.dart';
import '../../features/groups/presentation/group_details_screen.dart';
import '../../features/navigation/presentation/app_shell.dart';
import '../../features/profile/presentation/profile_qr_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/settings/presentation/settings_detail_screens.dart';
import '../../features/settings/presentation/settings_hub_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../theme/app_colors.dart';
import 'route_locations.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  final refreshNotifier = RouterRefreshNotifier(
    authRepository.sessionChanges(),
  );

  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final isSignedIn = authRepository.currentSession != null;
      final path = state.uri.path;
      final isAuthPath = publicAuthPaths.contains(path);

      if (!isSignedIn && path == '/') {
        return '/login';
      }
      if (isSignedIn && path == '/') {
        return '/chats';
      }
      if (!isSignedIn && !isAuthPath) {
        return publicAuthLocation('/login', from: state.uri.toString());
      }
      if (isSignedIn && isAuthPath) {
        final from = validatedInternalRedirect(
          state.uri.queryParameters['from'],
        );
        if (from != null) {
          return from;
        }
        return '/chats';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            LoginScreen(from: state.uri.queryParameters['from']),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) =>
            RegisterScreen(from: state.uri.queryParameters['from']),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) =>
            ResetPasswordScreen(from: state.uri.queryParameters['from']),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/chats',
                builder: (context, state) => const ChatsHubScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/contacts',
                builder: (context, state) => const ContactsHubScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsHubScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/profile/qr',
        builder: (context, state) => const ProfileQrScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/groups/new',
        builder: (context, state) => const CreateGroupScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/group/:conversationId',
        builder: (context, state) => GroupDetailsScreen(
          conversationId: state.pathParameters['conversationId']!,
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/group-access',
        builder: (context, state) =>
            GroupAccessScreen(initialToken: state.uri.queryParameters['token']),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/settings/appearance',
        builder: (context, state) => const AppearanceSettingsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/settings/privacy',
        builder: (context, state) => const PrivacySettingsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/settings/notifications',
        builder: (context, state) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/settings/data',
        builder: (context, state) => const DataStorageSettingsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/settings/lock',
        builder: (context, state) => const AppLockSettingsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/settings/devices',
        builder: (context, state) => const DevicesScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        name: 'conversation',
        path: '/conversation/:conversationId',
        builder: (context, state) {
          return EnhancedConversationScreen(
            conversationId: state.pathParameters['conversationId']!,
            title: state.uri.queryParameters['title'],
            isGroup: state.uri.queryParameters['group'] == 'true',
          );
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Вайб')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            'Такой страницы нет.',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ),
    ),
  );

  ref.onDispose(() {
    router.dispose();
    refreshNotifier.dispose();
  });
  return router;
});

class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(Stream<Object?> stream) {
    _subscription = stream.listen(
      (_) => notifyListeners(),
      onError: (Object _, StackTrace _) => notifyListeners(),
    );
  }

  late final StreamSubscription<Object?> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
