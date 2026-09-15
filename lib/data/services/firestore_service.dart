import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/app_config.dart';
import '../models/user_model.dart';
import '../models/user_stats.dart';

/// Firestore persistence layer — the **remote mirror** of Hive.
///
/// Nothing in the UI calls this directly. `SyncService` decides when to push
/// or pull, and every method returns a success flag so failed writes can be
/// queued in Hive and retried later.
///
/// Layout
/// ```
/// users/{uid}                       -> profile
/// users/{uid}/meta/stats            -> UserStats
/// users/{uid}/gifts/{giftId}        -> GiftClaim
/// leaderboard/{yyyy-MM-dd}/scores/{uid}
/// champions/{yyyy-MM-dd}/winners/{uid}
/// config/app                        -> AppConfig
/// ```
class FirestoreService {
  static const _users = 'users';
  static const _leaderboard = 'leaderboard';
  static const _champions = 'champions';
  static const _config = 'config';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// True when Firebase actually initialised — every call short-circuits
  /// when it did not, so the app stays fully usable offline.
  static bool get isReady => Firebase.apps.isNotEmpty;

  static String dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  // ---------------------------------------------------------- User CRUD --

  /// Saves (upserts) the user document's **client-editable profile fields
  /// only** and returns true on success.
  ///
  /// P0 (R02): the client must never write wallet/competitive/admin state
  /// (`coins`, `gems`, `xp`, `level`, streak, inventory, `is_admin`). Those
  /// fields are owned by the trusted backend (`/functions` — Admin SDK
  /// bypasses the rules) and by the rules' sensitive-key deny. Sending them
  /// would make the whole write fail under the current `firestore.rules`.
  static Future<bool> saveUser(UserModel user) async {
    if (!isReady || user.userId.isEmpty) return false;
    try {
      await _db.collection(_users).doc(user.userId).set(
            {...user.profileToJson(), 'updated_at': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
      return true;
    } catch (e) {
      debugPrint('Firestore: saveUser error – $e');
      return false;
    }
  }

  /// Loads a user document by [userId], or null.
  static Future<UserModel?> loadUser(String userId) async {
    if (!isReady || userId.isEmpty) return null;
    try {
      final doc = await _db.collection(_users).doc(userId).get();
      final data = doc.data();
      if (!doc.exists || data == null) return null;
      return UserModel.fromJson(data);
    } catch (e) {
      debugPrint('Firestore: loadUser error – $e');
      return null;
    }
  }

  static Future<bool> updateUserFields(
    String userId,
    Map<String, dynamic> fields,
  ) async {
    if (!isReady || userId.isEmpty) return false;
    try {
      await _db.collection(_users).doc(userId).set(
            fields,
            SetOptions(merge: true),
          );
      return true;
    } catch (e) {
      debugPrint('Firestore: updateUserFields error – $e');
      return false;
    }
  }

  static Future<bool> deleteUser(String userId) async {
    if (!isReady || userId.isEmpty) return false;
    try {
      await _db.collection(_users).doc(userId).delete();
      return true;
    } catch (e) {
      debugPrint('Firestore: deleteUser error – $e');
      return false;
    }
  }

  // --------------------------------------------------------------- Stats --

  static Future<bool> saveStats(String userId, UserStats stats) async {
    if (!isReady || userId.isEmpty) return false;
    try {
      await _db
          .collection(_users)
          .doc(userId)
          .collection('meta')
          .doc('stats')
          .set(
            {...stats.toJson(), 'updated_at': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
      return true;
    } catch (e) {
      debugPrint('Firestore: saveStats error – $e');
      return false;
    }
  }

  static Future<UserStats?> loadStats(String userId) async {
    if (!isReady || userId.isEmpty) return null;
    try {
      final doc = await _db
          .collection(_users)
          .doc(userId)
          .collection('meta')
          .doc('stats')
          .get();
      final data = doc.data();
      if (!doc.exists || data == null) return null;
      return UserStats.fromJson(data);
    } catch (e) {
      debugPrint('Firestore: loadStats error – $e');
      return null;
    }
  }

  // --------------------------------------------------------- Leaderboard --

  /// Updates or creates the daily leaderboard entry for this user.
  static Future<bool> saveLeaderboardEntry({
    required String userId,
    required String username,
    required String fullName,
    required String avatarPath,
    String? nameEffect,
    required int score,
    required double timeSeconds,
    required int streak,
    required DateTime date,
  }) async {
    if (!isReady || userId.isEmpty) return false;
    try {
      await _db
          .collection(_leaderboard)
          .doc(dateKey(date))
          .collection('scores')
          .doc(userId)
          .set({
        'user_id': userId,
        'username': username,
        'name': fullName,
        'avatar_path': avatarPath,
        'name_effect': nameEffect ?? '',
        'score': score,
        'time_seconds': timeSeconds,
        'streak': streak,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('Firestore: saveLeaderboardEntry error – $e');
      return false;
    }
  }

  /// Reads this user's own leaderboard entry for [date], or null.
  ///
  /// Used by the daily leaderboard self-heal: the player's Hive per-day best
  /// is the source of truth, and the entry in Firestore is corrected when it
  /// no longer matches (e.g. a phantom "legacy" score left by an old build).
  static Future<Map<String, dynamic>?> getLeaderboardEntry(
    String userId,
    DateTime date,
  ) async {
    if (!isReady || userId.isEmpty) return null;
    try {
      final doc = await _db
          .collection(_leaderboard)
          .doc(dateKey(date))
          .collection('scores')
          .doc(userId)
          .get();
      if (!doc.exists) return null;
      return Map<String, dynamic>.from(doc.data()!)
        ..remove('timestamp');
    } catch (e) {
      debugPrint('Firestore: getLeaderboardEntry error – $e');
      return null;
    }
  }

  /// Fetches the top N scores for a given date, already rank-ordered.
  static Future<List<Map<String, dynamic>>> getLeaderboard(
    DateTime date, {
    int limit = 50,
  }) async {
    if (!isReady) return const [];
    try {
      final snapshot = await _db
          .collection(_leaderboard)
          .doc(dateKey(date))
          .collection('scores')
          .orderBy('score', descending: true)
          .orderBy('time_seconds', descending: false)
          .limit(limit)
          .get();

      final rows = <Map<String, dynamic>>[];
      for (var i = 0; i < snapshot.docs.length; i++) {
        final data = Map<String, dynamic>.from(snapshot.docs[i].data());
        data['rank'] = i + 1;
        data.remove('timestamp'); // not JSON-encodable for the Hive cache
        rows.add(data);
      }
      return rows;
    } catch (e) {
      debugPrint('Firestore: getLeaderboard error – $e');
      return const [];
    }
  }

  // ----------------------------------------------------------- Champions --

  /// Published champions for [date]. Falls back to deriving them from that
  /// day's leaderboard when an admin has not published anything yet.
  static Future<List<Map<String, dynamic>>> getChampions(
    DateTime date, {
    int limit = 10,
  }) async {
    if (!isReady) return const [];
    try {
      final snapshot = await _db
          .collection(_champions)
          .doc(dateKey(date))
          .collection('winners')
          .orderBy('rank')
          .limit(limit)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs
            .map((d) => Map<String, dynamic>.from(d.data())..remove('timestamp'))
            .toList();
      }

      // Derive from the leaderboard so the screen still shows real winners.
      final scores = await getLeaderboard(date, limit: limit);
      return scores
          .map((row) => {
                'rank': row['rank'],
                'user_id': row['user_id'],
                'name': row['name'] ?? row['username'],
                'username': row['username'],
                'avatar_path': row['avatar_path'],
                'name_effect': row['name_effect'] ?? '',
                'score': row['score'],
                'time_seconds': row['time_seconds'],
                'gift_name': '',
                'gift_icon': '',
                'bonus_coins': 0,
                'badge_title': '',
              })
          .toList();
    } catch (e) {
      debugPrint('Firestore: getChampions error – $e');
      return const [];
    }
  }

  /// Admin action: publishes the champion list for [date].
  static Future<bool> publishChampions(
    DateTime date,
    List<Map<String, dynamic>> winners,
  ) async {
    if (!isReady || winners.isEmpty) return false;
    try {
      final batch = _db.batch();
      final col =
          _db.collection(_champions).doc(dateKey(date)).collection('winners');
      for (final winner in winners) {
        final id = '${winner['user_id'] ?? winner['rank']}';
        batch.set(col.doc(id), {
          ...winner,
          'timestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('Firestore: publishChampions error – $e');
      return false;
    }
  }

  // ------------------------------------------------------- Quiz History --

  /// Saves a quiz result to the user's history subcollection.
  static Future<bool> saveQuizHistory(
    String userId,
    Map<String, dynamic> result,
  ) async {
    if (!isReady || userId.isEmpty) return false;
    try {
      final id = result['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString();
      await _db
          .collection(_users)
          .doc(userId)
          .collection('quiz_history')
          .doc(id)
          .set({...result, 'timestamp': FieldValue.serverTimestamp()},
              SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('Firestore: saveQuizHistory error – $e');
      return false;
    }
  }

  /// Fetches the user's quiz history (newest first).
  static Future<List<Map<String, dynamic>>> getQuizHistory(
    String userId, {
    int limit = 50,
  }) async {
    if (!isReady || userId.isEmpty) return const [];
    try {
      final snapshot = await _db
          .collection(_users)
          .doc(userId)
          .collection('quiz_history')
          .orderBy('played_at', descending: true)
          .limit(limit)
          .get();
      return snapshot.docs
          .map((d) => Map<String, dynamic>.from(d.data())..remove('timestamp'))
          .toList();
    } catch (e) {
      debugPrint('Firestore: getQuizHistory error – $e');
      return const [];
    }
  }

  // --------------------------------------------------- Purchase History --

  /// Saves a purchase to the user's purchase history subcollection.
  static Future<bool> savePurchaseHistory(
    String userId,
    Map<String, dynamic> purchase,
  ) async {
    if (!isReady || userId.isEmpty) return false;
    try {
      final id = purchase['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString();
      await _db
          .collection(_users)
          .doc(userId)
          .collection('purchase_history')
          .doc(id)
          .set({...purchase, 'timestamp': FieldValue.serverTimestamp()},
              SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('Firestore: savePurchaseHistory error – $e');
      return false;
    }
  }

  /// Fetches the user's purchase history (newest first).
  static Future<List<Map<String, dynamic>>> getPurchaseHistory(
    String userId, {
    int limit = 50,
  }) async {
    if (!isReady || userId.isEmpty) return const [];
    try {
      final snapshot = await _db
          .collection(_users)
          .doc(userId)
          .collection('purchase_history')
          .orderBy('purchased_at', descending: true)
          .limit(limit)
          .get();
      return snapshot.docs
          .map((d) => Map<String, dynamic>.from(d.data())..remove('timestamp'))
          .toList();
    } catch (e) {
      debugPrint('Firestore: getPurchaseHistory error – $e');
      return const [];
    }
  }

  // --------------------------------------------------------------- Gifts --

  static Future<List<Map<String, dynamic>>> getGifts(String userId) async {
    if (!isReady || userId.isEmpty) return const [];
    try {
      final snapshot = await _db
          .collection(_users)
          .doc(userId)
          .collection('gifts')
          .get();
      return snapshot.docs
          .map((d) => Map<String, dynamic>.from(d.data())..remove('timestamp'))
          .toList();
    } catch (e) {
      debugPrint('Firestore: getGifts error – $e');
      return const [];
    }
  }

  static Future<bool> saveGift(
    String userId,
    Map<String, dynamic> gift,
  ) async {
    if (!isReady || userId.isEmpty) return false;
    try {
      await _db
          .collection(_users)
          .doc(userId)
          .collection('gifts')
          .doc('${gift['id']}')
          .set({...gift, 'timestamp': FieldValue.serverTimestamp()},
              SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('Firestore: saveGift error – $e');
      return false;
    }
  }

  // -------------------------------------------------------------- Config --

  static Future<AppConfig?> loadConfig() async {
    if (!isReady) return null;
    try {
      final doc = await _db.collection(_config).doc('app').get();
      final data = doc.data();
      if (!doc.exists || data == null) return null;
      return AppConfig.fromJson(data);
    } catch (e) {
      debugPrint('Firestore: loadConfig error – $e');
      return null;
    }
  }

  static Future<bool> saveConfig(AppConfig config) async {
    if (!isReady) return false;
    try {
      await _db.collection(_config).doc('app').set(
            config.toJson(),
            SetOptions(merge: true),
          );
      return true;
    } catch (e) {
      debugPrint('Firestore: saveConfig error – $e');
      return false;
    }
  }

  // ------------------------------------------------------- Admin metrics --

  /// Real counts for the admin panel (no placeholder numbers).
  static Future<Map<String, int>> adminMetrics() async {
    if (!isReady) return const {};
    final metrics = <String, int>{};
    try {
      final totalUsers = await _db.collection(_users).count().get();
      metrics['total_users'] = totalUsers.count ?? 0;

      final guests = await _db
          .collection(_users)
          .where('is_guest', isEqualTo: true)
          .count()
          .get();
      metrics['guest_users'] = guests.count ?? 0;

      final todayPlayers = await _db
          .collection(_leaderboard)
          .doc(dateKey(DateTime.now()))
          .collection('scores')
          .count()
          .get();
      metrics['players_today'] = todayPlayers.count ?? 0;
    } catch (e) {
      debugPrint('Firestore: adminMetrics error – $e');
    }
    return metrics;
  }
}
