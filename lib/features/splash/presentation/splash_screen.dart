import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, color: AppColors.electricBlue, size: 64),
            SizedBox(height: AppSpacing.md),
            Text(
              'Вайб',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: AppSpacing.lg),
            CircularProgressIndicator(strokeWidth: 2.5),
          ],
        ),
      ),
    );
  }
}
