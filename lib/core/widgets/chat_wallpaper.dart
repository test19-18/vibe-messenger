import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/vibe_tokens.dart';

/// Patterned backdrop behind a conversation.
///
/// The pattern is painted procedurally rather than shipped as an asset so it
/// stays crisp at any density and recolours itself with the theme.
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tokens.chatWallpaper, tokens.chatWallpaperEnd],
        ),
      ),
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _WallpaperPatternPainter(color: tokens.chatPattern),
          isComplex: true,
          willChange: false,
          child: child,
        ),
      ),
    );
  }
}

/// Tiles a small set of soft marks across the canvas.
///
/// Keeping every shape inside one 132pt tile means the cost scales with screen
/// area only, and the layout is deterministic — no seeded randomness that would
/// shuffle between frames.
class _WallpaperPatternPainter extends CustomPainter {
  const _WallpaperPatternPainter({required this.color});

  final Color color;

  static const double _tile = 132;

  // Unit-square coordinates within a tile: (x, y, scale, kind).
  // kind 0 = ring, 1 = dot cluster, 2 = rounded square, 3 = arc.
  static const List<List<double>> _marks = [
    [0.14, 0.18, 1.00, 0],
    [0.62, 0.10, 0.62, 1],
    [0.86, 0.42, 0.86, 2],
    [0.38, 0.48, 0.74, 3],
    [0.08, 0.72, 0.68, 2],
    [0.58, 0.78, 1.00, 0],
    [0.90, 0.90, 0.55, 1],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0) {
      return;
    }
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final columns = (size.width / _tile).ceil() + 1;
    final rows = (size.height / _tile).ceil() + 1;

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        // Offset every other row so the grid does not read as a lattice.
        final dx = column * _tile + (row.isEven ? 0 : _tile / 2);
        final dy = row * _tile;
        if (dx > size.width + _tile || dy > size.height + _tile) {
          continue;
        }
        for (final mark in _marks) {
          final center = Offset(dx + mark[0] * _tile, dy + mark[1] * _tile);
          _paintMark(canvas, center, mark[2], mark[3].toInt(), stroke, fill);
        }
      }
    }
  }

  void _paintMark(
    Canvas canvas,
    Offset center,
    double scale,
    int kind,
    Paint stroke,
    Paint fill,
  ) {
    switch (kind) {
      case 0:
        canvas.drawCircle(center, 11 * scale, stroke);
      case 1:
        for (var i = 0; i < 3; i++) {
          final angle = math.pi * 2 / 3 * i - math.pi / 2;
          final offset = Offset(
            center.dx + math.cos(angle) * 7 * scale,
            center.dy + math.sin(angle) * 7 * scale,
          );
          canvas.drawCircle(offset, 2.2 * scale, fill);
        }
      case 2:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: center,
              width: 16 * scale,
              height: 16 * scale,
            ),
            Radius.circular(5 * scale),
          ),
          stroke,
        );
      default:
        canvas.drawArc(
          Rect.fromCenter(
            center: center,
            width: 22 * scale,
            height: 22 * scale,
          ),
          -math.pi * 0.85,
          math.pi * 1.1,
          false,
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(_WallpaperPatternPainter oldDelegate) =>
      oldDelegate.color != color;
}
