// HTTP client for the R-VPN+ App API at https://api.rvpn.app/v1/.
//
// This is the entry point for all app↔backend communication: auth (OTP),
// subscription, nodes, payments, chat, push. The JWT access token is injected
// per-call by each typed client (subscription_api, account_api, …), and the
// global [_JwtAuthInterceptor] watches for 401s, refreshes the token via
// [AuthNotifier.refreshAccess], and transparently retries the original
// request once. Without this interceptor every typed client would silently
// log the user out the first time the 15-min access token expired (audit
// finding H14).

import 'package:dio/dio.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
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
      // Never let Dio throw on an HTTP status — the app inspects the
      // body + code itself (so "invalid OTP" / "rate limited" /
      // "email send failed" all surface as proper messages). Only
      // genuine transport failures (timeout, DNS, TLS, connection
      // refused) raise DioException → mapped to AuthErrorCode.network.
      //
      // Previously this was `status < 500`, which made every 5xx
      // (including our own 502 EMAIL_SEND_FAILED) throw a DioException
      // that the UI mislabelled as "нет связи с интернетом".
      validateStatus: (status) => status != null && status < 600,
    ),
  );

  dio.interceptors.add(_JwtAuthInterceptor(ref, dio));

  return dio;
});

/// Refresh-on-401 + retry-once. Marks the retried request with a sentinel
/// header so the second pass through the interceptor short-circuits even on
/// another 401 — no infinite loop.
class _JwtAuthInterceptor extends Interceptor {
  _JwtAuthInterceptor(this._ref, this._dio);
  final Ref _ref;
  final Dio _dio;

  static const _retryHeader = 'X-Rvpnplus-Auth-Retried';

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    if (response.statusCode != 401) {
      handler.next(response);
      return;
    }
    final ro = response.requestOptions;
    // Don't bounce 401s from the auth endpoints — refreshing in response to a
    // refresh failure is the definition of a loop, and verify/request 401s
    // mean the OTP itself is wrong (a refresh would not fix that).
    if (ro.path.contains('/auth/')) {
      handler.next(response);
      return;
    }
    if (ro.headers[_retryHeader] == '1') {
      // Already retried once — surface the 401 to the caller.
      handler.next(response);
      return;
    }
    // The ENTIRE 401 branch must be guarded: an exception thrown in the async
    // body of a Dio interceptor reaches neither `next` nor `reject`, so the
    // original request's Future would never complete and every awaiting caller
    // hangs forever. refreshAccess() can throw a PlatformException (Keystore /
    // secure-storage failure — the documented MIUI mode) or a StateError on a
    // disposed container; `_ref.read` likewise. On ANY failure, fall through to
    // surfacing the original 401 so the caller at least gets a response.
    try {
      final notifier = _ref.read(authNotifierProvider.notifier);
      final ok = await notifier.refreshAccess();
      if (!ok) {
        handler.next(response);
        return;
      }
      final auth = _ref.read(authNotifierProvider);
      if (auth is! AuthAuthenticated) {
        handler.next(response);
        return;
      }
      // Replay the original request with the new access token + retry marker.
      final newHeaders = Map<String, dynamic>.from(ro.headers);
      newHeaders['Authorization'] = 'Bearer ${auth.accessToken}';
      newHeaders[_retryHeader] = '1';
      final retryOptions = ro.copyWith(headers: newHeaders);
      final retry = await _dio.fetch<dynamic>(retryOptions);
      handler.resolve(retry);
    } catch (_) {
      // Refresh or retry transport failed — surface the original 401 response
      // rather than leaving the request hanging.
      handler.next(response);
    }
  }
}
