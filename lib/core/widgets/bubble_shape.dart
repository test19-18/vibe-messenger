import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Which bottom corner carries the bubble tail.
enum BubbleTailSide { left, right }

/// A chat bubble outline with the messenger-style tail on one bottom corner.
///
/// Only the last bubble of a sender streak draws a tail ([hasTail]); the rest
/// tuck their tail-side bottom corner in tight, which is what makes a run of
/// messages read as one block.
///
/// Used as a [ShapeDecoration] shape so bubbles can carry a gradient and clip
/// media payloads to the same outline.
@immutable
class BubbleShape extends ShapeBorder {
  const BubbleShape({
    required this.side,
    this.hasTail = true,
    this.radius = AppRadii.bubble,
    this.tailWidth = 7,
    this.tailHeight = 13,
  });

  final BubbleTailSide side;
  final bool hasTail;
  final double radius;
  final double tailWidth;
  final double tailHeight;

  bool get _tailOnRight => side == BubbleTailSide.right;

  /// Horizontal room reserved for the tail, so text never runs into it.
  @override
  EdgeInsetsGeometry get dimensions => hasTail
      ? EdgeInsets.only(
          left: _tailOnRight ? 0 : tailWidth,
          right: _tailOnRight ? tailWidth : 0,
        )
      : EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    // Keep the geometry sane on very small bubbles (single emoji, avatars).
    final r = radius.clamp(0.0, rect.shortestSide / 2);
    final tailH = tailHeight.clamp(0.0, rect.height);
    // A tucked corner marks "more messages from the same sender below".
    final tuck = AppRadii.bubbleTail.clamp(0.0, r);

    if (!hasTail) {
      return Path()..addRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: Radius.circular(r),
          topRight: Radius.circular(r),
          bottomLeft: Radius.circular(_tailOnRight ? r : tuck),
          bottomRight: Radius.circular(_tailOnRight ? tuck : r),
        ),
      );
    }

    final t = rect.top;
    final b = rect.bottom;
    final path = Path();

    if (_tailOnRight) {
      final l = rect.left;
      // Right edge of the bubble body; the tail bulges beyond it.
      final bx = rect.right - tailWidth;
      path
        ..moveTo(l + r, t)
        ..lineTo(bx - r, t)
        ..quadraticBezierTo(bx, t, bx, t + r)
        ..lineTo(bx, b - tailH)
        // Flare out and down to the tip sitting on the baseline.
        ..cubicTo(bx, b - tailH * 0.3, bx + tailWidth * 0.45, b, rect.right, b)
        // Straight underside back into the body's bottom edge.
        ..lineTo(l + r, b)
        ..quadraticBezierTo(l, b, l, b - r)
        ..lineTo(l, t + r)
        ..quadraticBezierTo(l, t, l + r, t)
        ..close();
    } else {
      final rr = rect.right;
      // Left edge of the bubble body; the tail bulges beyond it.
      final bx = rect.left + tailWidth;
      path
        ..moveTo(bx + r, t)
        ..lineTo(rr - r, t)
        ..quadraticBezierTo(rr, t, rr, t + r)
        ..lineTo(rr, b - r)
        ..quadraticBezierTo(rr, b, rr - r, b)
        // Bottom edge continues straight into the tail's underside.
        ..lineTo(rect.left, b)
        // Mirror of the right-hand flare, traversed tip-first.
        ..cubicTo(bx - tailWidth * 0.45, b, bx, b - tailH * 0.3, bx, b - tailH)
        ..lineTo(bx, t + r)
        ..quadraticBezierTo(bx, t, bx + r, t)
        ..close();
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    // Bubbles are filled by their decoration; the outline carries no stroke.
  }

  @override
  ShapeBorder scale(double t) => BubbleShape(
    side: side,
    hasTail: hasTail,
    radius: radius * t,
    tailWidth: tailWidth * t,
    tailHeight: tailHeight * t,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is BubbleShape &&
        other.side == side &&
        other.hasTail == hasTail &&
        other.radius == radius &&
        other.tailWidth == tailWidth &&
        other.tailHeight == tailHeight;
  }

  @override
  int get hashCode => Object.hash(side, hasTail, radius, tailWidth, tailHeight);
}
