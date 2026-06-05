// myGeoProvider — the user's REAL IP / city / country / ISP, fetched via
// /v1/geo. Single source of truth shared by the Home chip and the Account
// "Ваш реальный IP" card so they stay in sync without double-fetching.
//
// Lifecycle / re-runs (Riverpod handles all of this for free):
//   • Re-runs on login / logout — `ref.watch(authNotifierProvider)` covers it.
//   • Re-runs on biometric lock engaging / disengaging — `ref.watch` on the
//     `locked` selector. While locked we don't hit the network.
//   • A 10-minute internal freshness timer auto-invalidates so long-lived
//     sessions naturally re-check without user action.
//   • A Connectivity listener invalidates on network identity change
//     (Wi-Fi ↔ LTE / SSID change / carrier handover).
//   • Manual: `ref.invalidate(myGeoProvider)` from the chip / card refresh
//     action.
//
// Intentionally NOT autoDispose — the chip lives on Home and the card on
// Account; we keep one cached fetch alive across navigation so switching tabs
// doesn't refetch. The 10-minute timer + auth/lock gates are enough lifecycle.

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hiddify/core/api/geo_api.dart';
import 'package:hiddify/core/auth/biometric_lock.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final myGeoProvider = FutureProvider<GeoLookupResult>((ref) async {
  // Lock gate — biometric prompt is up / app is on the lock screen; no work,
  // no leaked HTTP request behind the prompt.
  final locked = ref.watch(biometricLockProvider.select((s) => s.locked));
  if (locked) return const GeoLookupAuthExpired();

  // Auth gate — pre-login state. Widgets render nothing.
  final auth = ref.watch(authNotifierProvider);
  if (auth is! AuthAuthenticated) return const GeoLookupAuthExpired();

  // Invalidate on network identity change. connectivity_plus 6.x emits the
  // current state immediately on subscribe — we skip that first replay so we
  // don't self-invalidate on every provider run.
  var skipFirstConnectivityEvent = true;
  final connSub = Connectivity().onConnectivityChanged.listen((_) {
    if (skipFirstConnectivityEvent) {
      skipFirstConnectivityEvent = false;
      return;
    }
    ref.invalidateSelf();
  });
  ref.onDispose(connSub.cancel);

  // 10-minute internal freshness. Stopwatch-via-Timer (no DateTime → immune
  // to NTP jumps / DST). Cancelled with the provider.
  final ttl = Timer(const Duration(minutes: 10), ref.invalidateSelf);
  ref.onDispose(ttl.cancel);

  // The actual call. 8s timeout — /v1/geo behind nginx is usually <1s, so 8s
  // is generous; longer than 8s, treat as a network blip.
  return await ref
      .read(geoApiProvider)
      .lookupTyped(accessToken: auth.accessToken)
      .timeout(
        const Duration(seconds: 8),
        onTimeout: () => const GeoLookupNetworkError(),
      );
});
