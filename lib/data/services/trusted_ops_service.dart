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
///   * [setAdmin]          — grant/revoke the `admin` custom claim
///     (functions/src/admin.ts; bootstrap via INITIAL_ADMIN_UID secret).
///
/// The app stays offline-first: every call here is best-effort. When
/// Firebase is not initialised, the functions are not deployed, the network
/// is down, or the callable errors, we log and move on — the local flow is
/// never blocked by the trusted backend.
class TrustedOpsService {
  /// The region every trusted callable is deployed to (functions/src/options.ts).
  /// The client must call the same region or the call 404s.
  static const String region = 'asia-south1';

  static FirebaseFunctions? get _functions {
    if (Firebase.apps.isEmpty) return null;
    try {
      return FirebaseFunctions.instanceFor(region: region);
    } catch (e) {
      debugPrint('TrustedOps: functions unavailable – $e');
      return null;
    }
  }

  /// Calls a trusted function and returns its receipt (the callable's result
  /// data), or null when the backend is unavailable/unreachable.
  static Future<Map<String, dynamic>?> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final functions = _functions;
    if (functions == null) return null;
    try {
      final result = await functions.httpsCallable(name).call(data);
      final value = result.data;
      if (value is Map) return Map<String, dynamic>.from(value);
      return null;
    } catch (e) {
      // Expected while the functions are not deployed yet (or offline).
      debugPrint('TrustedOps: $name failed – $e');
      return null;
    }
  }

  /// Credits today's daily quiz result server-side (idempotent per day via
  /// `users/{uid}/daily_claims/{date}`).
  ///
  /// [answers] is the per-question breakdown the server re-scores against the
  /// published packet + question bank, so a tampered client cannot claim a
  /// perfect run. Each entry is `{question_id, selected}`, where `selected` is
  /// the chosen option's localized text (`{en, bn, hi}`) or null on a timeout.
  /// The option order is shuffled per device, so the selected *text* — not an
  /// index — is what the server can compare against the answer key.
  ///
  /// Receipt: `{ok, credited, coins, gems, xp, daily_streak}` or null offline.
  static Future<Map<String, dynamic>?> submitDailyResult({
    required String date,
    required int score,
    required int correct,
    required int total,
    required double timeSeconds,
    List<Map<String, dynamic>>? answers,
  }) {
    return _call('submitDailyResult', {
      'date': date,
      'score': score,
      'correct': correct,
      'total': total,
      'timeSeconds': timeSeconds,
      if (answers != null && answers.isNotEmpty) 'answers': answers,
    });
  }

  /// Runs the server-side purchase (idempotent per [purchaseId]).
  static Future<void> purchaseItem({
    required String itemId,
    required String purchaseId,
  }) async {
    await _call('purchaseItem', {'itemId': itemId, 'purchaseId': purchaseId});
  }

  /// Grants or revokes the `admin` custom claim for [uid] via the
  /// `setAdmin` callable. The caller must already hold the claim, or be the
  /// bootstrap account (INITIAL_ADMIN_UID). Returns true on success.
  ///
  /// Authority lives in the custom claim — never in a client-editable
  /// `is_admin` profile field (firestore.rules denies client writes to it).
  static Future<bool> setAdmin({
    required String uid,
    required bool admin,
  }) async {
    final receipt = await _call('setAdmin', {'uid': uid, 'admin': admin});
    return receipt != null && receipt['ok'] == true;
  }

  /// Asks the server to settle a finished room (declares the remote winner).
  ///
  /// [matchId] identifies the session inside the room, so a rematch reusing
  /// the same room id is settled as its own match (R11). Returns the receipt
  /// `{ok, winner, reason}` when the backend answered, null when it did not.
  static Future<Map<String, dynamic>?> resolveBattle({
    required String roomId,
    String? matchId,
  }) {
    return _call('resolveBattle', {
      'roomId': roomId,
      if (matchId != null && matchId.isNotEmpty) 'matchId': matchId,
    });
  }
}
