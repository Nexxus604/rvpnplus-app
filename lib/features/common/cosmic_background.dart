// Deep-space backdrop for R-VPN+ cosmic screens: a vertical purple gradient,
// two soft violet nebula glows, and a field of static (seeded) stars. Drop it
// behind a transparent Scaffold body.
//
//   Scaffold(
//     backgroundColor: Colors.transparent,
//     body: CosmicBackground(child: ...),
//   )

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/cosmic_palette.dart';

class CosmicBackground extends StatelessWidget {
  const CosmicBackground({super.key, required this.child, this.stars = 130});

  final Widget child;
  final int stars;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1140), Cosmic.bg, Cosmic.deepest],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
      child: CustomPaint(
        painter: _StarfieldPainter(stars),
        isComplex: true,
        child: child,
      ),
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter(this.count);
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    // Two faint nebula glows (top-left violet, bottom-right brighter violet).
    _glow(canvas, Offset(size.width * 0.18, size.height * 0.16),
        size.shortestSide * 0.7, Cosmic.violet.withValues(alpha: .18));
    _glow(canvas, Offset(size.width * 0.85, size.height * 0.82),
        size.shortestSide * 0.6, Cosmic.violetBright.withValues(alpha: .12));

    // Stars — seeded so the field is stable across rebuilds.
    final rng = Random(42);
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < count; i++) {
      final dx = rng.nextDouble() * size.width;
      final dy = rng.nextDouble() * size.height;
      final r = rng.nextDouble() * 1.3 + 0.3;
      final opacity = rng.nextDouble() * 0.7 + 0.2;
      // Occasional brighter violet-tinted star.
      final tinted = rng.nextInt(7) == 0;
      paint.color = (tinted ? Cosmic.violetBright : Colors.white)
          .withValues(alpha: opacity);
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }

  void _glow(Canvas canvas, Offset center, double radius, Color color) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter old) => old.count != count;
}
