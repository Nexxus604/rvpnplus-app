// Per-protocol speed test, run from the client.
//
// For one server it tests each protocol in turn (VLESS, then AmneziaWG):
//   1. import + activate that protocol's profile,
//   2. bring the tunnel up and wait for "connected",
//   3. measure latency and download throughput (routed through the tunnel, so
//      it reflects the real path the user gets via this node),
//   4. tear the tunnel down and move to the next protocol.
// It also resolves geolocation: the user's own ("from", while disconnected)
// and the VPN exit's ("to", while connected, via /v1/geo through the tunnel),
// and reports a phase-based progress 0..1. Finally it recommends the best
// protocol (connected → higher Mbps → lower ping).
//
// NOTE: this drives the live VPN connection (connect/disconnect several
// times) and so interrupts any current connection; the previously-active
// profile is restored at the end (left disconnected).

import 'dart:async';
import 'dart:io';

import 'package:hiddify/core/api/geo_api.dart';
import 'package:hiddify/core/api/subscription_api.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/servers/widget/server_profile_sync.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _downloadUrl = 'https://speed.cloudflare.com/__down?bytes=';
const _downloadBytes = 30000000; // 30 MB ceiling
const _downloadMaxSeconds = 9; // stop early so the whole test stays snappy
const _connectTimeout = Duration(seconds: 25);

/// Provider label always shown for the VPN exit ("to") block.
const kExitProvider = 'R-VPN Plus';

enum SpeedPhase { idle, preparing, vless, awg, finishing, done, failed }

class ProtocolResult {
  final String protocol;
  final bool connected;
  final double? downloadMbps;
  final int? pingMs;
  final String? error;
  const ProtocolResult({
    required this.protocol,
    required this.connected,
    this.downloadMbps,
    this.pingMs,
    this.error,
  });
}

class SpeedProgress {
  final SpeedPhase phase;
  final double progress; // 0..1, phase-based
  final double? liveMbps; // current download rate during a measurement
  final List<ProtocolResult> results;
  final GeoInfo? fromGeo; // user's own location
  final GeoInfo? toGeo; // VPN exit location (isp forced to R-VPN Plus)
  final String? recommendation;
  final String? note;
  const SpeedProgress({
    required this.phase,
    this.progress = 0,
    this.liveMbps,
    this.results = const [],
    this.fromGeo,
    this.toGeo,
    this.recommendation,
    this.note,
  });
}

class SpeedTestRunner {
  SpeedTestRunner(this._ref, {required this.serverCode, required this.slotId});

  final WidgetRef _ref;
  final String serverCode;
  final int slotId;

  final _results = <ProtocolResult>[];
  GeoInfo? _fromGeo;
  GeoInfo? _toGeo;
  double _progress = 0;
  late void Function(SpeedProgress) _emit;

  void _report(SpeedPhase phase, {double? liveMbps, String? note, String? recommendation}) {
    _emit(SpeedProgress(
      phase: phase,
      progress: _progress,
      liveMbps: liveMbps,
      results: List.of(_results),
      fromGeo: _fromGeo,
      toGeo: _toGeo,
      recommendation: recommendation,
      note: note,
    ));
  }

  Future<void> run(void Function(SpeedProgress) onProgress) async {
    _emit = onProgress;
    _progress = 0.04;
    _report(SpeedPhase.preparing);

    final auth = _ref.read(authNotifierProvider);
    if (auth is! AuthAuthenticated) {
      _report(SpeedPhase.failed, note: 'Сессия истекла. Войдите заново.');
      return;
    }
    final api = _ref.read(subscriptionApiProvider);
    final geo = _ref.read(geoApiProvider);
    final sync = _ref.read(serverProfileSyncProvider);

    // Resolve configs + the user's own geolocation, all while still
    // disconnected (so "from" geo is the real user IP, not the exit).
    String? vlessUrl;
    try {
      final mine = await api.myServers(accessToken: auth.accessToken);
      for (final s in mine.servers) {
        if (s.code == serverCode && s.configUrl != null) {
          vlessUrl = s.configUrl;
          break;
        }
      }
    } catch (_) {}
    String? awgConf;
    try {
      awgConf = await api.awgConfig(accessToken: auth.accessToken, slotId: slotId);
    } catch (_) {}

    await _ensureDisconnected();
    _fromGeo = await geo.lookup(accessToken: auth.accessToken);
    _progress = 0.08;
    _report(SpeedPhase.preparing);

    if (vlessUrl == null && awgConf == null) {
      _report(SpeedPhase.failed, note: 'Не удалось получить конфигурации сервера.');
      return;
    }

    final prevActiveId = _ref.read(activeProfileProvider).valueOrNull?.id;

    final steps = <_Step>[
      if (vlessUrl != null) _Step('VLESS', SpeedPhase.vless, () => sync.selectRemote(vlessUrl!)),
      if (awgConf != null) _Step('AmneziaWG', SpeedPhase.awg, () => sync.selectLocal(awgConf!)),
    ];
    final n = steps.length;

    for (var i = 0; i < n; i++) {
      final step = steps[i];
      _progress = 0.08 + (i / n) * 0.86;
      _report(step.phase);
      final imported = await step.select();
      final res = imported
          ? await _measure(step.protocol, step.phase, i, n)
          : ProtocolResult(
              protocol: step.protocol, connected: false, error: 'Профиль не импортирован');
      _results.add(res);
      _progress = 0.08 + ((i + 1) / n) * 0.86;
      _report(step.phase);
      await _ensureDisconnected();
    }

    _progress = 0.97;
    _report(SpeedPhase.finishing);
    if (prevActiveId != null) await sync.setActive(prevActiveId);

    _progress = 1.0;
    _report(SpeedPhase.done, recommendation: _recommend());
  }

