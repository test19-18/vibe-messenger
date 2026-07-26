import 'package:flutter/material.dart';

import '../theme/vibe_tokens.dart';

/// Circular gradient avatar with initials fallback.
///
/// The gradient is derived from [seed] (falling back to [label]) so a person
/// keeps the same colours in the chat list, the conversation header and the
/// contact sheet.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    required this.label,
    super.key,
    this.imageUrl,
    this.radius = 24,
    this.seed,
    this.isOnline = false,
    this.showPresence = false,
    this.presenceRingColor,
  });

  final String label;
  final String? imageUrl;
  final double radius;
  final String? seed;

  final bool isOnline;

  /// Draws the presence dot even when offline (rendered muted).
  final bool showPresence;

  /// Colour of the ring punched around the presence dot — should match the
  /// surface the avatar sits on so the dot reads as cut out of it.
  final Color? presenceRingColor;

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
    final tokens = context.tokens;
    final normalizedUrl = imageUrl?.trim();
    final gradient = tokens.avatarGradientFor(seed ?? label);
    final diameter = radius * 2;

    // Initials are decorative; the surrounding row already carries the name,
    // and letting them scale would push them out of the circle.
    final initials = Center(
      child: Text(
        _initials,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.7,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );

    final avatar = Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradient,
        ),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: normalizedUrl == null || normalizedUrl.isEmpty
          ? initials
          : Image.network(
              normalizedUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => initials,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : initials,
            ),
    );

    if (!showPresence) {
      return avatar;
    }

    final dotSize = (diameter * 0.28).clamp(10.0, 16.0);
    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: isOnline ? tokens.online : tokens.textTertiary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: presenceRingColor ?? tokens.surface,
                  width: dotSize * 0.18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
