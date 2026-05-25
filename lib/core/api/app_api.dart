// HTTP client for the R-VPN+ App API at https://api.rvpn.app/v1/.
//
// This is the entry point for all app↔backend communication: auth (OTP),
// subscription, nodes, payments, chat, push. JWT access token is
// injected automatically once the user is authenticated (Phase 1).

import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Base URL of our REST API. Hardcoded — we never proxy this through
/// the VPN tunnel (auth has to work whether or not the user is
/// connected).
const String appApiBaseUrl = 'https://api.rvpn.app/v1';

/// Minimum app version the server accepts. Force-update gate (TZ §23.3)
/// reads `/version.min_supported_app_version` and compares to local
/// pubspec version on each app start.
const Duration appApiTimeout = Duration(seconds: 15);

final appApiClientProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: appApiBaseUrl,
      connectTimeout: appApiTimeout,
      sendTimeout: appApiTimeout,
      receiveTimeout: appApiTimeout,
      headers: {
        'User-Agent': 'R-VPN+ App/0.1.0',
        'Accept': 'application/json',
      },
      // Don't auto-throw on 4xx — the app needs to inspect the error
      // body to decide whether to show "invalid OTP" vs "rate limited"
      // vs "server down".
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  // JWT auth interceptor — slot in when we implement login (Phase 1).
  // dio.interceptors.add(_JwtAuthInterceptor(ref));

  return dio;
});
