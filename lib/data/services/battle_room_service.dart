import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/battle_room.dart';
import '../models/question_model.dart';
import 'trusted_ops_service.dart';

/// Firestore-backed matchmaking + live room sync for 1-vs-1 battles.
///
/// ## Collections
///
/// ```text
/// battle_queue/{uid}      presence doc: who is searching right now
/// battle_rooms/{roomId}   the match state, roomId = 'room_<a>_<b>' (sorted)
/// ```
///
/// ## The two-client convergence trick
///
/// Both players derive the same deterministic room id from their uids, so two
/// clients racing to match never create two rooms: the lexicographically
/// smaller uid *creates* the document (and writes the questions + the
/// countdown state); the other client simply reads it when it appears.
///
/// Every client writes **only its own `players.<side>` fields** (plus
/// idempotent state transitions), so concurrent writes never clobber the
/// opponent — mirroring the app rule that Firestore is a mirror, never the
/// source of truth for a client's own state.
///
/// Everything fails soft: when Firestore is unreachable the methods return
/// `false` / empty results and the provider falls back to a bot match.
class BattleRoomService {
  BattleRoomService({FirebaseFirestore? firestore})
      : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;

  /// Resolved lazily so constructing the service never touches Firebase.
  /// Every method fails soft and the provider falls back to a bot match.
  FirebaseFirestore get _db =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  static const String queueCollection = 'battle_queue';
  static const String roomsCollection = 'battle_rooms';

  /// A queue entry older than this is treated as gone.
  static const Duration queueStaleAfter = Duration(seconds: 45);

  /// An opponent not seen for this long during a match forfeits.
  static const Duration forfeitAfter = Duration(seconds: 20);

  // ------------------------------------------------------------- queue --

