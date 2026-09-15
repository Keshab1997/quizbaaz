import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Thin, **fail-soft** wrapper around the trusted backend callables in
/// `/functions` (P0 security fix, R02).
///
/// These operations are the server-authority path for economy and
/// competitive state:
///
///   * [submitDailyResult] — server-computed, once-per-day daily credit
///   * [purchaseItem]      — atomic server-side wallet deduct + grant
///   * [resolveBattle]     — server-declared battle winner
///
/// The app stays offline-first: every call here is best-effort. When
/// Firebase is not initialised, the functions are not deployed, the network
/// is down, or the callable errors, we log and move on — the local flow is
/// never blocked by the trusted backend.
class TrustedOpsService {
  static FirebaseFunctions? get _functions {
    if (Firebase.apps.isEmpty) return null;
    try {
      return FirebaseFunctions.instance;
    } catch (e) {
      debugPrint('TrustedOps: functions unavailable – $e');
      return null;
    }
  }

  static Future<void> _call(String name, Map<String, dynamic> data) async {
    final functions = _functions;
    if (functions == null) return;
    try {
      await functions.httpsCallable(name).call(data);
    } catch (e) {
      // Expected while the functions are not deployed yet (or offline).
      debugPrint('TrustedOps: $name failed – $e');
    }
  }

  /// Credits today's daily quiz result server-side (idempotent per day via
  /// `users/{uid}/daily_claims/{date}`).
  static Future<void> submitDailyResult({
    required String date,
    required int score,
    required int correct,
    required int total,
    required double timeSeconds,
  }) {
    return _call('submitDailyResult', {
      'date': date,
      'score': score,
      'correct': correct,
      'total': total,
      'timeSeconds': timeSeconds,
    });
  }

  /// Runs the server-side purchase (idempotent per [purchaseId]).
  static Future<void> purchaseItem({
    required String itemId,
    required String purchaseId,
  }) {
    return _call('purchaseItem', {'itemId': itemId, 'purchaseId': purchaseId});
  }

  /// Asks the server to settle a finished room (declares the remote winner).
  static Future<void> resolveBattle({required String roomId}) {
    return _call('resolveBattle', {'roomId': roomId});
  }
}
