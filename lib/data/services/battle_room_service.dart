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

  /// One pass over the queue: returns the best candidate opponent, or null.
  ///
  /// * deletes this device's own stale entry before searching;
  /// * only entries with the same [difficulty] and fresh timestamp count;
  /// * returns the most recent entrant.
  Future<BattleQueueEntry?> findOpponent({
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
        return BattleQueueEntry.fromId(doc.id, data);
      }
    } catch (e) {
      debugPrint('BattleRoomService: findOpponent failed – $e');
    }
    return null;
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
    required String difficulty,
    required BattleRoomPlayerInfo me,
    required BattleRoomPlayerInfo opponent,
    required List<QuestionModel> questions,
    required int countdownUntilMs,
  }) async {
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await _db.collection(roomsCollection).doc(roomId).set({
        'difficulty': difficulty,
        'status': 'active',
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
  Future<void> finishRoom(String roomId, String winner) async {
    try {
      await _db
          .collection(roomsCollection)
          .doc(roomId)
          .set({
        'status': 'finished',
        'state': {'phase': 'finished'},
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('BattleRoomService: finishRoom failed – $e');
    }
    // Fire-and-forget: the server declares the authoritative remote winner.
    // Fail-soft (no-op when Firebase is off or functions are not deployed).
    TrustedOpsService.resolveBattle(roomId: roomId);
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
