import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    required this.label,
    super.key,
    this.imageUrl,
    this.radius = 24,
    this.seed,
  });

  final String label;
  final String? imageUrl;
  final double radius;
  final String? seed;

  static const _palette = [
    AppColors.electricBlue,
    AppColors.purple,
    AppColors.cyan,
    AppColors.pink,
    AppColors.success,
    AppColors.warning,
  ];

  String get _initials {
    final parts = label.trim().split(RegExp(r'\s+'));
    final letters = parts
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first.toUpperCase())
        .join();
    return letters.isEmpty ? 'В' : letters;
  }

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = imageUrl?.trim();
    final colorSeed = seed ?? label;
    final color = _palette[colorSeed.hashCode.abs() % _palette.length];

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: normalizedUrl == null || normalizedUrl.isEmpty
          ? Center(
              child: Text(
                _initials,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: radius * 0.72,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          : Image.network(
              normalizedUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Center(
                child: Text(
                  _initials,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: radius * 0.72,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
    );
  }
}
