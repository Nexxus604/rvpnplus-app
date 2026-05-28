// Per-protocol speed test, run from the client.
//
// For one server it tests each protocol in turn (VLESS, then AmneziaWG):
//   1. import + activate that protocol's profile,
//   2. bring the tunnel up and wait for "connected",
//   3. measure latency (a few tiny requests) and download throughput
//      (a timed bulk download — routed through the tunnel, so it reflects
//      the real path the user gets via this node),
//   4. tear the tunnel down and move to the next protocol.
// Finally it recommends the best protocol (connected → higher Mbps → lower ping).
//
// NOTE: this drives the live VPN connection (connect/disconnect several
// times) and so interrupts any current connection; the previously-active
// profile is restored at the end (left disconnected).

import 'dart:async';
import 'dart:io';

import 'package:hiddify/core/api/subscription_api.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/servers/widget/server_profile_sync.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Bulk download source, reached THROUGH the tunnel (egress = the node), so
/// the measured rate is what the user actually gets via this server. Supports
/// an arbitrary byte count.
const _downloadUrl = 'https://speed.cloudflare.com/__down?bytes=';
const _downloadBytes = 30000000; // 30 MB ceiling
const _downloadMaxSeconds = 9; // stop early so the whole test stays snappy
const _connectTimeout = Duration(seconds: 25);

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
  final double? liveMbps; // current download rate during a measurement
  final List<ProtocolResult> results;
  final String? recommendation;
  final String? note;
  const SpeedProgress({
    required this.phase,
    this.liveMbps,
    this.results = const [],
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

  Future<void> run(void Function(SpeedProgress) onProgress) async {
    onProgress(const SpeedProgress(phase: SpeedPhase.preparing));

    final auth = _ref.read(authNotifierProvider);
    if (auth is! AuthAuthenticated) {
      onProgress(const SpeedProgress(
          phase: SpeedPhase.failed, note: 'Сессия истекла. Войдите заново.'));
      return;
    }
    final api = _ref.read(subscriptionApiProvider);
    final sync = _ref.read(serverProfileSyncProvider);

    // Resolve the configs for this server up front, while still disconnected.
    String? vlessUrl;
    try {
      final mine = await api.myServers(accessToken: auth.accessToken);
      for (final s in mine.servers) {
        if (s.code == serverCode && s.configUrl != null) {
          vlessUrl = s.configUrl;
          break;
        }
      }
    } catch (_) {/* vless stays null → reported as untestable */}

    String? awgConf;
    try {
      awgConf = await api.awgConfig(accessToken: auth.accessToken, slotId: slotId);
    } catch (_) {/* awg stays null */}

    if (vlessUrl == null && awgConf == null) {
      onProgress(const SpeedProgress(
          phase: SpeedPhase.failed,
          note: 'Не удалось получить конфигурации сервера.'));
      return;
    }

    // Remember the currently-active profile so we can restore it afterwards.
    final prevActiveId = _ref.read(activeProfileProvider).valueOrNull?.id;

    await _ensureDisconnected();

    // VLESS
    if (vlessUrl != null) {
      onProgress(SpeedProgress(phase: SpeedPhase.vless, results: List.of(_results)));
      final ok = await sync.selectRemote(vlessUrl);
      final res = ok
          ? await _measure('VLESS', onProgress)
          : const ProtocolResult(
              protocol: 'VLESS', connected: false, error: 'Профиль не импортирован');
      _results.add(res);
      onProgress(SpeedProgress(phase: SpeedPhase.vless, results: List.of(_results)));
      await _ensureDisconnected();
    }

    // AmneziaWG
    if (awgConf != null) {
      onProgress(SpeedProgress(phase: SpeedPhase.awg, results: List.of(_results)));
      final ok = await sync.selectLocal(awgConf);
      final res = ok
          ? await _measure('AmneziaWG', onProgress)
          : const ProtocolResult(
              protocol: 'AmneziaWG', connected: false, error: 'Профиль не импортирован');
      _results.add(res);
      onProgress(SpeedProgress(phase: SpeedPhase.awg, results: List.of(_results)));
      await _ensureDisconnected();
    }

    // Restore the previous profile (left disconnected).
    onProgress(SpeedProgress(phase: SpeedPhase.finishing, results: List.of(_results)));
    if (prevActiveId != null) await sync.setActive(prevActiveId);

    onProgress(SpeedProgress(
      phase: SpeedPhase.done,
      results: List.of(_results),
      recommendation: _recommend(),
    ));
  }

  // Connect via the (already-activated) profile, measure ping + download.
  Future<ProtocolResult> _measure(
    String protocol,
    void Function(SpeedProgress) onProgress,
  ) async {
    final conn = _ref.read(connectionNotifierProvider.notifier);
    await conn.mayConnect();
    final connected = await _waitConnected();
    if (!connected) {
      return ProtocolResult(
          protocol: protocol, connected: false, error: 'Не удалось подключиться');
    }

    // Give the tunnel a moment to settle routes.
    await Future<void>.delayed(const Duration(milliseconds: 800));

    final ping = await _ping();
    final mbps = await _download((live) {
      onProgress(SpeedProgress(
        phase: protocol == 'VLESS' ? SpeedPhase.vless : SpeedPhase.awg,
        liveMbps: live,
        results: List.of(_results),
      ));
    });

    return ProtocolResult(
      protocol: protocol,
      connected: true,
      downloadMbps: mbps,
      pingMs: ping,
    );
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
        } catch (_) {/* skip this sample */}
      }
    } finally {
      client.close(force: true);
    }
    return best;
  }

  Future<double?> _download(void Function(double mbps) onLive) async {
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
          if (ms - lastEmit >= 300) {
            lastEmit = ms;
            final secs = ms / 1000.0;
            if (secs > 0) onLive((received * 8) / secs / 1e6);
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
