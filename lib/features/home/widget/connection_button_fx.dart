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

    // --- Connected: faint electric arcs drifting around the rim. ---
    if (connected) {
      const arcs = 3;
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < arcs; i++) {
        final phase = (time + i / arcs) % 1.0;
        final fade = math.sin(phase * math.pi); // 0→1→0 over its life
        if (fade <= 0.04) continue;
        // Reseed a few times across the life so the bolt visibly flickers.
        final rnd = math.Random(i * 131 + (phase * 4).floor());
        var ang = i * 2.39 + time * math.pi * 0.4 + phase;
        var rad = r + 3;
        final path = Path()
          ..moveTo(c.dx + rad * math.cos(ang), c.dy + rad * math.sin(ang));
        for (var seg = 0; seg < 4; seg++) {
          rad += 5 + rnd.nextDouble() * 7;
          ang += (rnd.nextDouble() - 0.5) * 0.5;
          path.lineTo(c.dx + rad * math.cos(ang), c.dy + rad * math.sin(ang));
        }
        arcPaint.color = Cosmic.electric.withValues(alpha: 0.65 * fade);
        canvas.drawPath(path, arcPaint);
      }
    }

    // --- Press: strong lightning strike. ---
    if (strike > 0 && strike < 1) {
      // Bright full-area flash, peaks instantly and fades.
      if (strike < 0.4) {
        final k = 1 - strike / 0.4;
        final big = size.shortestSide * 0.72;
        final flash = Paint()
          ..shader = RadialGradient(
            colors: [Colors.white.withValues(alpha: 0.32 * k), Colors.transparent],
          ).createShader(Rect.fromCircle(center: c, radius: big));
        canvas.drawCircle(c, big, flash);
      }

      // Expanding shock ring.
      final ringR = r + 4 + 78 * strike;
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * (1 - strike)
        ..color = Colors.white.withValues(alpha: (1 - strike) * 0.95);
      canvas.drawCircle(c, ringR, ring);

      // Bright bolts radiating outward (glow pass + core pass).
      if (strike < 0.72) {
        final k = 1 - strike / 0.72;
        final glowBolt = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = Cosmic.electric.withValues(alpha: k * 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
        final bolt = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: k);
        final rnd = math.Random(11);
        const bolts = 9;
        for (var i = 0; i < bolts; i++) {
          final a = i * (2 * math.pi / bolts) + strike * 0.6;
          var rad = r + 2;
          final path = Path()
            ..moveTo(c.dx + rad * math.cos(a), c.dy + rad * math.sin(a));
          for (var seg = 0; seg < 4; seg++) {
            rad += 10 + rnd.nextDouble() * 14 + 28 * strike;
            final jit = (rnd.nextDouble() - 0.5) * 0.42;
            path.lineTo(c.dx + rad * math.cos(a + jit), c.dy + rad * math.sin(a + jit));
          }
          canvas.drawPath(path, glowBolt);
          canvas.drawPath(path, bolt);
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
