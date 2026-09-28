import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../services/hive_service.dart';
import '../services/push_sync.dart';

/// Owns the app language.
///
/// One setting drives everything: the UI chrome *and* the quiz content, since
/// questions ship pre-translated in the same three languages (see
/// `LocalizedText`). There is deliberately no separate "quiz language" — an
/// earlier build machine-translated questions at runtime and it was the wrong
/// trade for an exam-prep app: unreliable terminology, a network dependency,
/// and rate limits.
///
/// The choice persists in the Hive meta box, so a returning user never has to
/// pick again.
class LocaleProvider extends ChangeNotifier {
  static const metaAppLanguage = 'app_language_code';
  static const metaFollowSystem = 'app_language_follow_system';

  String _appLanguage = 'en';
  bool _followSystem = true;

  /// Active UI language code — always one of [kSupportedLanguageCodes].
  String get appLanguage => _appLanguage;

  /// Whether the UI language tracks the device setting instead of an explicit
  /// choice.
  bool get followSystem => _followSystem;

  Locale get locale => Locale(_appLanguage);

  /// Reads persisted preferences and primes [S]. Safe to call more than once.
  ///
  /// Must run *after* `HiveService.initialize()`.
  void initialize() {
    _followSystem = HiveService.getMeta<bool>(metaFollowSystem) ?? true;
    final stored = HiveService.getMeta<String>(metaAppLanguage);

    if (_followSystem || stored == null) {
      _appLanguage = _deviceLanguage();
    } else {
      _appLanguage = kSupportedLanguageCodes.contains(stored) ? stored : 'en';
    }

    S.load(_appLanguage);
    notifyListeners();
  }

  /// The device language if we ship a catalogue for it, otherwise English.
  String _deviceLanguage() {
    final code = PlatformDispatcher.instance.locale.languageCode;
    return kSupportedLanguageCodes.contains(code) ? code : 'en';
  }

  /// Switches the UI language and remembers the choice.
  Future<void> setAppLanguage(String code) async {
    if (!kSupportedLanguageCodes.contains(code)) return;
    if (!_followSystem && _appLanguage == code) return;

    _appLanguage = code;
    _followSystem = false;
    S.load(code);
    await HiveService.setMeta(metaAppLanguage, code);
    await HiveService.setMeta(metaFollowSystem, false);
    notifyListeners();
    unawaited(PushSync.syncFromHive());
  }

  /// Hands language selection back to the operating system.
  Future<void> useSystemLanguage() async {
    _followSystem = true;
    _appLanguage = _deviceLanguage();
    S.load(_appLanguage);
    await HiveService.setMeta(metaFollowSystem, true);
    await HiveService.setMeta(metaAppLanguage, null);
    notifyListeners();
    unawaited(PushSync.syncFromHive());
  }
}
