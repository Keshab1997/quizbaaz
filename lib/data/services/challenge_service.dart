import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'firestore_query_specs.dart';

/// Firestore-backed challenge system for 1v1 battles.
///
/// ## Collection
///
/// ```text
/// battle_challenges/{challengeId}
/// {
///   from_uid: String,
///   from_name: String,
///   from_avatar: String,
///   from_avatar_url: String?,
///   from_level: int,
///   to_uid: String,
///   to_name: String,
///   to_avatar: String,
///   to_avatar_url: String?,
///   difficulty: String,
///   status: String,  // pending | accepted | rejected | expired | cancelled
///   created_at: int (ms),
///   expires_at: int (ms),
///   accepted_at: int (ms)?,
/// }
/// ```
///
/// ## Flow
///
/// ```
/// Sender: sends challenge → status = 'pending'
///   ↓
/// Receiver: sees notification → accepts/rejects
///   ↓  accept
/// Both clients: create deterministic battle room (existing logic)
///   ↓  reject/timeout
/// Sender: notified → can challenge someone else
/// ```
class ChallengeService {
  ChallengeService({FirebaseFirestore? firestore})
      : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;

  /// Resolved lazily so constructing the service never touches Firebase.
  /// Every method fails soft (returns null/false) when Firestore is down.
  FirebaseFirestore get _db =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  static const String collection = 'battle_challenges';
  static const Duration challengeExpiry = Duration(seconds: 30);

  // ----------------------------------------- Send Challenge ---------------

  /// Sends a battle challenge to another user.
  /// Returns the challenge ID, or null on failure.
  Future<String?> sendChallenge({
    required String fromUid,
    required String fromName,
    required String fromAvatar,
    String? fromAvatarUrl,
    int fromLevel = 1,
    required String targetUid,
    required String targetName,
    required String targetAvatar,
    String? targetAvatarUrl,
    String difficulty = 'normal',
  }) async {
    try {
      final check = await hasPendingChallenge(fromUid, targetUid);
      if (check.hasPending) {
        debugPrint('ChallengeService: pending challenge already exists');
        return null;
      }
      if (check.failed) {
        // A denied/failed duplicate check must not create a second pending
        // challenge for the same pair — the sender gets no challenge id and
        // the UI reports it instead of silently double-sending.
        debugPrint('ChallengeService: duplicate check failed – ${check.error}');
        return null;
      }

      final challengeId =
          'ch_${fromUid}_${targetUid}_${DateTime.now().millisecondsSinceEpoch}';
      final now = DateTime.now().millisecondsSinceEpoch;

      await _db.collection(collection).doc(challengeId).set({
        'from_uid': fromUid,
        'from_name': fromName,
        'from_avatar': fromAvatar,
        'from_avatar_url': fromAvatarUrl ?? '',
        'from_level': fromLevel,
        'to_uid': targetUid,
        'to_name': targetName,
        'to_avatar': targetAvatar,
        'to_avatar_url': targetAvatarUrl ?? '',
        'difficulty': difficulty,
        'status': 'pending',
        'created_at': now,
        'expires_at': now + challengeExpiry.inMilliseconds,
        // The same instant as a real Firestore timestamp: the TTL policy in
        // firestore.indexes.json deletes the document after this, so a
        // challenge whose owner never reopens the app cannot linger and
        // block the next one (R17). TTL needs a Timestamp, which is why the
        // int `expires_at` is kept for the client's own maths.
        'expires_at_ts': Timestamp.fromMillisecondsSinceEpoch(
          now + challengeExpiry.inMilliseconds,
        ),
      });

      return challengeId;
    } catch (e) {
      debugPrint('ChallengeService: sendChallenge failed – $e');
      return null;
    }
  }

  /// Accepts a pending challenge.
  Future<bool> acceptChallenge(String challengeId) async {
    try {
      await _db.collection(collection).doc(challengeId).update({
        'status': 'accepted',
        'accepted_at': DateTime.now().millisecondsSinceEpoch,
      });
      return true;
    } catch (e) {
      debugPrint('ChallengeService: acceptChallenge failed – $e');
      return false;
    }
  }

