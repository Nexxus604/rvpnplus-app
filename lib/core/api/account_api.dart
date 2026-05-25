// Typed client for /v1/account (TZ §20.3 — Account).

import 'package:dio/dio.dart';
import 'package:hiddify/core/api/app_api.dart';
import 'package:hiddify/core/api/auth_api.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum AccountErrorCode { unauthorized, network, unknown }

class AccountApiException implements Exception {
  final AccountErrorCode code;
  final String message;
  const AccountApiException(this.code, this.message);
  @override
  String toString() => 'AccountApiException($code, $message)';
}

class SubscriptionSummary {
  final int id;
  final String status;
  final DateTime? expiresAt;
  final int maxDevices;
  const SubscriptionSummary({
    required this.id,
    required this.status,
    required this.maxDevices,
    this.expiresAt,
  });

  factory SubscriptionSummary.fromJson(Map<String, dynamic> json) =>
      SubscriptionSummary(
        id: json['id'] as int,
        status: json['status'] as String,
        expiresAt: json['expires_at'] != null
            ? DateTime.parse(json['expires_at'] as String)
            : null,
        maxDevices: json['max_devices'] as int,
      );
}

class AccountDetails {
  final Account account;
  final SubscriptionSummary? subscription;
  const AccountDetails({required this.account, this.subscription});
}

class AccountApi {
  final Dio _dio;
  const AccountApi(this._dio);

  Future<AccountDetails> get({required String accessToken}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/account',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      if (response.statusCode == 200) {
        final data = response.data!;
        return AccountDetails(
          account: Account.fromJson(data),
          subscription: data['subscription'] != null
              ? SubscriptionSummary.fromJson(
                  data['subscription'] as Map<String, dynamic>,
                )
              : null,
        );
      }
      if (response.statusCode == 401) {
        throw const AccountApiException(
          AccountErrorCode.unauthorized,
          'Access token rejected',
        );
      }
      throw AccountApiException(
        AccountErrorCode.unknown,
        'HTTP ${response.statusCode}',
      );
    } on DioException catch (e) {
      throw AccountApiException(
        AccountErrorCode.network,
        e.message ?? 'Network error',
      );
    }
  }
}

final accountApiProvider = Provider<AccountApi>((ref) {
  return AccountApi(ref.watch(appApiClientProvider));
});
