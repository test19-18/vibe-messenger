import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../providers/backend_providers.dart';
import '../theme/app_colors.dart';

class BackendStatusBanner extends ConsumerWidget {
  const BackendStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(backendBootstrapProvider);
    if (backend.isReady) {
      return const SizedBox.shrink();
    }

    final failed = backend.status == BackendStatus.failed;
    return Semantics(
      container: true,
      label: backend.message,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: (failed ? AppColors.danger : AppColors.warning).withValues(
            alpha: 0.12,
          ),
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(
            color: failed ? AppColors.danger : AppColors.warning,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              failed ? Icons.error_outline_rounded : Icons.info_outline_rounded,
              color: failed ? AppColors.danger : AppColors.warning,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                backend.message,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
