import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// UMP callbacks have been observed to never fire on some devices (no Play
/// Services, flaky network). Without a timeout the native splash freezes.
const Duration _umpTimeout = Duration(seconds: 5);

/// Google User Messaging Platform (UMP) consent flow for QuizBaaz.
///
/// Why this exists:
/// * **EU/EEA + UK users** (GDPR / UK GDPR) must be shown Google's consent
///   message and may decline personalised ads. No ad may be requested before
///   consent is resolved — [canRequestAds] gates every ad in [AdService].
/// * **India / rest of the world**: `ConsentStatus.notRequired` — nothing is
///   shown and [canRequestAds] is true immediately, so there is zero friction.
///
/// Call order (see `main.dart` + the dashboard):
///   1. `initialize()` at app start — fetches the latest consent status.
///   2. `showConsentFormIfRequired()` after the first frame — displays the
///      Google form only for users who need it.
///   3. `showPrivacyOptions()` from Profile → "Ad Consent Options" — the
///      change-consent entry point Google requires while privacy options are
///      required (EU/UK).
///
/// To test the EU flow from India on a real device, set
/// `ConsentService.debugForceEea = true` once (in `main.dart`), run, and
/// remove it before shipping.
class ConsentService extends ChangeNotifier {
  ConsentService._();

  static final ConsentService instance = ConsentService._();

  /// ⚠️ Test-only. Forces EEA geography so the consent form shows on any
  /// device. Never ship with this enabled.
  static bool debugForceEea = false;

  bool _initialized = false;
  bool _canRequestAds = false;
  ConsentStatus _status = ConsentStatus.unknown;
  PrivacyOptionsRequirementStatus _privacyOptions =
      PrivacyOptionsRequirementStatus.unknown;

  bool get isInitialized => _initialized;

  /// True when the app may request ads (consent resolved, or not required).
  /// All ad loads must check this.
  bool get canRequestAds => _canRequestAds;

  ConsentStatus get consentStatus => _status;

  /// True when Google's privacy options (consent change) entry point must be
  /// shown — i.e. EU/EEA/UK users after the form was presented.
  bool get privacyOptionsRequired =>
      _privacyOptions == PrivacyOptionsRequirementStatus.required;

  /// Fetches the latest consent status. Never throws. Idempotent.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _requestConsentInfoUpdate();
      await _refreshStatuses();
    } catch (e) {
      debugPrint('ConsentService: info update failed – $e');
      _canRequestAds = false;
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  /// Shows the Google consent form — but only when the platform says it is
  /// required (EU/EEA/UK). For everyone else this returns immediately.
  /// Safe to call on every app start.
  Future<void> showConsentFormIfRequired() async {
    if (!_initialized) await initialize();
    try {
      await _runWithListener(
        ConsentForm.loadAndShowConsentFormIfRequired,
        'consent form',
      );
      await _refreshStatuses();
    } catch (e) {
      debugPrint('ConsentService: consent form failed – $e');
    }
    notifyListeners();
  }

  /// The change-consent / privacy options form (EU/UK entry point).
  Future<void> showPrivacyOptions() async {
    try {
      await _runWithListener(
        ConsentForm.showPrivacyOptionsForm,
        'privacy options',
      );
      await _refreshStatuses();
    } catch (e) {
      debugPrint('ConsentService: privacy options failed – $e');
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------ impl --

  Future<void> _requestConsentInfoUpdate() {
    final completer = Completer<void>();
    final params = ConsentRequestParameters(
      consentDebugSettings: debugForceEea
          ? ConsentDebugSettings(
              debugGeography: DebugGeography.debugGeographyEea,
            )
          : null,
    );
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () {
        if (!completer.isCompleted) completer.complete();
      },
      (FormError error) {
        debugPrint('ConsentService: update error – ${error.message}');
        if (!completer.isCompleted) completer.complete();
      },
    );
    return completer.future.timeout(
      _umpTimeout,
      onTimeout: () {
        debugPrint('ConsentService: info update timed out');
      },
    );
  }

  Future<void> _runWithListener(
    void Function(OnConsentFormDismissedListener listener) fn,
    String what,
  ) {
    final completer = Completer<void>();
    fn((FormError? error) {
      if (error != null) {
        debugPrint('ConsentService: $what error – ${error.message}');
      }
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future.timeout(
      _umpTimeout,
      onTimeout: () {
        debugPrint('ConsentService: $what timed out');
      },
    );
  }

  Future<void> _refreshStatuses() async {
    try {
      _status = await ConsentInformation.instance.getConsentStatus();
      _canRequestAds = await ConsentInformation.instance.canRequestAds();
      _privacyOptions = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus();
      debugPrint(
        'ConsentService: status=$_status canRequestAds=$_canRequestAds '
        'privacyOptions=$_privacyOptions',
      );
    } catch (e) {
      debugPrint('ConsentService: status refresh failed – $e');
    }
  }
}
