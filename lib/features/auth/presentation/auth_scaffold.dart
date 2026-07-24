import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    super.key,
    this.showBack = false,
    this.backFallbackLocation = '/login',
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool showBack;
  final String backFallbackLocation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showBack)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton.filledTonal(
                        onPressed: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go(backFallbackLocation);
                          }
                        },
                        icon: const Icon(Icons.arrow_back_rounded),
                        tooltip: 'Назад',
                      ),
                    )
                  else
                    const _BrandMark(),
                  const SizedBox(height: AppSpacing.xl),
                  Text(title, style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: AppSpacing.sm),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: AppSpacing.xl),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF39A0FF), AppColors.electricBlue],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppColors.electricBlue.withValues(alpha: 0.35),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 38),
      ),
    );
  }
}
