// Visual FX layer around the connect button:
//   • idle  — a breathing violet halo that "invites" a tap, plus a few
//             bright electrons running around the rim;
//   • press — an electric discharge: an expanding ring + short lightning
//             bolts, and a brief area brighten.
// It's a passive overlay: a Listener triggers the spark on pointer-down but
// never consumes the tap, so the wrapped ConnectionButton still works.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/cosmic_palette.dart';

class ConnectionButtonFx extends StatefulWidget {
  const ConnectionButtonFx({super.key, required this.child, this.size = 220});
  final Widget child;
  final double size;

  @override
  State<ConnectionButtonFx> createState() => _ConnectionButtonFxState();
}

class _ConnectionButtonFxState extends State<ConnectionButtonFx>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);
  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();
  late final AnimationController _spark = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  @override
  void dispose() {
    _pulse.dispose();
    _orbit.dispose();
    _spark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _spark.forward(from: 0),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_pulse, _orbit, _spark]),
                  builder: (context, _) => CustomPaint(
                    painter: _ConnectionFxPainter(
                      pulse: Curves.easeInOut.transform(_pulse.value),
                      orbit: _orbit.value,
                      spark: _spark.value,
                    ),
                  ),
                ),
              ),
            ),
            widget.child,
          ],
        ),
      ),
    );
  }
}

class _ConnectionFxPainter extends CustomPainter {
  _ConnectionFxPainter({required this.pulse, required this.orbit, required this.spark});
  final double pulse; // 0..1 breathing
  final double orbit; // 0..1 rotation
  final double spark; // 0 (idle) .. 1 (press burst finished)

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * 0.40; // approx button radius

    // Brief area brighten on press (peaks early, fades) — "фон чуть светлее".
    if (spark > 0 && spark < 0.7) {
      final k = 1 - spark / 0.7;
      final big = size.shortestSide * 0.72;
      final b = Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.10 * k), Colors.transparent],
        ).createShader(Rect.fromCircle(center: c, radius: big));
      canvas.drawCircle(c, big, b);
    }

    // Idle glow — breathing violet halo behind the button.
    final glowR = r + 12 + 16 * pulse;
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          Cosmic.violetBright.withValues(alpha: 0.30 + 0.22 * pulse),
          Cosmic.violet.withValues(alpha: 0.14 + 0.12 * pulse),
          Colors.transparent,
        ],
        stops: const [0.55, 0.82, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: glowR));
    canvas.drawCircle(c, glowR, glow);

    // Running electrons — bright dots orbiting the rim.
    const n = 6;
    final er = r + 7;
    final dot = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < n; i++) {
      final a = orbit * 2 * math.pi + i * (2 * math.pi / n);
      final p = Offset(c.dx + er * math.cos(a), c.dy + er * math.sin(a));
      dot.color = Cosmic.violetBright.withValues(alpha: 0.35);
      canvas.drawCircle(p, 5.5, dot);
      dot.color = Colors.white.withValues(alpha: 0.95);
      canvas.drawCircle(p, 2.2, dot);
    }

    // Press → electric discharge.
    if (spark > 0 && spark < 1) {
      final ringR = r + 4 + 46 * spark;
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * (1 - spark)
        ..color = Colors.white.withValues(alpha: (1 - spark) * 0.9);
      canvas.drawCircle(c, ringR, ring);

      if (spark < 0.6) {
        final k = 1 - spark / 0.6;
        final bolt = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = Cosmic.violetBright.withValues(alpha: k);
        final rnd = math.Random(7);
        for (var i = 0; i < 8; i++) {
          final a = i * (2 * math.pi / 8) + spark;
          var rad = r + 2;
          final path = Path()
            ..moveTo(c.dx + rad * math.cos(a), c.dy + rad * math.sin(a));
          for (var seg = 0; seg < 3; seg++) {
            rad += 8 + rnd.nextDouble() * 9;
            final jit = (rnd.nextDouble() - 0.5) * 0.28;
            path.lineTo(c.dx + rad * math.cos(a + jit), c.dy + rad * math.sin(a + jit));
          }
          canvas.drawPath(path, bolt);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectionFxPainter old) =>
      old.pulse != pulse || old.orbit != orbit || old.spark != spark;
}