  /// Rejects a pending challenge.
  Future<bool> rejectChallenge(String challengeId) async {
    try {
      await _db.collection(collection).doc(challengeId).update({
        'status': 'rejected',
      });
      return true;
    } catch (e) {
      debugPrint('ChallengeService: rejectChallenge failed – $e');
      return false;
    }
  }

  /// Cancels a sent challenge (by the sender).
  Future<bool> cancelChallenge(String challengeId) async {
    try {
      await _db.collection(collection).doc(challengeId).update({
        'status': 'cancelled',
      });
      return true;
    } catch (e) {
      debugPrint('ChallengeService: cancelChallenge failed – $e');
      return false;
    }
  }

  // ----------------------------------- Watch Incoming Challenges ----------

  /// Watches for incoming challenges addressed to [myUid].
  Stream<ChallengeData?> watchIncomingChallenges(String myUid) {
    return FirestoreQuerySpecs.challengesIncoming
        .bind(equals: {'to_uid': myUid, 'status': 'pending'})
        .apply(_db.collection(collection))
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      return ChallengeData.fromDoc(snapshot.docs.first);
    }).handleError((e) {
      debugPrint('ChallengeService: watchIncoming – $e');
      return null;
    });
  }

  /// Watches for status changes on a specific challenge.
  Stream<ChallengeData?> watchChallengeStatus(String challengeId) {
    return _db
        .collection(collection)
        .doc(challengeId)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      return ChallengeData.fromDoc(snap);
    }).handleError((e) {
      debugPrint('ChallengeService: watchStatus – $e');
      return null;
    });
  }

  /// Watches for outgoing challenges sent by [myUid].
  Stream<ChallengeData?> watchOutgoingChallenge(String myUid) {
    return FirestoreQuerySpecs.challengesOutgoing
        .bind(
          equals: {'from_uid': myUid},
          whereIn: const {
            'status': ['pending', 'accepted'],
          },
        )
        .apply(_db.collection(collection))
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      return ChallengeData.fromDoc(snapshot.docs.first);
    }).handleError((e) {
      debugPrint('ChallengeService: watchOutgoing – $e');
      return null;
    });
  }

  // ----------------------------------------- Helpers --------------------

  /// Check if there's already a pending challenge between two users.
  ///
  /// Two participant-scoped queries instead of one collection-wide scan
  /// (R17): `allow list` on `battle_challenges` is participant-only, so a
  /// query that could return a stranger's challenge is denied by the rules —
  /// and the old scan was also filtered client-side, which rules cannot
  /// express. The result shape carries the failure instead of reporting a
  /// denied query as "no duplicate".
  Future<ChallengeCheck> hasPendingChallenge(
    String uidOne,
    String uidTwo,
  ) async {
    final col = _db.collection(collection);
    try {
      final mine = FirestoreQuerySpecs.challengesPendingFromTo
          .bind(equals: {
        'from_uid': uidOne,
        'to_uid': uidTwo,
        'status': 'pending',
      })
          .apply(col);
      final theirs = FirestoreQuerySpecs.challengesPendingFromTo
          .bind(equals: {
        'from_uid': uidTwo,
        'to_uid': uidOne,
        'status': 'pending',
      })
          .apply(col);

      final results = await Future.wait([mine.get(), theirs.get()]);
      final count = results.fold<int>(
        0,
        (total, snapshot) => total + snapshot.docs.length,
      );
      return ChallengeCheck(count: count);
    } catch (e) {
      debugPrint('ChallengeService: hasPendingChallenge failed – $e');
      return ChallengeCheck(count: 0, error: e);
    }
  }

  /// Global cleanup of stale challenges is **not** a client job any more.
  ///
  /// The old version ran `where('status', ==, 'pending')` over the whole
  /// collection and filtered by uid in Dart — a query the participant-only
  /// rules deny, and one that would have deleted other players' documents if
  /// the rules had been looser. Expiry is now handled by the TTL policy on
  /// `expires_at` (see `firestore.indexes.json` + docs/13) and by each player
  /// expiring their own challenges when they go offline:
  /// [expireMyChallenges].
  ///
  /// Kept as a no-op so older call sites keep compiling; it returns whether
  /// the caller should stop calling it (always true).
  Future<bool> cleanupExpiredChallenges() async {
    debugPrint(
      'ChallengeService: global cleanup moved to the TTL policy on '
      'battle_challenges.expires_at — nothing to do on the client.',
    );
    return true;
  }

  /// Mark this player's own pending challenges as expired (they are going
  /// offline, so nobody should keep waiting on them).
  ///
  /// Participant-scoped by construction: two queries, one per direction, each
  /// filtered by uid + status (R17).
  Future<void> expireMyChallenges(String myUid) async {
    final col = _db.collection(collection);
    try {
      final sent = FirestoreQuerySpecs.challengesPendingSent
          .bind(equals: {'from_uid': myUid, 'status': 'pending'})
          .apply(col);
      final received = FirestoreQuerySpecs.challengesPendingReceived
          .bind(equals: {'to_uid': myUid, 'status': 'pending'})
          .apply(col);

      final results = await Future.wait([sent.get(), received.get()]);
      final docs = [...results[0].docs, ...results[1].docs];
      if (docs.isEmpty) return;

      final batch = _db.batch();
      for (final doc in docs) {
        batch.update(doc.reference, {'status': 'expired'});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('ChallengeService: expireMyChallenges failed – $e');
    }
  }
}

