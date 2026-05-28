// Client for /v1/geo — geolocates the caller's IP (city / country / ISP).
// Called while disconnected for the user's own location, and while connected
// (through the tunnel) for the VPN exit's location.

import 'package:dio/dio.dart';
import 'package:hiddify/core/api/app_api.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GeoInfo {
  final String? ip;
  final String? city;
  final String? country;
  final String? countryCode;
  final String? isp;
  const GeoInfo({this.ip, this.city, this.country, this.countryCode, this.isp});

  factory GeoInfo.fromJson(Map<String, dynamic> j) => GeoInfo(
        ip: j['ip'] as String?,
        city: j['city'] as String?,
        country: j['country'] as String?,
        countryCode: j['country_code'] as String?,
        isp: j['isp'] as String?,
      );

  /// "Москва, Россия" — falls back to the IP, then a dash.
  String get locationLabel {
    final parts = <String>[
      if (city != null && city!.isNotEmpty) city!,
      if (country != null && country!.isNotEmpty) country!,
    ];
    if (parts.isNotEmpty) return parts.join(', ');
    return ip ?? '—';
  }

  GeoInfo copyWith({String? isp}) => GeoInfo(
        ip: ip,
        city: city,
        country: country,
        countryCode: countryCode,
        isp: isp ?? this.isp,
      );
}

class GeoApi {
  final Dio _dio;
  const GeoApi(this._dio);

  /// Geolocate an IP. With [ip] null, the backend geolocates the caller's IP
  /// (the user's own location). With [ip] set, it geolocates that address —
  /// used for the VPN exit IP, which the app discovers through the tunnel.
  Future<GeoInfo?> lookup({required String accessToken, String? ip}) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        '/geo',
        queryParameters: ip != null ? {'ip': ip} : null,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      if (r.statusCode == 200 && r.data != null) {
        return GeoInfo.fromJson(r.data!);
      }
    } catch (_) {/* best-effort — UI shows a dash if geo is unavailable */}
    return null;
  }
}

final geoApiProvider = Provider<GeoApi>((ref) => GeoApi(ref.watch(appApiClientProvider)));
