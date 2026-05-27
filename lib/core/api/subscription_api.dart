// Typed client for /v1/subscription/* — the account's real servers,
// synced with the Telegram bot (TZ §11 + sync).

import 'package:dio/dio.dart';
import 'package:hiddify/core/api/app_api.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum SubscriptionErrorCode { unauthorized, network, unknown }

class SubscriptionApiException implements Exception {
  final SubscriptionErrorCode code;
  final String message;
  const SubscriptionApiException(this.code, this.message);
  @override
  String toString() => 'SubscriptionApiException($code, $message)';
}

class SubInfo {
  final int id;
  final String status;
  final DateTime? expiresAt;
  final int maxDevices;
  const SubInfo({
    required this.id,
    required this.status,
    required this.maxDevices,
    this.expiresAt,
  });

  factory SubInfo.fromJson(Map<String, dynamic> json) => SubInfo(
        id: json['id'] as int,
        status: json['status'] as String,
        expiresAt: json['expires_at'] != null
            ? DateTime.parse(json['expires_at'] as String)
            : null,
        maxDevices: json['max_devices'] as int,
      );
}

class MyServer {
  final int slotId;
  final String code;
  final String name;
  final String countryCode;
  final String countryName;
  final String countryFlag;
  final String? city;
  final bool isActive;
  final int loadPercent;
  final String? configUrl;

  const MyServer({
    required this.slotId,
    required this.code,
    required this.name,
    required this.countryCode,
    required this.countryName,
    required this.countryFlag,
    required this.isActive,
    required this.loadPercent,
    this.city,
    this.configUrl,
  });

  factory MyServer.fromJson(Map<String, dynamic> json) => MyServer(
        slotId: json['slot_id'] as int,
        code: json['code'] as String,
        name: json['name'] as String,
        countryCode: json['country_code'] as String,
        countryName: json['country_name'] as String,
        countryFlag: json['country_flag'] as String? ?? '',
        city: json['city'] as String?,
        isActive: json['is_active'] as bool,
        loadPercent: json['load_percent'] as int,
        configUrl: json['config_url'] as String?,
      );
}

class MyServersResult {
  final SubInfo? subscription;
  final List<MyServer> servers;
  const MyServersResult({required this.servers, this.subscription});
}

class SubscriptionApi {
  final Dio _dio;
  const SubscriptionApi(this._dio);

  Future<void> deleteServer({
    required String accessToken,
    required int slotId,
  }) async {
    try {
      final response = await _dio.delete<void>(
        '/subscription/servers/$slotId',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      if (response.statusCode == 204) return;
      if (response.statusCode == 401) {
        throw const SubscriptionApiException(
            SubscriptionErrorCode.unauthorized, 'Access token rejected');
      }
      throw SubscriptionApiException(
          SubscriptionErrorCode.unknown, 'HTTP ${response.statusCode}');
    } on DioException catch (e) {
      throw SubscriptionApiException(
          SubscriptionErrorCode.network, e.message ?? 'Network error');
    }
  }

  Future<MyServersResult> myServers({required String accessToken}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/subscription/servers',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      if (response.statusCode == 200) {
        final data = response.data!;
        return MyServersResult(
          subscription: data['subscription'] != null
              ? SubInfo.fromJson(data['subscription'] as Map<String, dynamic>)
              : null,
          servers: (data['servers'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map(MyServer.fromJson)
              .toList(),
        );
      }
      if (response.statusCode == 401) {
        throw const SubscriptionApiException(
            SubscriptionErrorCode.unauthorized, 'Access token rejected');
      }
      throw SubscriptionApiException(
          SubscriptionErrorCode.unknown, 'HTTP ${response.statusCode}');
    } on DioException catch (e) {
      throw SubscriptionApiException(
          SubscriptionErrorCode.network, e.message ?? 'Network error');
    }
  }
}

final subscriptionApiProvider = Provider<SubscriptionApi>((ref) {
  return SubscriptionApi(ref.watch(appApiClientProvider));
});
