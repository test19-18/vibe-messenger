import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/vibe_tokens.dart';

/// A grouped block of settings rows, optionally introduced by a caption.
///
/// Blocks sit on [VibeTokens.groupedBackground] and separate by the gap between
/// them, so screens read as a stack of related groups rather than one long list.
class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.children,
    super.key,
    this.title,
    this.footer,
  });

  final List<Widget> children;

  /// Caption above the block.
  final String? title;

  /// Explanatory line below the block.
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              6,
            ),
            child: Text(
              title!.toUpperCase(),
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ),
        Material(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              6,
              AppSpacing.md,
              0,
            ),
            child: Text(
              footer!,
              style: TextStyle(color: tokens.textSecondary, fontSize: 12.5),
            ),
          ),
      ],
    );
  }
}

/// Row inside a [SectionCard]: rounded colour-coded icon, title, optional
/// subtitle and a chevron.
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
    final tokens = context.tokens;
    return ListTile(
      onTap: onTap,
      minTileHeight: AppSizes.minTapTarget,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 4,
      ),
      leading: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: iconColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
      horizontalTitleGap: AppSpacing.sm,
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(color: tokens.textSecondary, fontSize: 13),
            ),
      trailing:
          trailing ??
          Icon(Icons.chevron_right_rounded, color: tokens.textTertiary),
    );
  }
}

/// Hairline between rows of a [SectionCard], inset past the icon column.
class SectionDivider extends StatelessWidget {
  const SectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(height: 0.5, indent: 58, color: context.tokens.separator);
  }
}
