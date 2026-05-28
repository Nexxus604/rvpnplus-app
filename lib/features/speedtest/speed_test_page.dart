// Speedtest-style screen. A big dial (shimmering contour when idle; pulsing
// with electric lightning while testing) runs the per-protocol speed test:
// it connects via each protocol in turn, shows a live download rate, per-
// protocol results, the user's location ("from") and the VPN exit ("to") with
// an electric arc between them, a phase-based progress line, and a final
// recommendation.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/theme/cosmic_palette.dart';
import 'package:hiddify/features/common/cosmic_background.dart';
import 'package:hiddify/features/speedtest/speed_test_runner.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SpeedTestArgs {
  final String code;
  final int slotId;
  final String name;
  const SpeedTestArgs({required this.code, required this.slotId, required this.name});
}

class SpeedTestPage extends ConsumerStatefulWidget {
  const SpeedTestPage({super.key, required this.args});
  final SpeedTestArgs args;

  @override
  ConsumerState<SpeedTestPage> createState() => _SpeedTestPageState();
}

class _SpeedTestPageState extends ConsumerState<SpeedTestPage> {
  SpeedProgress? _progress;
  bool _running = false;

  bool get _busy =>
      _running &&
      _progress?.phase != SpeedPhase.done &&
      _progress?.phase != SpeedPhase.failed;

