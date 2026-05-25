// Typed client for /v1/devices (TZ §20.3 — Devices).

import 'package:dio/dio.dart';
import 'package:hiddify/core/api/app_api.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum DevicesErrorCode { unauthorized, notFound, network, unknown }

class DevicesApiException implements Exception {
  final DevicesErrorCode code;
  final String message;
  const DevicesApiException(this.code, this.message);
  @override
  String toString() => 'DevicesApiException($code, $message)';
}

class DeviceItem {
  final int id;
  final String? name;
  final String platform;
  final String? osVersion;
  final String? deviceModel;
  final String? appVersion;
  final DateTime lastSeenAt;
  final DateTime createdAt;

  const DeviceItem({
    required this.id,
    required this.platform,
    required this.lastSeenAt,
    required this.createdAt,
    this.name,
    this.osVersion,
    this.deviceModel,
    this.appVersion,
  });

  factory DeviceItem.fromJson(Map<String, dynamic> json) => DeviceItem(
        id: json['id'] as int,
        name: json['name'] as String?,
        platform: json['platform'] as String,
        osVersion: json['os_version'] as String?,
        deviceModel: json['device_model'] as String?,
        appVersion: json['app_version'] as String?,
        lastSeenAt: DateTime.parse(json['last_seen_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class DevicesApi {
  final Dio _dio;
  const DevicesApi(this._dio);

  Future<List<DeviceItem>> list({required String accessToken}) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/devices',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      if (response.statusCode == 200) {
        return (response.data ?? const [])
            .cast<Map<String, dynamic>>()
            .map(DeviceItem.fromJson)
            .toList();
      }
      if (response.statusCode == 401) {
        throw const DevicesApiException(
            DevicesErrorCode.unauthorized, 'Access token rejected');
      }
      throw DevicesApiException(
          DevicesErrorCode.unknown, 'HTTP ${response.statusCode}');
    } on DioException catch (e) {
      throw DevicesApiException(
          DevicesErrorCode.network, e.message ?? 'Network error');
    }
  }

  Future<void> revoke({
    required String accessToken,
    required int deviceId,
  }) async {
    try {
      final response = await _dio.delete<void>(
        '/devices/$deviceId',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      if (response.statusCode == 204) return;
      if (response.statusCode == 401) {
        throw const DevicesApiException(
            DevicesErrorCode.unauthorized, 'Access token rejected');
      }
      if (response.statusCode == 404) {
        throw const DevicesApiException(
            DevicesErrorCode.notFound, 'Device not found');
      }
      throw DevicesApiException(
          DevicesErrorCode.unknown, 'HTTP ${response.statusCode}');
    } on DioException catch (e) {
      throw DevicesApiException(
          DevicesErrorCode.network, e.message ?? 'Network error');
    }
  }
}

final devicesApiProvider = Provider<DevicesApi>((ref) {
  return DevicesApi(ref.watch(appApiClientProvider));
});
