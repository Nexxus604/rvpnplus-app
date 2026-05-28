// Visual FX layer around the connect button. State-aware:
//   • disconnected — a white "supernova" pulse: a bright burst of white
//     light that breathes in and out around the button;
//   • connected    — the glow turns cosmic-blue and faint electric arcs
//     drift around the rim continuously (low intensity);
//   • on press     — a strong lightning strike: a white flash, an expanding
//     shock ring and bright bolts radiating outward.
// It's a passive overlay: a Listener triggers the strike on pointer-down but
// never consumes the tap, so the wrapped ConnectionButton still works.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/cosmic_palette.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ConnectionButtonFx extends ConsumerStatefulWidget {
  const ConnectionButtonFx({super.key, required this.child, this.size = 220});
  final Widget child;
  final double size;

  @override
  ConsumerState<ConnectionButtonFx> createState() => _ConnectionButtonFxState();
}

class _ConnectionButtonFxState extends ConsumerState<ConnectionButtonFx>
    with TickerProviderStateMixin {
  // Slow breathing of the supernova halo.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);
  // Continuous driver for the drifting electric arcs (connected only).
  late final AnimationController _arc = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();
  // One-shot lightning strike fired on tap.
  late final AnimationController _strike = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void dispose() {
    _pulse.dispose();
    _arc.dispose();
    _strike.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected =
        ref.watch(connectionNotifierProvider).valueOrNull?.isConnected ?? false;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _strike.forward(from: 0),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_pulse, _arc, _strike]),
                  builder: (context, _) => CustomPaint(
                    painter: _ConnectionFxPainter(
                      pulse: Curves.easeInOut.transform(_pulse.value),
                      time: _arc.value,
                      strike: _strike.value,
                      connected: connected,
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
  _ConnectionFxPainter({
    required this.pulse,
    required this.time,
    required this.strike,
    required this.connected,
  });

  final double pulse; // 0..1 breathing
  final double time; // 0..1 continuous (arc driver)
  final double strike; // 0 (idle) .. 1 (strike finished)
  final bool connected;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * 0.40; // approx button radius

    // Palette flips white→cosmic-blue when the tunnel is up.
    final core = connected ? Cosmic.connectedBlue : Colors.white;
    final mid = connected ? const Color(0xFF2E7BFF) : const Color(0xFFDCEBFF);

    // --- Supernova pulse: a bright burst breathing around the button. ---
    final glowR = r + 8 + 34 * pulse;
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          core.withValues(alpha: 0.0),
          core.withValues(alpha: 0.42 + 0.34 * pulse),
          mid.withValues(alpha: 0.16 + 0.16 * pulse),
          Colors.transparent,
        ],
        stops: const [0.50, 0.66, 0.86, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: glowR));
    canvas.drawCircle(c, glowR, glow);

    // A tight bright rim right at the button edge — the "flash" of the star.
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 + 2 * pulse
      ..color = core.withValues(alpha: 0.20 + 0.30 * pulse)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(c, r + 2, rim);

    // --- Connected: two faint electric arcs drifting around the rim. ---
    if (connected) {
      const arcs = 2;
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < arcs; i++) {
        final phase = (time + i / arcs) % 1.0;
        final fade = math.sin(phase * math.pi); // 0→1→0 over its life
        if (fade <= 0.04) continue;
        final rnd = math.Random(i * 131 + (phase * 4).floor());
        var ang = i * math.pi + time * math.pi * 0.4 + phase;
        var rad = r + 3;
        final path = Path()
          ..moveTo(c.dx + rad * math.cos(ang), c.dy + rad * math.sin(ang));
        for (var seg = 0; seg < 3; seg++) {
          rad += 6 + rnd.nextDouble() * 6;
          ang += (rnd.nextDouble() - 0.5) * 0.45;
          path.lineTo(c.dx + rad * math.cos(ang), c.dy + rad * math.sin(ang));
        }
        arcPaint.color = Cosmic.electric.withValues(alpha: 0.5 * fade);
        canvas.drawPath(path, arcPaint);
      }
    }

    // --- Press: a clean, minimal lightning strike — one bright ring plus
    // three crisp forked bolts (a soft glow pass under a thin core line). ---
    if (strike > 0 && strike < 1) {
      final tip = connected ? Cosmic.connectedBlue : Colors.white;

      // Single thin expanding shock ring.
      final ringR = r + 4 + 70 * Curves.easeOut.transform(strike);
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * (1 - strike)
        ..color = tip.withValues(alpha: (1 - strike) * 0.9);
      canvas.drawCircle(c, ringR, ring);

      // Three forked bolts, 120° apart, fading over the first ~65%.
      if (strike < 0.65) {
        final k = 1 - strike / 0.65;
        final glow = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Cosmic.electric.withValues(alpha: k * 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
        final core = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white.withValues(alpha: k);
        const bolts = 3;
        final reach = r + 14 + 34 * strike;
        for (var i = 0; i < bolts; i++) {
          final a = -math.pi / 2 + i * (2 * math.pi / bolts);
          final start = Offset(c.dx + (r + 2) * math.cos(a), c.dy + (r + 2) * math.sin(a));
          // A 2-kink fork: out, slight zig, slight zag.
          final perp = a + math.pi / 2;
          final p1 = Offset(
            c.dx + (r + (reach - r) * 0.45) * math.cos(a) + 5 * math.cos(perp),
            c.dy + (r + (reach - r) * 0.45) * math.sin(a) + 5 * math.sin(perp),
          );
          final p2 = Offset(
            c.dx + (r + (reach - r) * 0.78) * math.cos(a) - 4 * math.cos(perp),
            c.dy + (r + (reach - r) * 0.78) * math.sin(a) - 4 * math.sin(perp),
          );
          final end = Offset(c.dx + reach * math.cos(a), c.dy + reach * math.sin(a));
          final path = Path()
            ..moveTo(start.dx, start.dy)
            ..lineTo(p1.dx, p1.dy)
            ..lineTo(p2.dx, p2.dy)
            ..lineTo(end.dx, end.dy);
          canvas.drawPath(path, glow);
          canvas.drawPath(path, core);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectionFxPainter old) =>
      old.pulse != pulse ||
      old.time != time ||
      old.strike != strike ||
      old.connected != connected;
}
