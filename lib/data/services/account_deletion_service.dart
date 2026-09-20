import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'hive_service.dart';

/// Outcome of an account deletion attempt, mapped to friendly UI messages.
enum AccountDeletionStatus {
  /// The account is gone and every tracked collection was cleaned up.
  success,

  /// The account is gone, but at least one collection could not be cleaned up
  /// from the client. The follow-up is recorded server-side, so this is a
  /// "deleted, cleanup finishing" state — never a silent partial success.
  partial,

  /// The user cancelled the re-authentication step. Nothing was touched.
  canceled,

  /// The account could not be deleted. Local data is intact.
  failed,
}

/// Thrown by the re-auth step when the user backs out of the Google prompt.
class AccountDeletionCanceled implements Exception {
  const AccountDeletionCanceled();
}

/// What the remote cleanup managed to delete.
class AccountCleanupReport {
  final List<String> deleted;
  final List<String> pending;
  final bool followUpRecorded;

  const AccountCleanupReport({
    this.deleted = const [],
    this.pending = const [],
    this.followUpRecorded = false,
  });

  bool get isComplete => pending.isEmpty;

  AccountCleanupReport withFollowUp(bool recorded) => AccountCleanupReport(
        deleted: deleted,
        pending: pending,
        followUpRecorded: recorded,
      );

  @override
  String toString() =>
      'deleted=${deleted.length} pending=${pending.join(', ')}';
}

/// Result of a deletion attempt: the status plus what the cleanup did.
class AccountDeletionResult {
  final AccountDeletionStatus status;
  final AccountCleanupReport report;

  const AccountDeletionResult({
    required this.status,
    this.report = const AccountCleanupReport(),
  });

  bool get accountGone =>
      status == AccountDeletionStatus.success ||
      status == AccountDeletionStatus.partial;
}

/// Deletes every trace of a user: Firestore data, the Firebase Auth account
/// and (via [UserProvider.signOutLocal]) the local Hive profile.
///
/// ## Order matters (R15)
///
/// The old flow deleted remote data **first** and only then discovered that
/// Firebase wanted a recent sign-in — so cancelling the Google prompt left a
/// half-deleted account. Now:
///
///   1. **re-authenticate first** (when the account can do that). A cancel or
///      failure ends the attempt here, with every byte of data untouched;
///   2. write the local deletion tombstone, so a background sync tick cannot
///      re-upload the profile while the deletion runs;
///   3. delete the remote data, tracking what actually succeeded;
///   4. delete the Firebase Auth account;
///   5. if anything could not be cleaned up, record the follow-up in
///      `deletion_requests/{uid}` for the trusted backend and report
///      [AccountDeletionStatus.partial] instead of pretending everything went
///      away.
///
/// Per-collection failures never abort the flow (a collection the rules do not
/// allow to be deleted, e.g. an opponent's finished room, must not trap the
/// user inside an account they asked to delete) — but they are reported.
class AccountDeletionService {
  AccountDeletionService({
    FirebaseFirestore? firestore,
    Future<void> Function(String uid)? reAuthenticate,
    Future<AccountCleanupReport> Function(String uid)? remoteCleanup,
  })  : _firestoreOverride = firestore,
        _reAuthenticateOverride = reAuthenticate,
        _remoteCleanupOverride = remoteCleanup;

  /// The instance the UI uses.
  static final AccountDeletionService shared = AccountDeletionService();

  final FirebaseFirestore? _firestoreOverride;
  final Future<void> Function(String uid)? _reAuthenticateOverride;
  final Future<AccountCleanupReport> Function(String uid)? _remoteCleanupOverride;

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  FirebaseFirestore get _firestore => _firestoreOverride ?? _db;

  /// Number of writes per batch (Firestore caps a batch at 500).
  static const int _batchSize = 400;

  /// Hive meta key holding the uid whose deletion is in progress.
  static const String deletingUidKey = 'deletion_pending_uid';

  /// True when [uid] has a deletion in progress on this device (and therefore
  /// must not be pushed back to the server).
  static bool isDeletionPending(String uid) {
    final pending = HiveService.getMeta<String>(deletingUidKey);
    return pending != null && pending == uid;
  }

  /// Deletes the signed-in [user]'s account. Throws nothing — every failure
  /// maps to a status.
  Future<AccountDeletionResult> deleteAccount(User user) => deleteAccountWith(
        uid: user.uid,
        providerIds: [for (final p in user.providerData) p.providerId],
        deleteAuthUser: () async {
          // Apply the credential the re-auth prompt just produced (if any), so
          // `delete()` does not bounce back with `requires-recent-login` after
          // the remote data has already been removed.
          final credential = freshGoogleCredential;
          if (credential != null) {
            await user.reauthenticateWithCredential(credential);
          }
          await user.delete();
        },
      );

