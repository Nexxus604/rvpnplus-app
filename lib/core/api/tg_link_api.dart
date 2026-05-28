// Client for /v1/auth/telegram/* — the in-app "link my Telegram" flow.
// start() mints a request_id + bot deeplink; the user confirms in the bot
// (enters their email + OTP there); status() polls until the bot confirms,
// then returns tokens the app uses to log in (auth_notifier.loginWithTokens).

import 'package:dio/dio.dart';
import 'package:hiddify/core/api/app_api.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum TgLinkErrorCode { network, unknown }

class TgLinkApiException implements Exception {
  final TgLinkErrorCode code;
  final String message;
  const TgLinkApiException(this.code, this.message);
}

class TgLinkStart {
  final String requestId;
  final String botDeeplink;
  final int expiresIn;
  const TgLinkStart({
    required this.requestId,
    required this.botDeeplink,
    required this.expiresIn,
  });
}

class TgLinkStatus {
  final String status; // "pending" | "ready" | "expired"
  final String? accessToken;
  final String? refreshToken;
  const TgLinkStatus({required this.status, this.accessToken, this.refreshToken});

  bool get isReady => status == 'ready';
  bool get isExpired => status == 'expired';
}

class TgLinkApi {
  final Dio _dio;
  const TgLinkApi(this._dio);

  Future<TgLinkStart> start() async {
    try {
      final r = await _dio.post<Map<String, dynamic>>('/auth/telegram/start');
      final data = r.data!;
      return TgLinkStart(
        requestId: data['request_id'] as String,
        botDeeplink: data['bot_deeplink'] as String,
        expiresIn: (data['expires_in'] as num?)?.toInt() ?? 300,
      );
    } on DioException catch (e) {
      throw TgLinkApiException(TgLinkErrorCode.network, e.message ?? 'Network error');
    }
  }

  Future<TgLinkStatus> status(String requestId) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        '/auth/telegram/status',
        queryParameters: {'request_id': requestId},
      );
      final data = r.data!;
      return TgLinkStatus(
        status: data['status'] as String? ?? 'pending',
        accessToken: data['access_token'] as String?,
        refreshToken: data['refresh_token'] as String?,
      );
    } on DioException catch (e) {
      throw TgLinkApiException(TgLinkErrorCode.network, e.message ?? 'Network error');
    }
  }
}

final tgLinkApiProvider = Provider<TgLinkApi>((ref) {
  return TgLinkApi(ref.watch(appApiClientProvider));
});