/// Model for challenge data.
class ChallengeData {
  final String challengeId;
  final String fromUid;
  final String fromName;
  final String fromAvatar;
  final String? fromAvatarUrl;
  final int fromLevel;
  final String toUid;
  final String toName;
  final String toAvatar;
  final String? toAvatarUrl;
  final String difficulty;
  final String status;
  final int createdAtMs;
  final int expiresAtMs;
  final int? acceptedAtMs;

  const ChallengeData({
    required this.challengeId,
    required this.fromUid,
    required this.fromName,
    required this.fromAvatar,
    this.fromAvatarUrl,
    this.fromLevel = 1,
    required this.toUid,
    required this.toName,
    required this.toAvatar,
    this.toAvatarUrl,
    this.difficulty = 'normal',
    this.status = 'pending',
    this.createdAtMs = 0,
    this.expiresAtMs = 0,
    this.acceptedAtMs,
  });

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isRejected => status == 'rejected';
  bool get isExpired => status == 'expired';
  bool get isCancelled => status == 'cancelled';

  /// Seconds remaining before this challenge expires.
  int get secondsRemaining {
    if (!isPending) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = expiresAtMs - now;
    return remaining <= 0 ? 0 : (remaining / 1000).ceil();
  }

  bool get hasExpired {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now >= expiresAtMs;
  }

  /// Best avatar URL for the challenger.
  String get fromEffectiveAvatar =>
      (fromAvatarUrl != null && fromAvatarUrl!.isNotEmpty)
          ? fromAvatarUrl!
          : fromAvatar;

  factory ChallengeData.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ChallengeData(
      challengeId: doc.id,
      fromUid: data['from_uid']?.toString() ?? '',
      fromName: data['from_name']?.toString() ?? 'Player',
      fromAvatar: data['from_avatar']?.toString() ?? '',
      fromAvatarUrl: data['from_avatar_url']?.toString(),
      fromLevel: (data['from_level'] as num?)?.toInt() ?? 1,
      toUid: data['to_uid']?.toString() ?? '',
      toName: data['to_name']?.toString() ?? 'Player',
      toAvatar: data['to_avatar']?.toString() ?? '',
      toAvatarUrl: data['to_avatar_url']?.toString(),
      difficulty: data['difficulty']?.toString() ?? 'normal',
      status: data['status']?.toString() ?? 'pending',
      createdAtMs: (data['created_at'] as num?)?.toInt() ?? 0,
      expiresAtMs: (data['expires_at'] as num?)?.toInt() ?? 0,
      acceptedAtMs: (data['accepted_at'] as num?)?.toInt(),
    );
  }
}

/// Result of a duplicate-challenge check.
///
/// A denied query or a missing index used to look exactly like "no duplicate
/// exists" — the caller then created a second challenge for the same pair.
/// [error] keeps those two cases apart (R17).
class ChallengeCheck {
  final int count;
  final Object? error;

  const ChallengeCheck({required this.count, this.error});

  bool get hasPending => count > 0;
  bool get failed => error != null;
}
