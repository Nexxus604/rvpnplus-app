// Typed client for /v1/tariffs — purchasable plans. Payment itself happens
// by opening the tariff's Tribute link (url_launcher) in the payments screen.

import 'package:dio/dio.dart';
import 'package:hiddify/core/api/app_api.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum TariffsErrorCode { unauthorized, network, unknown }

class TariffsApiException implements Exception {
  final TariffsErrorCode code;
  final String message;
  const TariffsApiException(this.code, this.message);
  @override
  String toString() => 'TariffsApiException($code, $message)';
}

class Tariff {
  final String code;
  final String title;
  final String? description;
  final int durationDays;
  final int maxDevices;
  final double priceRub;
  final int? priceStars;
  final String? tributeLink;

  const Tariff({
    required this.code,
    required this.title,
    required this.durationDays,
    required this.maxDevices,
    required this.priceRub,
    this.description,
    this.priceStars,
    this.tributeLink,
  });

  bool get payable => tributeLink != null && tributeLink!.isNotEmpty;

  factory Tariff.fromJson(Map<String, dynamic> json) => Tariff(
        code: json['code'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        durationDays: json['duration_days'] as int,
        maxDevices: json['max_devices'] as int,
        priceRub: (json['price_rub'] as num).toDouble(),
        priceStars: json['price_stars'] as int?,
        tributeLink: json['tribute_link'] as String?,
      );
}

class TariffsApi {
  final Dio _dio;
  const TariffsApi(this._dio);

  Future<List<Tariff>> list({required String accessToken}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/tariffs',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      if (response.statusCode == 200) {
        return (response.data!['tariffs'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(Tariff.fromJson)
            .toList();
      }
      if (response.statusCode == 401) {
        throw const TariffsApiException(
            TariffsErrorCode.unauthorized, 'Access token rejected');
      }
      throw TariffsApiException(
          TariffsErrorCode.unknown, 'HTTP ${response.statusCode}');
    } on DioException catch (e) {
      throw TariffsApiException(TariffsErrorCode.network, e.message ?? 'Network error');
    }
  }
}

final tariffsApiProvider = Provider<TariffsApi>((ref) {
  return TariffsApi(ref.watch(appApiClientProvider));
});
