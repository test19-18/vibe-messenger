import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/vibe_tokens.dart';

/// Centred capsule floating over the chat wallpaper.
///
/// Carries date separators and system events ("user joined", "call ended") —
/// anything that belongs to the conversation but not to a participant.
class ServicePill extends StatelessWidget {
  const ServicePill({required this.label, super.key, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: tokens.servicePill,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: tokens.onServicePill),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: tokens.onServicePill,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
