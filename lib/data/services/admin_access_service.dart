import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Server-side admin authority, read from the Firebase **custom claim**
/// `admin: true` — the only thing `firestore.rules:isAdmin()` trusts.
///
/// Why this exists: the admin screens used to decide access from the
/// client-editable `users/{uid}.is_admin` profile field (and the app still
/// shows the panel on that flag). Firestore rules deliberately ignore that
/// field, so an admin whose claim is missing or stale sees the panel open but
/// every write fail with `permission-denied` ("cloud permission nei").
///
/// The mismatch is almost always one of:
///   1. The `setAdmin` callable was never run for this uid (no claim yet).
///   2. The claim was granted but the ID token is stale (claims arrive on
///      the next token refresh — force with [refresh]).
///   3. The rules deployed to production are not the v2 rules in this repo.
///
/// All reads are fail-soft: null/false means "unknown", never "not admin".
class AdminAccessService {
  AdminAccessService._();

  /// True when the current ID token carries `admin: true`.
  ///
  /// Pass `forceRefresh: true` after granting the claim so the fresh token
  /// (with the new claim) is fetched instead of the cached one.
  static Future<bool> hasAdminClaim({bool forceRefresh = false}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      final result = await user.getIdTokenResult(forceRefresh);
      final claims = result.claims ?? const <String, dynamic>{};
      return claims['admin'] == true;
    } catch (e) {
      debugPrint('AdminAccessService: claim check failed — $e');
      return false;
    }
  }

  /// Forces an ID-token refresh so a just-granted claim becomes visible.
  /// Returns true when the refreshed token carries the claim.
  static Future<bool> refresh() => hasAdminClaim(forceRefresh: true);

  /// Signed-in uid, or null when signed out / Firebase unavailable.
  static String? get uid {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// True when [error] looks like a Firestore rules denial rather than a
  /// network/offline failure.
  static bool isPermissionDenied(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('permission-denied') ||
        text.contains('permission denied') ||
        text.contains('insufficient permissions') ||
        text.contains('missing or insufficient');
  }

  /// Short Bengali-friendly explanation shown under admin write failures.
  static String explainWriteError(Object error) {
    if (isPermissionDenied(error)) {
      return 'Cloud permission nei: ei account-er admin claim Firestore-e '
          'deny hocche. Admin Dashboard-er banner theke status dekhe '
          'claim refresh koro (niche step দেওয়া আছে).';
    }
    return 'Cloud-e save kora jayni: $error';
  }
}
