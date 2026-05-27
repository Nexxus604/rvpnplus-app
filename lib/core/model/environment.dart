import 'package:dartx/dartx.dart';

enum Environment {
  prod,
  dev;

  static const sentryDSN = String.fromEnvironment("sentry_dsn");
  // This environment variable is set in the 'windows-release-zip' command
  static const isPortable = bool.fromEnvironment("portable");
}

enum Release {
  general("general"),
  // This environment variable is set in the 'android-release-aab' command
  googlePlay("google-play");

  const Release(this.key);

  final String key;

  // Disabled for R-VPN+. The upstream checker queries Hiddify-Next's
  // GitHub releases and sends users to Hiddify's download page on
  // "update". We re-enable this with our own checker (against
  // api.rvpn.app /v1/version) once R-VPN+ is published to the stores.
  bool get allowCustomUpdateChecker => false;

  static Release read() =>
      Release.values.firstOrNullWhere((e) => e.key == const String.fromEnvironment("release")) ?? Release.general;
}
