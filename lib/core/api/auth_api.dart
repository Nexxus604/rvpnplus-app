// Typed client for /v1/auth/* endpoints on api.rvpn.app.

import 'package:dio/dio.dart';
import 'package:hiddify/core/api/app_api.dart';
import 'package:hiddify/core/device/device_info_collector.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class Account {
  final int id;
  final String email;
  final bool emailVerified;
  final String locale;
  final bool hasTelegram;

  const Account({
    required this.id,
    required this.email,
    required this.emailVerified,
    required this.locale,
    required this.hasTelegram,
  });

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as int,
        email: json['email'] as String,
        emailVerified: json['email_verified'] as bool,
        locale: json['locale'] as String,
        hasTelegram: json['has_telegram'] as bool,
      );
}

class DeviceInfo {
  final int id;
  final String? name;
  final String platform;

  const DeviceInfo({required this.id, required this.platform, this.name});

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
        id: json['id'] as int,
        platform: json['platform'] as String,
        name: json['name'] as String?,
      );
}

class VerifyResult {
  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final Account account;
  final DeviceInfo device;

  const VerifyResult({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.account,
    required this.device,
  });
}

class RefreshResult {
  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  const RefreshResult({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });
}

/// Server-side error codes mapped to client cases for localised UX.
enum AuthErrorCode {
  otpWrong,
  otpExpired,
  otpExhausted,
  otpCooldown,
  emailSendFailed,
  refreshInvalid,
  accountInactive,
  network,
  unknown,
}

class AuthApiException implements Exception {
  final AuthErrorCode code;
  final String message;
  const AuthApiException(this.code, this.message);

  @override
  String toString() => 'AuthApiException($code, $message)';
}

class AuthApi {
  final Dio _dio;
  const AuthApi(this._dio);

  Future<void> requestOtp({
    required String email,
    String purpose = 'login',
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/otp/request',
        data: {'email': email, 'purpose': purpose},
      );
      if (response.statusCode == 200) return;
      throw _mapError(response.statusCode, response.data);
    } on DioException catch (e) {
      throw AuthApiException(AuthErrorCode.network, e.message ?? 'Network error');
    }
  }

  Future<VerifyResult> verifyOtp({
    required String email,
    required String code,
    required DeviceInfoPayload device,
    String purpose = 'login',
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/otp/verify',
        data: {
          'email': email,
          'code': code,
          'purpose': purpose,
          'device': device.toJson(),
        },
      );
      if (response.statusCode == 200) {
        final data = response.data!;
        return VerifyResult(
          accessToken: data['access_token'] as String,
          refreshToken: data['refresh_token'] as String,
          expiresIn: data['expires_in'] as int,
          account: Account.fromJson(data['account'] as Map<String, dynamic>),
          device: DeviceInfo.fromJson(data['device'] as Map<String, dynamic>),
        );
      }
      throw _mapError(response.statusCode, response.data);
    } on DioException catch (e) {
      throw AuthApiException(AuthErrorCode.network, e.message ?? 'Network error');
    }
  }

  Future<RefreshResult> refresh({required String refreshToken}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      if (response.statusCode == 200) {
        final data = response.data!;
        return RefreshResult(
          accessToken: data['access_token'] as String,
          refreshToken: data['refresh_token'] as String,
          expiresIn: data['expires_in'] as int,
        );
      }
      throw _mapError(response.statusCode, response.data);
    } on DioException catch (e) {
      throw AuthApiException(AuthErrorCode.network, e.message ?? 'Network error');
    }
  }

  AuthApiException _mapError(int? status, dynamic body) {
    // FastAPI returns {"detail": {"code": "...", "message": "..."}}
    String? serverCode;
    String message = 'Unknown error';
    if (body is Map && body['detail'] is Map) {
      final detail = body['detail'] as Map;
      serverCode = detail['code'] as String?;
      message = detail['message'] as String? ?? message;
    }
    final code = switch (serverCode) {
      'OTP_WRONG' => AuthErrorCode.otpWrong,
      'OTP_EXPIRED' => AuthErrorCode.otpExpired,
      'OTP_EXHAUSTED' => AuthErrorCode.otpExhausted,
      'OTP_COOLDOWN' => AuthErrorCode.otpCooldown,
      'EMAIL_SEND_FAILED' => AuthErrorCode.emailSendFailed,
      'REFRESH_INVALID' => AuthErrorCode.refreshInvalid,
      'ACCOUNT_INACTIVE' => AuthErrorCode.accountInactive,
      _ => AuthErrorCode.unknown,
    };
    return AuthApiException(code, message);
  }
}

final authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(ref.watch(appApiClientProvider));
});