  /// The deletion itself, described by what it actually needs: the uid, the
  /// account's sign-in providers (to decide whether a re-authentication prompt
  /// is possible) and a callback that removes the auth user.
  ///
  /// [deleteAccount] is the thin wrapper the UI uses; keeping the core free of
  /// the Firebase `User` type is also what makes the **order** — re-auth, then
  /// remote cleanup, then the account itself — testable (R15).
  Future<AccountDeletionResult> deleteAccountWith({
    required String uid,
    required Future<void> Function() deleteAuthUser,
    List<String> providerIds = const [],
    String? reAuthProviderHint,
  }) async {
    // 1) Prove a recent sign-in BEFORE anything is removed. When this fails or
    //    is cancelled, the account and all of its data stay exactly as they
    //    were.
    try {
      await _confirmRecentSignIn(uid, providerIds, reAuthProviderHint);
    } on AccountDeletionCanceled {
      return const AccountDeletionResult(
        status: AccountDeletionStatus.canceled,
      );
    } catch (e) {
      debugPrint('AccountDeletion: re-auth failed – $e');
      return const AccountDeletionResult(status: AccountDeletionStatus.failed);
    }

    // 2) Local tombstone: the profile is gone as far as this device is
    //    concerned, so a sync tick cannot resurrect it.
    var report = const AccountCleanupReport();
    try {
      await HiveService.setMeta(deletingUidKey, uid);
    } catch (e) {
      debugPrint('AccountDeletion: could not write the local tombstone – $e');
    }

    // 3) Remote data (best-effort per collection, reported).
    try {
      report = await (_remoteCleanupOverride ?? _deleteRemoteData)(uid);
    } catch (e) {
      debugPrint('AccountDeletion: remote cleanup failed – $e');
      report = const AccountCleanupReport(pending: ['remote_cleanup']);
    }

    // 4) The account itself.
    try {
      await deleteAuthUser();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        // The recent-login proof from step 1 no longer held (or this account
        // type cannot re-auth). Nothing else is removed: the user keeps a
        // working, complete account.
        debugPrint('AccountDeletion: still requires recent login – $e');
        await _clearTombstone();
        return AccountDeletionResult(
          status: AccountDeletionStatus.failed,
          report: report,
        );
      }
      debugPrint('AccountDeletion: delete failed – $e');
      await _clearTombstone();
      return AccountDeletionResult(
        status: AccountDeletionStatus.failed,
        report: report,
      );
    } catch (e) {
      debugPrint('AccountDeletion: unexpected delete error – $e');
      await _clearTombstone();
      return AccountDeletionResult(
        status: AccountDeletionStatus.failed,
        report: report,
      );
    }

    // 5) Track whatever the client could not finish, then report the truth:
    //    "deleted" only when the cleanup really completed.
    if (!report.isComplete) {
      final recorded = await _recordDeletionRequest(uid, report);
      report = report.withFollowUp(recorded);
    }

