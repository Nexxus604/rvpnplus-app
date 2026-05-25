// Typed client for /v1/nodes (TZ §20.3 — Nodes).

import 'package:dio/dio.dart';
import 'package:hiddify/core/api/app_api.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum NodesErrorCode {
  unauthorized,
  notFound,
  notProvisioned,
  bindTelegram,
  noSubscription,
  panelUnconfigured,
  network,
  unknown,
}

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

class NodeConfig {
  final int nodeId;
  final String nodeCode;
  final String configUrl;        // default — sing-box
  final String configUrlSingbox;
  final String configUrlClash;
  final String configUrlV2ray;

  const NodeConfig({
    required this.nodeId,
    required this.nodeCode,
    required this.configUrl,
    required this.configUrlSingbox,
    required this.configUrlClash,
    required this.configUrlV2ray,
  });

  factory NodeConfig.fromJson(Map<String, dynamic> json) => NodeConfig(
        nodeId: json['node_id'] as int,
        nodeCode: json['node_code'] as String,
        configUrl: json['config_url'] as String,
        configUrlSingbox: json['config_url_singbox'] as String,
        configUrlClash: json['config_url_clash'] as String,
        configUrlV2ray: json['config_url_v2ray'] as String,
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

  Future<NodeConfig> getConfig({
    required String accessToken,
    required int nodeId,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/nodes/$nodeId/config',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      if (response.statusCode == 200) {
        return NodeConfig.fromJson(response.data!);
      }
      throw _mapError(response.statusCode, response.data);
    } on DioException catch (e) {
      throw NodesApiException(
          NodesErrorCode.network, e.message ?? 'Network error');
    }
  }

  NodesApiException _mapError(int? status, dynamic body) {
    String? serverCode;
    String message = 'Unknown';
    if (body is Map && body['detail'] is Map) {
      final detail = body['detail'] as Map;
      serverCode = detail['code'] as String?;
      message = detail['message'] as String? ?? message;
    }
    final code = switch (serverCode) {
      'NODE_NOT_FOUND' => NodesErrorCode.notFound,
      'NODE_NOT_PROVISIONED' => NodesErrorCode.notProvisioned,
      'BIND_TELEGRAM' => NodesErrorCode.bindTelegram,
      'NO_USER' || 'NO_SUBSCRIPTION' => NodesErrorCode.noSubscription,
      'NODE_PANEL_UNCONFIGURED' => NodesErrorCode.panelUnconfigured,
      _ => status == 401
          ? NodesErrorCode.unauthorized
          : NodesErrorCode.unknown,
    };
    return NodesApiException(code, message);
  }
}

final nodesApiProvider = Provider<NodesApi>((ref) {
  return NodesApi(ref.watch(appApiClientProvider));
});
