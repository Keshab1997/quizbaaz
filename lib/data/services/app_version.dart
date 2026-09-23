import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Cached `package_info_plus` values. Hive is still the only startup await;
/// this loads fire-and-forget so splash/profile never show a hardcoded
/// `1.0.0` again.
class AppVersion {
  AppVersion._();

  static String version = '';
  static String buildNumber = '';

  static String get label {
    if (version.isEmpty) return '';
    return buildNumber.isEmpty ? 'v$version' : 'v$version+$buildNumber';
  }

  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      buildNumber = info.buildNumber;
    } catch (e) {
      debugPrint('AppVersion: package info unavailable – $e');
    }
  }
}
