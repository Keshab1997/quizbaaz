import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Live `package_info_plus` values. Hive is still the only startup await;
/// this loads fire-and-forget and notifies listeners so splash/profile show
/// the real `pubspec` version instead of a hardcoded `1.0.0`.
class AppVersion extends ChangeNotifier {
  AppVersion._();
  static final AppVersion instance = AppVersion._();

  String version = '';
  String buildNumber = '';

  /// e.g. `1.0.5+6` — the same string Play Console shows.
  String get label {
    if (version.isEmpty) return '';
    return buildNumber.isEmpty ? version : '$version+$buildNumber';
  }

  static Future<void> load() => instance._load();

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      buildNumber = info.buildNumber;
      notifyListeners();
    } catch (e) {
      debugPrint('AppVersion: package info unavailable – $e');
    }
  }
}