  Future<void> _start() async {
    if (_running) return;
    setState(() {
      _running = true;
      _progress = const SpeedProgress(phase: SpeedPhase.preparing);
    });
    final runner = SpeedTestRunner(ref, serverCode: widget.args.code, slotId: widget.args.slotId);
    try {
      await runner.run((p) {
        if (mounted) setState(() => _progress = p);
      });
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _progress;
    final from = p?.fromGeo;
    final to = p?.toGeo;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text('Тест скорости — ${widget.args.name}')),
      body: CosmicBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  children: [
                    const Gap(4),
                    Center(child: _Dial(progress: p, busy: _busy, onTap: _busy ? null : _start)),
                    const Gap(20),
                    if (p != null)
                      for (final r in p.results) _ResultCard(result: r),
                    if (_busy && (p?.phase == SpeedPhase.vless || p?.phase == SpeedPhase.awg))
                      _RunningCard(
                        protocol: p?.phase == SpeedPhase.vless ? 'VLESS' : 'AmneziaWG',
                        liveMbps: p?.liveMbps,
                      ),
                    const Gap(18),
                    // From → (electric arc) → To
                    _GeoBlock(
                      icon: Icons.smartphone_rounded,
                      title: from?.locationLabel ?? 'Определяю ваше местоположение…',
                      subtitle: from?.isp,
                    ),
                    _ElectricArc(active: _busy),
                    _GeoBlock(
                      icon: Icons.dns_rounded,
                      title: to != null
                          ? '${to.locationLabel}${to.ip != null ? ', IP ${to.ip}' : ''}'
                          : 'Сервер (определяется при подключении)',
                      subtitle: to != null ? kExitProvider : null,
                      highlight: true,
                    ),
                    const Gap(16),
                    if (p?.phase == SpeedPhase.done && p?.recommendation != null)
                      _Summary(text: p!.recommendation!),
                    if (p?.phase == SpeedPhase.failed && p?.note != null)
                      _Summary(text: p!.note!, error: true),
                  ],
                ),
              ),
              _ProgressBar(
                value: switch (p?.phase) {
                  SpeedPhase.done || SpeedPhase.failed => 1.0,
                  _ => p?.progress ?? 0,
                },
                done: p?.phase == SpeedPhase.done,
                failed: p?.phase == SpeedPhase.failed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Dial ───────────────────────────

class _Dial extends StatefulWidget {
  const _Dial({required this.progress, required this.busy, this.onTap});
  final SpeedProgress? progress;
  final bool busy;
  final VoidCallback? onTap;

  @override
  State<_Dial> createState() => _DialState();
}

class _DialState extends State<_Dial> with TickerProviderStateMixin {
  late final AnimationController _rot = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 3600))..repeat();
  late final AnimationController _pulse = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _rot.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    final live = p?.liveMbps;
    String big;
    String small;
    if (widget.busy) {
      big = live != null ? live.toStringAsFixed(1) : '…';
      small = 'Мбит/с';
    } else if (p?.phase == SpeedPhase.done) {
      big = 'Ещё раз';
      small = '';
    } else if (p?.phase == SpeedPhase.failed) {
      big = 'Повторить';
      small = '';
    } else {
      big = 'СТАРТ';
      small = 'нажмите';
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: 230,
        height: 230,
        child: AnimatedBuilder(
          animation: Listenable.merge([_rot, _pulse]),
          builder: (context, _) => CustomPaint(
            painter: _DialPainter(
              rot: _rot.value,
              pulse: Curves.easeInOut.transform(_pulse.value),
              busy: widget.busy,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(big,
                      style: TextStyle(
                          color: Cosmic.text,
                          fontSize: widget.busy ? 46 : 26,
                          fontWeight: FontWeight.w700)),
                  if (small.isNotEmpty)
                    Text(small, style: const TextStyle(color: Cosmic.text2, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({required this.rot, required this.pulse, required this.busy});
  final double rot;
  final double pulse;
  final bool busy;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2 - 8;

    // Soft inner fill.
    canvas.drawCircle(
      c, r,
      Paint()
        ..shader = const RadialGradient(colors: [Cosmic.cardHi, Cosmic.deepest], radius: 0.95)
            .createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Breathing glow (stronger while testing).
    final glowA = busy ? 0.30 + 0.30 * pulse : 0.14 + 0.10 * pulse;
    canvas.drawCircle(
      c, r,
      Paint()
        ..color = Cosmic.violet.withValues(alpha: glowA)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );

    // Shimmering contour — a sweep-gradient ring that rotates ("переливается").
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..shader = SweepGradient(
        transform: GradientRotation(rot * 2 * math.pi),
        colors: const [
          Cosmic.violet,
          Cosmic.violetBright,
          Cosmic.electric,
          Cosmic.connectedBlue,
          Cosmic.violetBright,
          Cosmic.violet,
        ],
        stops: const [0.0, 0.22, 0.4, 0.55, 0.78, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, ring);

    // While testing — electric lightning arcs flicking off the rim.
    if (busy) {
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = Cosmic.electric.withValues(alpha: 0.4 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      final core = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.5 + 0.4 * pulse);
      const bolts = 3;
      final rnd = math.Random((rot * 8).floor());
      for (var i = 0; i < bolts; i++) {
        var ang = rot * 2 * math.pi + i * (2 * math.pi / bolts);
        var rad = r;
        final path = Path()..moveTo(c.dx + rad * math.cos(ang), c.dy + rad * math.sin(ang));
        for (var seg = 0; seg < 3; seg++) {
          rad += 5 + rnd.nextDouble() * 8;
          ang += (rnd.nextDouble() - 0.5) * 0.5;
          path.lineTo(c.dx + rad * math.cos(ang), c.dy + rad * math.sin(ang));
        }
        canvas.drawPath(path, glow);
        canvas.drawPath(path, core);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) =>
      old.rot != rot || old.pulse != pulse || old.busy != busy;
}

// ─────────────────────── Geo blocks + arc ───────────────────────

class _GeoBlock extends StatelessWidget {
  const _GeoBlock({required this.icon, required this.title, this.subtitle, this.highlight = false});
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Cosmic.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight ? Cosmic.connectedBlue.withValues(alpha: .5) : Colors.white.withValues(alpha: .06),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: highlight ? Cosmic.connectedBlue : Cosmic.text2),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(color: Cosmic.text, fontSize: 14, fontWeight: FontWeight.w600)),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const Gap(2),
                  Text(subtitle!, style: const TextStyle(color: Cosmic.text2, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical electric discharge that travels between the two geo blocks while
/// the test runs.
class _ElectricArc extends StatefulWidget {
  const _ElectricArc({required this.active});
  final bool active;

  @override
  State<_ElectricArc> createState() => _ElectricArcState();
}

class _ElectricArcState extends State<_ElectricArc> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _ArcPainter(t: _c.value, active: widget.active),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({required this.t, required this.active});
  final double t;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    if (!active) {
      // Idle: a dim static connector.
      canvas.drawLine(
        Offset(x, 0), Offset(x, size.height),
        Paint()
          ..color = Cosmic.text2.withValues(alpha: 0.25)
          ..strokeWidth = 1.5,
      );
      return;
    }
    final rnd = math.Random((t * 6).floor());
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = Cosmic.connectedBlue.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = Cosmic.electric.withValues(alpha: 0.95);
    final path = Path()..moveTo(x, 0);
    const segs = 5;
    for (var i = 1; i <= segs; i++) {
      final y = size.height * i / segs;
      final dx = i == segs ? 0.0 : (rnd.nextDouble() - 0.5) * 16;
      path.lineTo(x + dx, y);
    }
    canvas.drawPath(path, glow);
    canvas.drawPath(path, core);
    // A bright travelling spark.
    final sy = size.height * t;
    canvas.drawCircle(Offset(x, sy), 2.6, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _ArcPainter old) => old.t != t || old.active != active;
}

// ─────────────────────── Progress line ───────────────────────

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, this.done = false, this.failed = false});
  final double value;
  final bool done;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final solid = failed ? Cosmic.error : (done ? Cosmic.success : null);
    final glow = done || failed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Stack(
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: Cosmic.section,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          AnimatedFractionallySizedBox(
            duration: const Duration(milliseconds: 300),
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: solid,
                gradient: solid == null
                    ? const LinearGradient(colors: [Cosmic.violet, Cosmic.connectedBlue])
                    : null,
                borderRadius: BorderRadius.circular(3),
                // When the test finishes, the bar glows white (success = green
                // fill, failure = red fill) to signal the outcome.
                boxShadow: glow
                    ? [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.75),
                          blurRadius: 9,
                          spreadRadius: 0.5,
                        ),
                        BoxShadow(
                          color: (solid ?? Colors.white).withValues(alpha: 0.6),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────── Result cards ───────────────────────

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});
  final ProtocolResult result;

  @override
  Widget build(BuildContext context) {
    final ok = result.connected;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Cosmic.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.cancel,
              color: ok ? Cosmic.success : Cosmic.error, size: 20),
          const Gap(10),
          Expanded(
            child: Text(result.protocol,
                style: const TextStyle(color: Cosmic.text, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          if (ok) ...[
            _Metric(value: result.downloadMbps?.toStringAsFixed(1) ?? '—', label: 'Мбит/с'),
            const Gap(16),
            _Metric(value: result.pingMs != null ? '${result.pingMs}' : '—', label: 'мс'),
          ] else
            Flexible(
              child: Text(result.error ?? 'Не подключился',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Cosmic.text2, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _RunningCard extends StatelessWidget {
  const _RunningCard({required this.protocol, this.liveMbps});
  final String protocol;
  final double? liveMbps;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Cosmic.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Cosmic.violet.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Cosmic.violetBright)),
          const Gap(10),
          Expanded(
            child: Text(protocol,
                style: const TextStyle(color: Cosmic.text, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          Text(liveMbps != null ? '${liveMbps!.toStringAsFixed(1)} Мбит/с' : 'измеряю…',
              style: const TextStyle(color: Cosmic.violetBright, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(value, style: const TextStyle(color: Cosmic.text, fontSize: 16, fontWeight: FontWeight.w700)),
        Text(label, style: const TextStyle(color: Cosmic.text2, fontSize: 11)),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.text, this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (error ? Cosmic.error : Cosmic.violet).withValues(alpha: .14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: (error ? Cosmic.error : Cosmic.violet).withValues(alpha: .5)),
      ),
      child: Row(
        children: [
          Icon(error ? Icons.error_outline : Icons.lightbulb_outline,
              color: error ? Cosmic.error : Cosmic.violetBright, size: 20),
          const Gap(10),
          Expanded(child: Text(text, style: const TextStyle(color: Cosmic.text, height: 1.35))),
        ],
      ),
    );
  }
}
