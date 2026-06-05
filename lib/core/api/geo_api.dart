// Client for /v1/geo — geolocates the caller's IP (city / country / ISP).
// Two surfaces:
//   • lookup()       — legacy best-effort, returns null on any failure.
//                       Used by the speed-test runner (where any failure is
//                       just "no geo this run").
//   • lookupTyped()  — typed result distinguishing auth vs network vs server
//                       errors, so the Home-chip and Account-card widgets can
//                       render the right state ("hide" vs "недоступно" vs
//                       "Определяю…") instead of conflating everything to "—".

import 'package:dio/dio.dart';
import 'package:hiddify/core/api/app_api.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Typed result of a /v1/geo call used by [GeoApi.lookupTyped].
sealed class GeoLookupResult {
  const GeoLookupResult();
}

class GeoLookupOk extends GeoLookupResult {
  final GeoInfo info;
  const GeoLookupOk(this.info);
}

/// The user is not authenticated (or token rejected). Widgets render nothing.
class GeoLookupAuthExpired extends GeoLookupResult {
  const GeoLookupAuthExpired();
}

/// Transport-level failure (offline, DNS, TLS, connection refused, timeout).
class GeoLookupNetworkError extends GeoLookupResult {
  const GeoLookupNetworkError();
}

/// Server replied but with a non-2xx (or an empty all-null body that we can't
/// usefully show).
class GeoLookupServerError extends GeoLookupResult {
  final int statusCode;
  const GeoLookupServerError(this.statusCode);
}

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

  /// Typed variant used by [myGeoProvider]. Always returns — caller pattern-
  /// matches on the result instead of nursing nulls.
  Future<GeoLookupResult> lookupTyped({required String accessToken}) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        '/geo',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final code = r.statusCode ?? 0;
      if (code == 200 && r.data != null) {
        final info = GeoInfo.fromJson(r.data!);
        // Server replied 200 but with nothing useful — treat as a server
        // error so the UI shows the недоступно-with-retry affordance rather
        // than a misleading bare dash.
        if (info.ip == null && info.city == null && info.country == null) {
          return const GeoLookupServerError(200);
        }
        return GeoLookupOk(info);
      }
      if (code == 401 || code == 403) return const GeoLookupAuthExpired();
      return GeoLookupServerError(code);
    } on DioException catch (e) {
      // All transport failures funnel here.
      switch (e.type) {
        case DioExceptionType.connectionError:
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return const GeoLookupNetworkError();
        default:
          // Per app_api.dart's validateStatus<600, non-2xx arrives here only
          // when Dio still raises (rare). Treat as a network blip.
          return const GeoLookupNetworkError();
      }
    } catch (_) {
      return const GeoLookupNetworkError();
    }
  }
}

final geoApiProvider = Provider<GeoApi>((ref) => GeoApi(ref.watch(appApiClientProvider)));
