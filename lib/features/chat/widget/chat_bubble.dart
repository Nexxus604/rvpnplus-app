// App-wide floating AI assistant bubble. Mounted once in the MaterialApp
// builder Stack (app.dart) so it overlays every route. Hides itself unless
// the user is authenticated; tapping opens the full chat screen.
//
// Rocket mark = FontAwesomeIcons.rocket on a warm orange disc, pulsing like
// an orange "supernova" with a blue electric light shimmering around the rim
// (the R-VPN+ support button).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/theme/cosmic_palette.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChatBubble extends ConsumerWidget {
  const ChatBubble({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authed = ref.watch(authNotifierProvider) is AuthAuthenticated;
    if (!authed) return const SizedBox.shrink();

    return Positioned(
      right: 16,
      bottom: 96,
      child: SafeArea(
        child: RocketMark(
          onTap: () {
            final ctx = rootNavKey.currentContext;
            if (ctx != null) GoRouter.of(ctx).push('/chat');
          },
        ),
      ),
    );
  }
}

/// Orange rocket disc that pulses like a supernova, with a blue electric
/// light shimmering around the rim. Used for the support button (with
/// [onTap]) and, statically, as the chat avatar ([pulse] off).
class RocketMark extends StatefulWidget {
  const RocketMark({super.key, this.size = 60, this.onTap, this.pulse = true});

  final double size;
  final VoidCallback? onTap;
  final bool pulse;

  // Warm orange "supernova".
  static const _orangeDeep = Color(0xFFFF5E1A);
  static const _orangeBright = Color(0xFFFFB347);
  static const _halo = Color(0xFFFF7A18);

  @override
  State<RocketMark> createState() => _RocketMarkState();
}

class _RocketMarkState extends State<RocketMark> with TickerProviderStateMixin {
  // Breathing supernova halo.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  // Blue electric light travelling around the rim.
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) {
      _pulse.repeat(reverse: true);
      _ring.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disc = AnimatedBuilder(
      animation: Listenable.merge([_pulse, _ring]),
      builder: (context, child) {
        final t = widget.pulse ? _pulse.value : 0.0;
        final glow = 16.0 + 16.0 * t; // halo grows/shrinks
        final scale = 1.0 + 0.06 * t;
        return Transform.scale(
          scale: scale,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Disc + orange supernova halo.
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [RocketMark._orangeDeep, RocketMark._orangeBright],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: RocketMark._halo.withValues(alpha: 0.45 + 0.30 * t),
                        blurRadius: glow,
                        spreadRadius: 1.5 + 2.0 * t,
                      ),
                    ],
                  ),
                ),
                // Blue electric ring shimmering around the rim.
                if (widget.pulse)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ElectricRingPainter(rot: _ring.value, t: t),
                    ),
                  ),
                child!,
              ],
            ),
          ),
        );
      },
      child: Center(
        child: FaIcon(
          FontAwesomeIcons.rocket,
          color: Colors.white,
          size: widget.size * 0.42,
        ),
      ),
    );

    if (widget.onTap == null) return disc;
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: disc,
    );
  }
}

/// Blue electric light running around the disc rim: a sweep-gradient ring
/// whose bright spot rotates, plus a couple of jagged sparks at the leading
/// edge to sell the "electric" look.
class _ElectricRingPainter extends CustomPainter {
  _ElectricRingPainter({required this.rot, required this.t});
  final double rot; // 0..1 rotation
  final double t; // 0..1 pulse

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 1.5;
    final stroke = math.max(2.0, size.shortestSide * 0.04);

    // Shimmer ring — a blue glow that travels around the circle.
    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..shader = SweepGradient(
        transform: GradientRotation(rot * 2 * math.pi),
        colors: [
          Colors.transparent,
          Cosmic.electric.withValues(alpha: 0.10),
          Cosmic.connectedBlue.withValues(alpha: 0.85 + 0.10 * t),
          Cosmic.electric.withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.34, 0.5, 0.66, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: radius))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
    canvas.drawCircle(c, radius, sweep);

    // Sparks near the bright leading spot.
    final spark = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, size.shortestSide * 0.022)
      ..strokeCap = StrokeCap.round
      ..color = Cosmic.electric.withValues(alpha: 0.9);
    final lead = rot * 2 * math.pi;
    final rnd = math.Random((rot * 12).floor());
    for (var i = 0; i < 2; i++) {
      var ang = lead + (i - 0.5) * 0.35;
      var rad = radius;
      final path = Path()
        ..moveTo(c.dx + rad * math.cos(ang), c.dy + rad * math.sin(ang));
      for (var seg = 0; seg < 3; seg++) {
        rad += size.shortestSide * (0.06 + rnd.nextDouble() * 0.06);
        ang += (rnd.nextDouble() - 0.5) * 0.5;
        path.lineTo(c.dx + rad * math.cos(ang), c.dy + rad * math.sin(ang));
      }
      canvas.drawPath(path, spark);
    }
  }

  @override
  bool shouldRepaint(covariant _ElectricRingPainter old) =>
      old.rot != rot || old.t != t;
}