  Future<ProtocolResult> _measure(String protocol, SpeedPhase phase, int i, int n) async {
    final conn = _ref.read(connectionNotifierProvider.notifier);
    final base = 0.08 + (i / n) * 0.86;
    final span = 0.86 / n;

    await conn.mayConnect();
    final connected = await _waitConnected();
    if (!connected) {
      return ProtocolResult(
          protocol: protocol, connected: false, error: 'Не удалось подключиться');
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));

    final ping = await _ping();
    final mbps = await _download((mbps, frac) {
      _progress = base + (0.3 + 0.7 * frac) * span;
      _report(phase, liveMbps: mbps);
    });

    return ProtocolResult(
        protocol: protocol, connected: true, downloadMbps: mbps, pingMs: ping);
  }

  Future<int?> _ping() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    int? best;
    try {
      for (var i = 0; i < 3; i++) {
        final sw = Stopwatch()..start();
        try {
          final req = await client.getUrl(Uri.parse('${_downloadUrl}1'));
          final resp = await req.close();
          await resp.drain<void>();
          sw.stop();
          final ms = sw.elapsedMilliseconds;
          if (best == null || ms < best) best = ms;
        } catch (_) {}
      }
    } finally {
      client.close(force: true);
    }
    return best;
  }

  Future<double?> _download(void Function(double mbps, double frac) onLive) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse('$_downloadUrl$_downloadBytes'));
      final resp = await req.close();
      var received = 0;
      final sw = Stopwatch()..start();
      var lastEmit = 0;
      final completer = Completer<double?>();
      late StreamSubscription<List<int>> sub;

      void finish() {
        if (completer.isCompleted) return;
        sw.stop();
        final secs = sw.elapsedMilliseconds / 1000.0;
        final mbps = secs > 0 ? (received * 8) / secs / 1e6 : null;
        sub.cancel();
        completer.complete(mbps);
      }

      sub = resp.listen(
        (chunk) {
          received += chunk.length;
          final ms = sw.elapsedMilliseconds;
          if (ms - lastEmit >= 250) {
            lastEmit = ms;
            final secs = ms / 1000.0;
            final frac = (ms / (_downloadMaxSeconds * 1000)).clamp(0.0, 1.0);
            if (secs > 0) onLive((received * 8) / secs / 1e6, frac);
          }
          if (ms >= _downloadMaxSeconds * 1000) finish();
        },
        onDone: finish,
        onError: (_) => finish(),
        cancelOnError: true,
      );
      return await completer.future;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> _waitConnected() => _waitFor(() {
        final st = _ref.read(connectionNotifierProvider).valueOrNull;
        return st?.isConnected ?? false;
      }, _connectTimeout);

  Future<void> _ensureDisconnected() async {
    await _ref.read(connectionNotifierProvider.notifier).abortConnection();
    await _waitFor(() {
      final st = _ref.read(connectionNotifierProvider).valueOrNull;
      return st?.isDisconnected ?? false;
    }, const Duration(seconds: 12));
  }

  Future<bool> _waitFor(bool Function() cond, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (cond()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return cond();
  }

  String _recommend() {
    final ok = _results.where((r) => r.connected && r.downloadMbps != null).toList();
    if (ok.isEmpty) {
      final anyConn = _results.where((r) => r.connected).toList();
      if (anyConn.isNotEmpty) {
        return 'Подключение работает по ${anyConn.first.protocol}, '
            'но измерить скорость не удалось.';
      }
      return 'Ни один протокол не подключился. Попробуйте другой сервер.';
    }
    ok.sort((a, b) {
      final byMbps = (b.downloadMbps ?? 0).compareTo(a.downloadMbps ?? 0);
      if (byMbps != 0) return byMbps;
      return (a.pingMs ?? 1 << 30).compareTo(b.pingMs ?? 1 << 30);
    });
    final best = ok.first;
    return 'Рекомендуем подключаться по ${best.protocol} — '
        'самая высокая скорость${best.pingMs != null ? ' и низкий пинг' : ''}.';
  }
}

class _Step {
  final String protocol;
  final SpeedPhase phase;
  final Future<bool> Function() select;
  const _Step(this.protocol, this.phase, this.select);
}
