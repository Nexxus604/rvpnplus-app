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

/// A server in the activation catalog (Stage 2): may or may not already be
/// active for this account. [slotId] is set when active (for deactivation).
class CatalogServer {
  final String code;
  final String name;
  final String countryCode;
  final String countryName;
  final String countryFlag;
  final String? city;
  final bool isPremium;
  final int loadPercent;
  final bool isActivated;
  final int? slotId;

  const CatalogServer({
    required this.code,
    required this.name,
    required this.countryCode,
    required this.countryName,
    required this.countryFlag,
    required this.isPremium,
    required this.loadPercent,
    required this.isActivated,
    this.city,
    this.slotId,
  });

  factory CatalogServer.fromJson(Map<String, dynamic> json) => CatalogServer(
        code: json['code'] as String,
        name: json['name'] as String,
        countryCode: json['country_code'] as String,
        countryName: json['country_name'] as String,
        countryFlag: json['country_flag'] as String? ?? '',
        city: json['city'] as String?,
        isPremium: json['is_premium'] as bool,
        loadPercent: json['load_percent'] as int,
        isActivated: json['is_activated'] as bool,
        slotId: json['slot_id'] as int?,
      );
}

class CatalogResult {
  final SubInfo? subscription;
  final List<CatalogServer> servers;
  const CatalogResult({required this.servers, this.subscription});
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

  Future<CatalogResult> catalog({required String accessToken}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/subscription/catalog',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      if (response.statusCode == 200) {
        final data = response.data!;
        return CatalogResult(
          subscription: data['subscription'] != null
              ? SubInfo.fromJson(data['subscription'] as Map<String, dynamic>)
              : null,
          servers: (data['servers'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map(CatalogServer.fromJson)
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

  /// Activate (provision) a server by code. Returns the server message.
  Future<String> activateServer({
    required String accessToken,
    required String serverCode,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/subscription/servers',
        data: {'server_code': serverCode},
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        return (response.data?['message'] as String?) ?? 'Сервер активирован';
      }
      if (response.statusCode == 401) {
        throw const SubscriptionApiException(
            SubscriptionErrorCode.unauthorized, 'Access token rejected');
      }
      // 409 ACTIVATE_FAILED / 412 BIND_TELEGRAM carry a detail message.
      final detail = response.data?['detail'];
      final msg = detail is Map ? (detail['message'] as String?) : null;
      throw SubscriptionApiException(
          SubscriptionErrorCode.unknown, msg ?? 'HTTP ${response.statusCode}');
    } on DioException catch (e) {
      final detail = e.response?.data is Map ? e.response?.data['detail'] : null;
      final msg = detail is Map ? (detail['message'] as String?) : null;
      if (msg != null) {
        throw SubscriptionApiException(SubscriptionErrorCode.unknown, msg);
      }
      throw SubscriptionApiException(
          SubscriptionErrorCode.network, e.message ?? 'Network error');
    }
  }

  /// AmneziaWG .conf for an active server slot (the app imports it as a
  /// local profile; sing-box runs it as an `awg` outbound).
  Future<String> awgConfig({
    required String accessToken,
    required int slotId,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/subscription/servers/$slotId/awg',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      if (response.statusCode == 200) {
        return response.data!['content'] as String;
      }
      if (response.statusCode == 401) {
        throw const SubscriptionApiException(
            SubscriptionErrorCode.unauthorized, 'Access token rejected');
      }
      final detail = response.data?['detail'];
      final msg = detail is Map ? (detail['message'] as String?) : null;
      throw SubscriptionApiException(
          SubscriptionErrorCode.unknown, msg ?? 'HTTP ${response.statusCode}');
    } on DioException catch (e) {
      final detail = e.response?.data is Map ? e.response?.data['detail'] : null;
      final msg = detail is Map ? (detail['message'] as String?) : null;
      if (msg != null) {
        throw SubscriptionApiException(SubscriptionErrorCode.unknown, msg);
      }
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
