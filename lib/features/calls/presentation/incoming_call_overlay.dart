import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_avatar.dart';
import '../domain/call_models.dart';
import '../providers/call_providers.dart';

/// Incoming call overlay shown when a ringing call is detected.
///
/// This is a full-screen overlay that appears over the current content
/// when [latestIncomingCallProvider] emits a ringing call. It provides
/// Accept and Decline buttons.
///
/// **Note:** This only works in the foreground. Background incoming call
/// notifications require Firebase push, which is not yet configured.
class IncomingCallOverlay extends ConsumerWidget {
  const IncomingCallOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incomingCall = ref.watch(latestIncomingCallProvider);
    final activeCall = ref.watch(activeCallProvider).valueOrNull;

    // Only show the overlay if there's a ringing incoming call
    // and no active call in progress.
    if (incomingCall == null ||
        incomingCall.status != CallStatus.ringingIncoming ||
        activeCall != null) {
      return child;
    }

    return Stack(
      children: [
        child,
        Positioned.fill(child: _IncomingCallSheet(session: incomingCall)),
      ],
    );
  }
}

class _IncomingCallSheet extends ConsumerWidget {
  const _IncomingCallSheet({required this.session});

  final CallSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.background.withValues(alpha: 0.95),
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            // Caller avatar
            AppAvatar(
              label: context.tr(ru: 'Собеседник', en: 'Caller'),
              seed: session.callerId,
              radius: 56,
            ),
            const SizedBox(height: AppSpacing.lg),
            // Caller name (would be fetched from profile in production)
            Text(
              context.tr(ru: 'Входящий звонок', en: 'Incoming call'),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              session.type == CallType.video
                  ? context.tr(ru: 'Видеозвонок', en: 'Video call')
                  : context.tr(ru: 'Аудиозвонок', en: 'Audio call'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const Spacer(),
            // Action buttons
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline
                  _IncomingCallButton(
                    icon: Icons.call_end_rounded,
                    label: context.tr(ru: 'Отклонить', en: 'Decline'),
                    color: AppColors.danger,
                    onPressed: () async {
                      await ref
                          .read(incomingCallActionProvider.notifier)
                          .decline(session);
                    },
                  ),
                  // Accept
                  _IncomingCallButton(
                    icon: session.type == CallType.video
                        ? Icons.videocam_rounded
                        : Icons.call_rounded,
                    label: context.tr(ru: 'Ответить', en: 'Accept'),
                    color: AppColors.success,
                    onPressed: () async {
                      final success = await ref
                          .read(incomingCallActionProvider.notifier)
                          .accept(session);
                      if (success && context.mounted) {
                        // Navigate to the call screen.
                        // The router will pick up the active call state.
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomingCallButton extends StatelessWidget {
  const _IncomingCallButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
