// Typed client for /v1/nodes (TZ §20.3 — Nodes).

import 'package:dio/dio.dart';
import 'package:hiddify/core/api/app_api.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum NodesErrorCode { unauthorized, network, unknown }

class NodesApiException implements Exception {
  final NodesErrorCode code;
  final String message;
  const NodesApiException(this.code, this.message);
  @override
  String toString() => 'NodesApiException($code, $message)';
}

class NodeItem {
  final int id;
  final String code;
  final String name;
  final String countryCode;
  final String countryFlag;
  final String? city;
  final int loadPercent;
  final bool isPremium;

  const NodeItem({
    required this.id,
    required this.code,
    required this.name,
    required this.countryCode,
    required this.countryFlag,
    required this.loadPercent,
    required this.isPremium,
    this.city,
  });

  factory NodeItem.fromJson(Map<String, dynamic> json) => NodeItem(
        id: json['id'] as int,
        code: json['code'] as String,
        name: json['name'] as String,
        countryCode: json['country_code'] as String,
        countryFlag: json['country_flag'] as String? ?? '',
        city: json['city'] as String?,
        loadPercent: json['load_percent'] as int,
        isPremium: json['is_premium'] as bool,
      );
}

class NodesApi {
  final Dio _dio;
  const NodesApi(this._dio);

  Future<List<NodeItem>> list({required String accessToken}) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/nodes',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      if (response.statusCode == 200) {
        return (response.data ?? const [])
            .cast<Map<String, dynamic>>()
            .map(NodeItem.fromJson)
            .toList();
      }
      if (response.statusCode == 401) {
        throw const NodesApiException(
            NodesErrorCode.unauthorized, 'Access token rejected');
      }
      throw NodesApiException(
          NodesErrorCode.unknown, 'HTTP ${response.statusCode}');
    } on DioException catch (e) {
      throw NodesApiException(
          NodesErrorCode.network, e.message ?? 'Network error');
    }
  }
}

final nodesApiProvider = Provider<NodesApi>((ref) {
  return NodesApi(ref.watch(appApiClientProvider));
});
