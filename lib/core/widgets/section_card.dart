import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: BorderSide(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class VibeListTile extends StatelessWidget {
  const VibeListTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    super.key,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
    );
  }
}