    return AccountDeletionResult(
      status: report.isComplete
          ? AccountDeletionStatus.success
          : AccountDeletionStatus.partial,
      report: report,
    );
  }

  /// Clears the local tombstone (only used when the account survives).
  Future<void> _clearTombstone() async {
    try {
      await HiveService.setMeta(deletingUidKey, null);
    } catch (_) {}
  }

  /// Clears the tombstone after the caller wiped the local profile.
  static Future<void> clearTombstone() async {
    try {
      await HiveService.setMeta(deletingUidKey, null);
    } catch (_) {}
  }

  // ---------------------------------------------------------------- Remote --

  /// Deletes the user's data, collection by collection, and reports exactly
  /// what was skipped.
  Future<AccountCleanupReport> _deleteRemoteData(String uid) async {
    final deleted = <String>[];
    final pending = <String>[];

    Future<void> step(String name, Future<void> Function() action) async {
      try {
        await action();
        deleted.add(name);
      } catch (e) {
        debugPrint('AccountDeletion: $name skipped – $e');
        pending.add(name);
      }
    }

    // User profile + subcollections.
    final userDoc = _firestore.collection('users').doc(uid);
    await step('users/meta', () => _deleteCollection(userDoc.collection('meta')));
    await step('users/gifts', () => _deleteCollection(userDoc.collection('gifts')));
    await step(
      'users/quiz_history',
      () => _deleteCollection(userDoc.collection('quiz_history')),
    );
    await step(
      'users/purchase_history',
      () => _deleteCollection(userDoc.collection('purchase_history')),
    );
    await step('users/{uid}', () => userDoc.delete());

    // Leaderboard entries for every day: leaderboard/{date}/scores/{uid}.
    // `documentId()` in a collection-group query matches the document id
    // inside each collection (`scores/{uid}`), which is exactly the entry
    // being removed here.
    await step(
      'leaderboard/scores',
      () => _deleteQuery(
        _firestore
            .collectionGroup('scores')
            .where(FieldPath.documentId, isEqualTo: uid),
      ),
    );

    // Presence + battle queue (owned docs).
    await step(
      'online_users',
      () => _firestore.collection('online_users').doc(uid).delete(),
    );
    await step(
      'battle_queue',
      () => _firestore.collection('battle_queue').doc(uid).delete(),
    );

    // 1v1 challenges where the user is a participant (participant-only reads,
    // see firestore.rules).
    await step('battle_challenges', () async {
      final sent = await _firestore
          .collection('battle_challenges')
          .where('from_uid', isEqualTo: uid)
          .get();
      final received = await _firestore
          .collection('battle_challenges')
          .where('to_uid', isEqualTo: uid)
          .get();
      await _deleteDocs([...sent.docs, ...received.docs]);
    });

    // Battle rooms the user played in (rules may deny the delete — the
    // backend finishing job takes those over).
    await step('battle_rooms', () async {
      final asA = await _firestore
          .collection('battle_rooms')
          .where('players.a.uid', isEqualTo: uid)
          .get();
      final asB = await _firestore
          .collection('battle_rooms')
          .where('players.b.uid', isEqualTo: uid)
          .get();
      await _deleteDocs([...asA.docs, ...asB.docs]);
    });

    return AccountCleanupReport(deleted: deleted, pending: pending);
  }

  /// Hands the unfinished part of the cleanup to the trusted backend so the
  /// deletion is completed even when the client could not (or the app was
  /// closed straight after). Returns true when the request was recorded.
  Future<bool> _recordDeletionRequest(
    String uid,
    AccountCleanupReport report,
  ) async {
    try {
      await _firestore.collection('deletion_requests').doc(uid).set({
        'uid': uid,
        'requested_at': DateTime.now().millisecondsSinceEpoch,
        'pending_collections': report.pending,
        'deleted_collections': report.deleted,
        'status': 'pending',
      });
      return true;
    } catch (e) {
      debugPrint('AccountDeletion: could not record the follow-up – $e');
      return false;
    }
  }

  Future<void> _deleteCollection(
    CollectionReference<Map<String, dynamic>> ref,
  ) async {
    final snap = await ref.get();
    await _deleteDocs(snap.docs);
  }

  Future<void> _deleteQuery(Query<Map<String, dynamic>> query) async {
    final snap = await query.get();
    await _deleteDocs(snap.docs);
  }

  Future<void> _deleteDocs(List<QueryDocumentSnapshot> docs) async {
    for (var i = 0; i < docs.length; i += _batchSize) {
      final batch = _firestore.batch();
      for (final doc in docs.skip(i).take(_batchSize)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  // ------------------------------------------------------------- Re-auth --

  /// Firebase only lets the account owner delete after a recent sign-in.
  ///
  /// Google accounts refresh that with a fresh Google credential; accounts
  /// that cannot re-authenticate (anonymous/guest) simply carry on and let
  /// `user.delete()` decide.
  Future<void> _confirmRecentSignIn(
    String uid,
    List<String> providerIds,
    String? providerHint,
  ) async {
    final override = _reAuthenticateOverride;
    if (override != null) {
      await override(uid);
      return;
    }
    final providers = {...providerIds, if (providerHint != null) providerHint};
    if (!providers.contains('google.com')) return;
    await _reauthenticateWithGoogle();
  }

  Future<void> _reauthenticateWithGoogle() async {
    GoogleSignInAccount googleAccount;
    try {
      googleAccount = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        throw const AccountDeletionCanceled();
      }
      rethrow;
    }
    // The credential is applied by the caller of the flow: the re-auth prompt
    // runs before any data is touched, and the fresh sign-in is what lets
    // `user.delete()` succeed without `requires-recent-login`.
    _pendingGoogleIdToken = googleAccount.authentication.idToken;
  }

  /// The Google id token captured by the most recent re-authentication prompt.
  String? _pendingGoogleIdToken;

  /// Fresh Google credential for the account being deleted, when the user
  /// completed the re-auth prompt. Null for non-Google accounts.
  AuthCredential? get freshGoogleCredential {
    final token = _pendingGoogleIdToken;
    if (token == null || token.isEmpty) return null;
    return GoogleAuthProvider.credential(idToken: token);
  }
}
