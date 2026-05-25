// Typed client for /v1/auth/* endpoints on api.rvpn.app.
//
// Phase 1 chunk 2 — wraps the Dio instance from app_api.dart.

import 'package:dio/dio.dart';
import 'package:hiddify/core/api/app_api.dart';
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

class VerifyResult {
  final String accessToken;
  final int expiresIn;
  final Account account;

  const VerifyResult({
    required this.accessToken,
    required this.expiresIn,
    required this.account,
  });
}

/// Server-side error codes mapped to client cases for localised UX.
enum AuthErrorCode {
  otpWrong,
  otpExpired,
  otpExhausted,
  emailSendFailed,
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
    String purpose = 'login',
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/otp/verify',
        data: {'email': email, 'code': code, 'purpose': purpose},
      );
      if (response.statusCode == 200) {
        final data = response.data!;
        return VerifyResult(
          accessToken: data['access_token'] as String,
          expiresIn: data['expires_in'] as int,
          account: Account.fromJson(data['account'] as Map<String, dynamic>),
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
      'EMAIL_SEND_FAILED' => AuthErrorCode.emailSendFailed,
      _ => AuthErrorCode.unknown,
    };
    return AuthApiException(code, message);
  }
}

final authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(ref.watch(appApiClientProvider));
});
