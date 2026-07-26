import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_tokens.dart';
import '../../chats/providers/conversation_providers.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _goToBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final conversations = ref.watch(conversationsProvider).valueOrNull;
    final unread =
        conversations
            ?.where((conversation) => !conversation.isArchived)
            .fold<int>(
              0,
              (total, conversation) => total + conversation.unreadCount,
            ) ??
        0;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.navBar,
          border: Border(top: BorderSide(color: tokens.divider, width: 0.5)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                _Destination(
                  label: context.tr(ru: 'Чаты', en: 'Chats'),
                  icon: Icons.chat_bubble_outline_rounded,
                  activeIcon: Icons.chat_bubble_rounded,
                  badgeCount: unread,
                  selected: navigationShell.currentIndex == 0,
                  onTap: () => _goToBranch(0),
                ),
                _Destination(
                  label: context.tr(ru: 'Контакты', en: 'Contacts'),
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  selected: navigationShell.currentIndex == 1,
                  onTap: () => _goToBranch(1),
                ),
                _Destination(
                  label: context.tr(ru: 'Настройки', en: 'Settings'),
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings_rounded,
                  selected: navigationShell.currentIndex == 2,
                  onTap: () => _goToBranch(2),
                ),
                _Destination(
                  label: context.tr(ru: 'Профиль', en: 'Profile'),
                  icon: Icons.account_circle_outlined,
                  activeIcon: Icons.account_circle_rounded,
                  selected: navigationShell.currentIndex == 3,
                  onTap: () => _goToBranch(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Destination extends StatelessWidget {
  const _Destination({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = selected ? tokens.accent : tokens.textSecondary;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: badgeCount > 0
            ? '$label, ${context.tr(ru: 'непрочитанных', en: 'unread')}: $badgeCount'
            : label,
        child: InkResponse(
          onTap: onTap,
          radius: 42,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(selected ? activeIcon : icon, size: 26, color: color),
                  if (badgeCount > 0)
                    Positioned(
                      top: -5,
                      left: 14,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 17),
                        height: 17,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tokens.badge,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          border: Border.all(color: tokens.navBar, width: 1.5),
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            color: tokens.onBadge,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
