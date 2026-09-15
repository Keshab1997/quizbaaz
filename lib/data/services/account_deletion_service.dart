import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Outcome of an account deletion attempt, mapped to friendly UI messages.
enum AccountDeletionStatus {
  /// Everything (remote data + Firebase auth account) was deleted.
  success,

  /// The user cancelled the Google re-auth step.
  canceled,

  /// The account could not be deleted (e.g. re-auth failed / network).
  failed,
}

/// Deletes every trace of a user: Firestore data, the Firebase Auth account
/// and (via [UserProvider.signOutLocal]) the local Hive profile.
///
/// Order matters:
///   1. Remote data is removed first so nothing is left behind if signing out
///      afterwards is interrupted.
///   2. Local data is cleared by the caller so a later `flutter` sync cannot
///      resurrect the remote profile.
///   3. The Firebase Auth account is deleted last, re-authenticating with
///      Google when Firebase demands a recent sign-in.
///
/// Every Firestore step is best-effort: a collection the security rules do not
/// allow to be deleted (e.g. `battle_rooms`) is skipped instead of aborting
/// the whole flow.
class AccountDeletionService {
  AccountDeletionService._();

  /// Resolved lazily so referencing the class never touches Firebase.
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Number of writes per batch (Firestore caps a batch at 500).
  static const int _batchSize = 400;

  /// Deletes the signed-in [user]'s account. Throws nothing — failures map to
  /// [AccountDeletionStatus].
  static Future<AccountDeletionStatus> deleteAccount(User user) async {
    final uid = user.uid;

    // 1) Remote data (best-effort per collection).
    await _deleteRemoteData(uid);

    // 2) Firebase Auth account (may require a recent sign-in).
    try {
      await user.delete();
      return AccountDeletionStatus.success;
    } on FirebaseAuthException catch (e) {
      if (e.code != 'requires-recent-login') {
        debugPrint('AccountDeletion: delete failed – $e');
        return AccountDeletionStatus.failed;
      }
      // Re-authenticate with Google and retry once.
      try {
        await _reauthenticate(user);
        await user.delete();
        return AccountDeletionStatus.success;
      } on GoogleSignInException catch (e2) {
        if (e2.code == GoogleSignInExceptionCode.canceled ||
            e2.code == GoogleSignInExceptionCode.interrupted) {
          return AccountDeletionStatus.canceled;
        }
        debugPrint('AccountDeletion: google re-auth failed – $e2');
        return AccountDeletionStatus.failed;
      } on FirebaseAuthException catch (e2) {
        debugPrint('AccountDeletion: re-auth delete failed – $e2');
        return AccountDeletionStatus.failed;
      } catch (e2) {
        debugPrint('AccountDeletion: re-auth error – $e2');
        return AccountDeletionStatus.failed;
      }
    } catch (e) {
      debugPrint('AccountDeletion: unexpected error – $e');
      return AccountDeletionStatus.failed;
    }
  }

  // ---------------------------------------------------------------- Remote --

  static Future<void> _deleteRemoteData(String uid) async {
    // User profile + subcollections.
    final userDoc = _db.collection('users').doc(uid);
    await _deleteCollection(userDoc.collection('meta'));
    await _deleteCollection(userDoc.collection('gifts'));
    await _deleteCollection(userDoc.collection('quiz_history'));
    await _deleteCollection(userDoc.collection('purchase_history'));
    try {
      await userDoc.delete();
    } catch (e) {
      debugPrint('AccountDeletion: user doc delete skipped – $e');
    }

    // Leaderboard entries for every day: leaderboard/{date}/scores/{uid}.
    try {
      await _deleteQuery(
        _db.collectionGroup('scores').where(FieldPath.documentId,
            isEqualTo: uid),
      );
    } catch (e) {
      debugPrint('AccountDeletion: leaderboard sweep skipped – $e');
    }

    // Presence + battle queue (owned docs, owner-scoped rule).
    try {
      await _db.collection('online_users').doc(uid).delete();
    } catch (e) {
      debugPrint('AccountDeletion: online_users delete skipped – $e');
    }
    try {
      await _db.collection('battle_queue').doc(uid).delete();
    } catch (e) {
      debugPrint('AccountDeletion: battle_queue delete skipped – $e');
    }

    // 1v1 challenges where the user is a participant.
    try {
      final sent = await _db
          .collection('battle_challenges')
          .where('from_uid', isEqualTo: uid)
          .get();
      final received = await _db
          .collection('battle_challenges')
          .where('to_uid', isEqualTo: uid)
          .get();
      await _deleteDocs([...sent.docs, ...received.docs]);
    } catch (e) {
      debugPrint('AccountDeletion: battle_challenges sweep skipped – $e');
    }

    // Battle rooms the user played in (rules may deny delete — best effort).
    try {
      final asA = await _db
          .collection('battle_rooms')
          .where('players.a.uid', isEqualTo: uid)
          .get();
      final asB = await _db
          .collection('battle_rooms')
          .where('players.b.uid', isEqualTo: uid)
          .get();
      await _deleteDocs([...asA.docs, ...asB.docs]);
    } catch (e) {
      debugPrint('AccountDeletion: battle_rooms sweep skipped – $e');
    }
  }

  static Future<void> _deleteCollection(
      CollectionReference<Map<String, dynamic>> ref) async {
    try {
      final snap = await ref.get();
      await _deleteDocs(snap.docs);
    } catch (e) {
      debugPrint('AccountDeletion: collection ${ref.path} skipped – $e');
    }
  }

  static Future<void> _deleteQuery(Query<Map<String, dynamic>> query) async {
    try {
      final snap = await query.get();
      await _deleteDocs(snap.docs);
    } catch (e) {
      debugPrint('AccountDeletion: query skipped – $e');
    }
  }

  static Future<void> _deleteDocs(List<QueryDocumentSnapshot> docs) async {
    for (var i = 0; i < docs.length; i += _batchSize) {
      final batch = _db.batch();
      for (final doc in docs.skip(i).take(_batchSize)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  // ------------------------------------------------------------- Re-auth --

  /// Firebase only lets the account owner delete after a recent sign-in;
  /// Google users refresh that with a fresh credential.
  static Future<void> _reauthenticate(User user) async {
    final googleAccount = await GoogleSignIn.instance.authenticate();
    final auth = googleAccount.authentication;
    final credential = GoogleAuthProvider.credential(idToken: auth.idToken);
    await user.reauthenticateWithCredential(credential);
  }
}
