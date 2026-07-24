import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _goToBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Container(
          height: 76,
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.divider),
            boxShadow: const [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              _Destination(
                label: context.tr(ru: 'Чаты', en: 'Chats'),
                icon: Icons.chat_bubble_rounded,
                color: AppColors.electricBlue,
                selected: navigationShell.currentIndex == 0,
                onTap: () => _goToBranch(0),
              ),
              _Destination(
                label: context.tr(ru: 'Контакты', en: 'Contacts'),
                icon: Icons.people_alt_rounded,
                color: AppColors.purple,
                selected: navigationShell.currentIndex == 1,
                onTap: () => _goToBranch(1),
              ),
              _Destination(
                label: context.tr(ru: 'Настройки', en: 'Settings'),
                icon: Icons.tune_rounded,
                color: AppColors.cyan,
                selected: navigationShell.currentIndex == 2,
                onTap: () => _goToBranch(2),
              ),
              _Destination(
                label: context.tr(ru: 'Профиль', en: 'Profile'),
                icon: Icons.person_rounded,
                color: AppColors.pink,
                selected: navigationShell.currentIndex == 3,
                onTap: () => _goToBranch(3),
              ),
            ],
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
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: selected
                  ? color.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: selected ? color : AppColors.surfaceHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: selected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  style: TextStyle(
                    color: selected ? color : AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