  Future<void> joinQueue({
    required String uid,
    required String name,
    required String avatar,
    required String difficulty,
  }) async {
    try {
      await _db.collection(queueCollection).doc(uid).set({
        'name': name,
        'avatar': avatar,
        'difficulty': difficulty,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('BattleRoomService: joinQueue failed – $e');
    }
  }

  Future<void> leaveQueue(String uid) async {
    try {
      await _db.collection(queueCollection).doc(uid).delete();
    } catch (e) {
      debugPrint('BattleRoomService: leaveQueue failed – $e');
    }
  }

  /// One pass over the queue: the best candidate opponent, an empty result, or
  /// a failure.
  ///
  /// Returns a [QueueSearchResult] instead of a bare `null` so a denied query
  /// or a missing composite index can never be reported to the player as
  /// "no opponent online" (R17). The caller decides what to do with a
  /// [QueueSearchError]:
  ///
  /// * [QueueSearchError.configuration] — `permission-denied`,
  ///   `failed-precondition` (missing index) or `unauthenticated`: a
  ///   deployment problem, surfaced to the player instead of hiding behind a
  ///   bot match.
  /// * [QueueSearchError.transient] — offline/timeout: the app keeps its
  ///   offline promise and falls back to a bot match.
  Future<QueueSearchResult> findOpponent({
    required String myUid,
    required String difficulty,
  }) async {
    try {
      final cutoff = DateTime.now()
              .subtract(queueStaleAfter)
              .millisecondsSinceEpoch;

      final snapshot = await _db
          .collection(queueCollection)
          .where('difficulty', isEqualTo: difficulty)
          .where('created_at', isGreaterThan: cutoff)
          .orderBy('created_at', descending: true)
          .limit(15)
          .get();

      for (final doc in snapshot.docs) {
        if (doc.id == myUid) continue;
        final data = doc.data();
        if (data.isEmpty) continue;
        return QueueSearchResult.found(BattleQueueEntry.fromId(doc.id, data));
      }
      return QueueSearchResult.empty();
    } catch (e) {
      debugPrint('BattleRoomService: findOpponent failed – $e');
      return QueueSearchResult.failure(e);
    }
  }

  /// Atomically claims [opponentUid] as this player's match partner.
  ///
  /// Runs the room check, the room creation and the queue cleanup in one
  /// Firestore transaction, so two clients racing for the same opponent (or
  /// three players arriving at once) can never create two rooms for the same
  /// pair: the first transaction wins, the loser sees the room already exists
  /// and just reads it (R11).
  ///
  /// Returns the [QueueClaimOutcome] describing what happened.
  Future<QueueClaimOutcome> claimOpponent({
    required String myUid,
    required String opponentUid,
    required String difficulty,
    required String matchId,
    required BattleRoomPlayerInfo me,
    required BattleRoomPlayerInfo opponent,
    required List<QuestionModel> questions,
    required int countdownUntilMs,
  }) async {
    final roomId = roomIdFor(myUid, opponentUid);
    final roomRef = _db.collection(roomsCollection).doc(roomId);
    try {
      return await _db.runTransaction<QueueClaimOutcome>((tx) async {
        final existing = await tx.get(roomRef);
        if (existing.exists) {
          final data = existing.data() ?? const <String, dynamic>{};
          final createdAt =
              (data['created_at'] as num?)?.toInt() ?? 0;
          final isStale = createdAt > 0 &&
              DateTime.now().millisecondsSinceEpoch - createdAt >
                  const Duration(minutes: 10).inMilliseconds;
          if (!isStale) {
            return QueueClaimOutcome.alreadyExists(
              roomId: roomId,
              matchId: data['match_id']?.toString() ?? '',
              status: BattleRoomStatus.parse(data['status']),
            );
          }
          // A leftover room from an old match is replaced, not joined.
          tx.delete(roomRef);
        }

        final opponentDoc =
            await tx.get(_db.collection(queueCollection).doc(opponentUid));
        if (!opponentDoc.exists) {
          return QueueClaimOutcome.opponentGone(roomId: roomId);
        }

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        tx.set(roomRef, {
          'match_id': matchId,
          'difficulty': difficulty,
          'status': BattleRoomStatus.created.name,
          'created_at': nowMs,
          'questions': [for (final q in questions) q.toJson()],
          'state': {
            'phase': 'countdown',
            'q_index': 0,
            'countdown_until': countdownUntilMs,
            'question_until': 0,
            'reveal_until': 0,
            'next_q': 0,
          },
          'players': {
            'a': BattleRoomPlayer(
              uid: me.uid,
              name: me.name,
              avatar: me.avatar,
              lastSeenMs: nowMs,
            ).toJson(),
            'b': BattleRoomPlayer(
              uid: opponent.uid,
              name: opponent.name,
              avatar: opponent.avatar,
              lastSeenMs: nowMs,
            ).toJson(),
          },
          'winner': null,
        });

        // Atomic reservation: both queue entries go away in the same commit,
        // so nobody else can claim either player for another room.
        tx.delete(_db.collection(queueCollection).doc(myUid));
        tx.delete(_db.collection(queueCollection).doc(opponentUid));
        return QueueClaimOutcome.created(roomId: roomId, matchId: matchId);
      });
    } catch (e) {
      debugPrint('BattleRoomService: claimOpponent failed – $e');
      return QueueClaimOutcome.failure(roomId: roomId, error: e);
    }
  }

  // ------------------------------------------------------------- room --

  /// Deterministic room id for a pair, e.g. `room_aaa_bbb`.
  static String roomIdFor(String uidA, String uidB) {
    final ids = [uidA, uidB]..sort();
    return 'room_${ids[0]}_${ids[1]}';
  }

  /// Creates the room the caller is the creator of (lexicographically smaller
  /// uid). Writes players, questions and the countdown state in one go.
  Future<void> createRoom({
    required String roomId,
    required String matchId,
    required String difficulty,
    required BattleRoomPlayerInfo me,
    required BattleRoomPlayerInfo opponent,
    required List<QuestionModel> questions,
    required int countdownUntilMs,
  }) async {
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await _db.collection(roomsCollection).doc(roomId).set({
        'match_id': matchId,
        'difficulty': difficulty,
        'status': BattleRoomStatus.created.name,
        'created_at': nowMs,
        'questions': [for (final q in questions) q.toJson()],
        'state': {
          'phase': 'countdown',
          'q_index': 0,
          'countdown_until': countdownUntilMs,
          'question_until': 0,
          'reveal_until': 0,
          'next_q': 0,
        },
        'players': {
          'a': BattleRoomPlayer(
            uid: me.uid,
            name: me.name,
            avatar: me.avatar,
            lastSeenMs: nowMs,
          ).toJson(),
          'b': BattleRoomPlayer(
            uid: opponent.uid,
            name: opponent.name,
            avatar: opponent.avatar,
            lastSeenMs: nowMs,
          ).toJson(),
        },
        'winner': null,
      });
    } catch (e) {
      // Already-exists is fine: the other client may have won the race with
      // the same deterministic id — the caller just reads the room instead.
      debugPrint('BattleRoomService: createRoom failed – $e');
    }
  }

  /// Streams one room document. Never throws — errors surface as an empty
  /// snapshot via a null-mapped emit.
  Stream<BattleRoomData?> watchRoom(String roomId) {
    return _db
        .collection(roomsCollection)
        .doc(roomId)
        .snapshots()
        .map((snap) {
          if (!snap.exists) return null;
          return BattleRoomData.fromJson(snap.id, snap.data() ?? {});
        })
        .handleError((e) => debugPrint('BattleRoomService: watchRoom – $e'));
  }

  /// One-shot read of a room (used right after creating it).
  Future<BattleRoomData?> readRoom(String roomId) async {
    try {
      final snap = await _db.collection(roomsCollection).doc(roomId).get();
      if (!snap.exists) return null;
      return BattleRoomData.fromJson(snap.id, snap.data() ?? {});
    } catch (e) {
      debugPrint('BattleRoomService: readRoom failed – $e');
      return null;
    }
  }

  /// Writes only the caller's `players.<side>` fields (merge).
  Future<bool> updateMyPlayer(String roomId, String side, Map<String, dynamic> fields) async {
    try {
      await _db
          .collection(roomsCollection)
          .doc(roomId)
          .set({'players': {side: fields}}, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('BattleRoomService: updateMyPlayer failed – $e');
      return false;
    }
  }

  /// Writes one answer for [side] using the nested `answers` map.
  ///
  /// Returns true when the write landed. Never throws — the caller keeps its
  /// local state and the next heartbeat repairs the room (R11).
  Future<bool> writeMyAnswer({
    required String roomId,
    required String side,
    required int questionIndex,
    required BattleAnswer answer,
    Map<String, dynamic> extraFields = const {},
  }) async {
    try {
      await _db.collection(roomsCollection).doc(roomId).set(
        <String, dynamic>{
          'players': <String, dynamic>{
            side: <String, dynamic>{
              ...extraFields,
              // Nested map, never a dotted path: `'answers.$index'` in a merge
              // write lands as a field literally named `answers.0`, which the
              // nested-map reader can never see (R11).
              'answers': <String, dynamic>{
                '$questionIndex': answer.toJson(),
              },
            },
          },
        },
        SetOptions(merge: true),
      );
      return true;
    } catch (e) {
      debugPrint('BattleRoomService: writeMyAnswer failed – $e');
      return false;
    }
  }

  /// Marks this client as attached to the room (`players.<side>.attached`).
  /// Written once per match; both flags set means the room is `ready`.
  Future<bool> attachPlayer(String roomId, String side) =>
      updateMyPlayer(roomId, side, {'attached': true});

  /// The room is really being played now (the first question started).
  Future<void> markActive(String roomId) async {
    try {
      await _db.collection(roomsCollection).doc(roomId).set(
        {'status': BattleRoomStatus.active.name},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('BattleRoomService: markActive failed – $e');
    }
  }

  /// Marks both players attached (creator only) so the room reads `ready`.
  Future<void> markReady(String roomId) async {
    try {
      await _db.collection(roomsCollection).doc(roomId).set(
        {
          'status': BattleRoomStatus.ready.name,
          'state': {'phase': 'countdown'},
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('BattleRoomService: markReady failed – $e');
    }
  }

  /// Marks the room abandoned by [side] **at the top level**.
  ///
  /// The reader (`BattleRoomData.abandoned` / `abandonedBy`) looks at the
  /// document's own fields, so a forfeit written only into the nested `state`
  /// map used to be invisible to the opponent's client — it saw a finished
  /// room with no winner instead of an instant forfeit win (R11).
  Future<void> abandonRoom(String roomId, String side) async {
    try {
      await _db.collection(roomsCollection).doc(roomId).set({
        'status': BattleRoomStatus.abandoned.name,
        'abandoned': true,
        'abandoned_by': side,
        'state': {'phase': 'finished'},
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('BattleRoomService: abandonRoom failed – $e');
    }
  }

  /// Idempotent state patch: merges [state] into the room's `state` map.
  ///
  /// Transitions are re-appliable by design (same values, same timestamps the
  /// writer computed), so a lost update from a duplicate writer is harmless.
  Future<void> advanceState(String roomId, Map<String, dynamic> state) async {
    try {
      await _db
          .collection(roomsCollection)
          .doc(roomId)
          .set({'state': state}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('BattleRoomService: advanceState failed – $e');
    }
  }

  /// Marks the room finished (remote) — the [winner] is kept **local**.
  ///
  /// P0 (R02): `firestore.rules` freezes the room's `winner` field against
  /// client writes; a tampered client must not be able to declare a remote
  /// winner. The authoritative settlement is the `resolveBattle` callable
  /// (functions/src/battle.ts), which re-reads the room and writes
  /// `status`/`winner`/`resolved` with the Admin SDK. Call
  /// `TrustedOpsService.resolveBattle` right after this for online players.
  Future<void> finishRoom(
    String roomId,
    String winner, {
    String? matchId,
  }) async {
    try {
      await _db
          .collection(roomsCollection)
          .doc(roomId)
          .set({
        'status': BattleRoomStatus.finished.name,
        'state': {'phase': 'finished'},
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('BattleRoomService: finishRoom failed – $e');
    }
    // Fire-and-forget: the server declares the authoritative remote winner and
    // returns a receipt (`ok`, `winner`, `reason`) for this match. Fail-soft
    // (no-op when Firebase is off or functions are not deployed).
    TrustedOpsService.resolveBattle(roomId: roomId, matchId: matchId);
  }
}

/// Static info about a player, used when creating a room.
class BattleRoomPlayerInfo {
  final String uid;
  final String name;
  final String avatar;

  const BattleRoomPlayerInfo({
    required this.uid,
    required this.name,
    required this.avatar,
  });
}

/// Why [BattleRoomService.findOpponent] failed.
enum QueueSearchError {
  /// `permission-denied` / `failed-precondition` (missing composite index) /
  /// `unauthenticated` — a deployment problem, not "nobody is online".
  configuration,

  /// Offline, timeout or any other temporary error.
  transient,
}

/// Outcome of one matchmaking pass.
class QueueSearchResult {
  final BattleQueueEntry? entry;
  final QueueSearchError? error;
  final Object? cause;

  const QueueSearchResult._(this.entry, this.error, this.cause);

  factory QueueSearchResult.found(BattleQueueEntry entry) =>
      QueueSearchResult._(entry, null, null);

  factory QueueSearchResult.empty() =>
      const QueueSearchResult._(null, null, null);

  factory QueueSearchResult.failure(Object cause) {
    final text = cause.toString().toLowerCase();
    final isConfiguration = text.contains('permission-denied') ||
        text.contains('permission_denied') ||
        text.contains('failed-precondition') ||
        text.contains('failed_precondition') ||
        text.contains('requires an index') ||
        text.contains('unauthenticated');
    return QueueSearchResult._(
      null,
      isConfiguration
          ? QueueSearchError.configuration
          : QueueSearchError.transient,
      cause,
    );
  }

  bool get hasOpponent => entry != null;
  bool get isEmpty => entry == null && error == null;
  bool get isConfigurationError => error == QueueSearchError.configuration;
}

/// What happened when a player tried to claim an opponent atomically.
enum QueueClaimStatus {
  /// This client created the room; it publishes the questions/countdown.
  created,

  /// The room already existed (the opponent got there first) — read it.
  alreadyExists,

  /// The opponent left the queue before the claim landed.
  opponentGone,

  /// Firestore refused the transaction (rules, index, offline).
  failed,
}

class QueueClaimOutcome {
  final QueueClaimStatus status;
  final String roomId;
  final String matchId;
  final BattleRoomStatus? roomStatus;
  final Object? error;

  const QueueClaimOutcome._({
    required this.status,
    required this.roomId,
    this.matchId = '',
    this.roomStatus,
    this.error,
  });

  factory QueueClaimOutcome.created({
    required String roomId,
    required String matchId,
  }) =>
      QueueClaimOutcome._(
        status: QueueClaimStatus.created,
        roomId: roomId,
        matchId: matchId,
      );

  factory QueueClaimOutcome.alreadyExists({
    required String roomId,
    required String matchId,
    required BattleRoomStatus status,
  }) =>
      QueueClaimOutcome._(
        status: QueueClaimStatus.alreadyExists,
        roomId: roomId,
        matchId: matchId,
        roomStatus: status,
      );

  factory QueueClaimOutcome.opponentGone({required String roomId}) =>
      QueueClaimOutcome._(
        status: QueueClaimStatus.opponentGone,
        roomId: roomId,
      );

  factory QueueClaimOutcome.failure({
    required String roomId,
    required Object error,
  }) =>
      QueueClaimOutcome._(
        status: QueueClaimStatus.failed,
        roomId: roomId,
        error: error,
      );

  bool get isCreated => status == QueueClaimStatus.created;
}
