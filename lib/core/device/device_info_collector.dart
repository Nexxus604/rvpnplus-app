// Collects per-device metadata for the backend (TZ §7.2 + §8).
//
// `install_id` is a UUIDv4 minted on first launch and persisted in
// shared_preferences. It anchors the device fingerprint
// (sha256(platform|os|model|install_id) computed server-side) so the
// same physical install dedupes on re-login. install_id resets on
// app uninstall/reinstall — accepted trade-off.

import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _kInstallIdKey = 'app_install_id';

class DeviceInfoPayload {
  final String platform; // 'android' | 'ios' | 'windows' | 'macos' | 'linux'
  final String? osVersion;
  final String? deviceModel;
  final String? appVersion;
  final String installId;
  final String? name;

  const DeviceInfoPayload({
    required this.platform,
    required this.installId,
    this.osVersion,
    this.deviceModel,
    this.appVersion,
    this.name,
  });

  Map<String, dynamic> toJson() => {
        'platform': platform,
        if (osVersion != null) 'os_version': osVersion,
        if (deviceModel != null) 'device_model': deviceModel,
        if (appVersion != null) 'app_version': appVersion,
        'install_id': installId,
        if (name != null) 'name': name,
      };
}

class DeviceInfoCollector {
  Future<DeviceInfoPayload> collect() async {
    final installId = await _getOrCreateInstallId();
    final pkg = await PackageInfo.fromPlatform();
    final appVersion = '${pkg.version}+${pkg.buildNumber}';

    final plugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await plugin.androidInfo;
      return DeviceInfoPayload(
        platform: 'android',
        osVersion: 'Android ${a.version.release}',
        deviceModel: '${a.manufacturer} ${a.model}',
        appVersion: appVersion,
        installId: installId,
        name: '${a.manufacturer} ${a.model} (Android ${a.version.release})',
      );
    }
    if (Platform.isIOS) {
      final i = await plugin.iosInfo;
      return DeviceInfoPayload(
        platform: 'ios',
        osVersion: 'iOS ${i.systemVersion}',
        deviceModel: i.utsname.machine,
        appVersion: appVersion,
        installId: installId,
        name: '${i.name} (iOS ${i.systemVersion})',
      );
    }
    if (Platform.isWindows) {
      final w = await plugin.windowsInfo;
      return DeviceInfoPayload(
        platform: 'windows',
        osVersion: 'Windows ${w.productName}',
        deviceModel: w.computerName,
        appVersion: appVersion,
        installId: installId,
        name: '${w.computerName} (Windows)',
      );
    }
    if (Platform.isMacOS) {
      final m = await plugin.macOsInfo;
      return DeviceInfoPayload(
        platform: 'macos',
        osVersion: 'macOS ${m.osRelease}',
        deviceModel: m.model,
        appVersion: appVersion,
        installId: installId,
        name: '${m.computerName} (macOS ${m.osRelease})',
      );
    }
    if (Platform.isLinux) {
      final l = await plugin.linuxInfo;
      return DeviceInfoPayload(
        platform: 'linux',
        osVersion: '${l.name} ${l.version}',
        deviceModel: l.machineId,
        appVersion: appVersion,
        installId: installId,
        name: '${l.prettyName} (Linux)',
      );
    }
    return DeviceInfoPayload(
      platform: 'unknown',
      appVersion: appVersion,
      installId: installId,
    );
  }

  Future<String> _getOrCreateInstallId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_kInstallIdKey);
    if (existing != null) return existing;
    final fresh = const Uuid().v4();
    await prefs.setString(_kInstallIdKey, fresh);
    return fresh;
  }
}

final deviceInfoCollectorProvider = Provider<DeviceInfoCollector>((_) {
  return DeviceInfoCollector();
});
