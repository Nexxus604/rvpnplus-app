// Speedtest-style screen: a big circular button that, on tap, runs the
// per-protocol speed test (see SpeedTestRunner) — connecting via each
// protocol in turn, showing a live download rate, then per-protocol results
// and a recommendation.

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
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text('Тест скорости — ${widget.args.name}')),
      body: CosmicBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              const Gap(8),
              Center(child: _Dial(progress: p, busy: _busy, onTap: _busy ? null : _start)),
              const Gap(24),
              if (p != null) ...[
                for (final r in p.results) _ResultCard(result: r),
                if (_busy && (p.phase == SpeedPhase.vless || p.phase == SpeedPhase.awg))
                  _RunningCard(
                    protocol: p.phase == SpeedPhase.vless ? 'VLESS' : 'AmneziaWG',
                    liveMbps: p.liveMbps,
                  ),
              ],
              const Gap(16),
              if (p?.phase == SpeedPhase.done && p?.recommendation != null)
                _Summary(text: p!.recommendation!),
              if (p?.phase == SpeedPhase.failed && p?.note != null)
                _Summary(text: p!.note!, error: true),
              const Gap(12),
              Text(
                _hint(p),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Cosmic.muted, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _hint(SpeedProgress? p) {
    if (p == null) {
      return 'Тест поочерёдно подключается по VLESS и AmneziaWG и измеряет '
          'скорость и пинг через этот сервер. Текущее подключение будет прервано.';
    }
    return switch (p.phase) {
      SpeedPhase.preparing => 'Готовлю конфигурации…',
      SpeedPhase.vless => 'Подключаюсь и измеряю по VLESS…',
      SpeedPhase.awg => 'Подключаюсь и измеряю по AmneziaWG…',
      SpeedPhase.finishing => 'Завершаю и восстанавливаю профиль…',
      SpeedPhase.done => 'Готово. Нажмите кнопку, чтобы повторить.',
      SpeedPhase.failed => 'Нажмите кнопку, чтобы попробовать снова.',
      SpeedPhase.idle => '',
    };
  }
}

class _Dial extends StatelessWidget {
  const _Dial({required this.progress, required this.busy, this.onTap});
  final SpeedProgress? progress;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final live = p?.liveMbps;
    String big;
    String small;
    if (busy) {
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
      onTap: onTap,
      child: Container(
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [Cosmic.cardHi, Cosmic.deepest],
            radius: 0.95,
          ),
          border: Border.all(color: Cosmic.violet.withValues(alpha: busy ? .9 : .55), width: 3),
          boxShadow: [
            BoxShadow(
              color: Cosmic.violet.withValues(alpha: busy ? .45 : .25),
              blurRadius: 28,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Cosmic.violetBright),
                  ),
                ),
              Text(
                big,
                style: TextStyle(
                  color: Cosmic.text,
                  fontSize: busy ? 44 : 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (small.isNotEmpty)
                Text(small, style: const TextStyle(color: Cosmic.text2, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});
  final ProtocolResult result;

  @override
  Widget build(BuildContext context) {
    final ok = result.connected;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            _Metric(
              value: result.downloadMbps != null
                  ? result.downloadMbps!.toStringAsFixed(1)
                  : '—',
              label: 'Мбит/с',
            ),
            const Gap(16),
            _Metric(value: result.pingMs != null ? '${result.pingMs}' : '—', label: 'мс'),
          ] else
            Flexible(
              child: Text(
                result.error ?? 'Не подключился',
                textAlign: TextAlign.right,
                style: const TextStyle(color: Cosmic.text2, fontSize: 12),
              ),
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
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Cosmic.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Cosmic.violet.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Cosmic.violetBright),
          ),
          const Gap(10),
          Expanded(
            child: Text(protocol,
                style: const TextStyle(color: Cosmic.text, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          Text(
            liveMbps != null ? '${liveMbps!.toStringAsFixed(1)} Мбит/с' : 'измеряю…',
            style: const TextStyle(color: Cosmic.violetBright, fontSize: 13, fontWeight: FontWeight.w600),
          ),
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
          Expanded(
            child: Text(text, style: const TextStyle(color: Cosmic.text, height: 1.35)),
          ),
        ],
      ),
    );
  }
}
