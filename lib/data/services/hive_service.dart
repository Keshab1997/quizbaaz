import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/chapter_set_progress.dart';
import '../models/notification_item.dart';
import '../models/user_model.dart';
import '../models/user_stats.dart';

/// Local persistence layer using Hive — the **single source of truth**.
///
/// Rules for the whole app:
/// * Providers read from and write to Hive first (instant, offline-safe).
/// * Firestore is only ever a mirror; it is written through [enqueuePending]
///   or directly by `SyncService`, never by the UI.
/// * Nothing in the UI may hold literal/placeholder data — if a value is not
///   in Hive yet, the screen shows an empty state.
///
/// Boxes
/// | box          | contents                                        |
/// |--------------|-------------------------------------------------|
/// | `qb_user`    | current [UserModel] as JSON                     |
/// | `qb_stats`   | [UserStats], quiz/purchase/notification history |
/// | `qb_cache`   | remote payloads with a timestamp (TTL cache)    |
/// | `qb_meta`    | flags, schema version, last sync timestamps     |
/// | `qb_pending` | queued Firestore writes made while offline      |
class HiveService {
  // ------------------------------------------------------------ Box names --

  static const _legacyBoxName = 'quizbaaz_box';
  static const userBoxName = 'qb_user';
  static const statsBoxName = 'qb_stats';
  static const cacheBoxName = 'qb_cache';
  static const metaBoxName = 'qb_meta';
  static const pendingBoxName = 'qb_pending';

  // ----------------------------------------------------------------- Keys --

  static const _userKey = 'current_user';
  static const _statsKey = 'user_stats';
  static const _quizHistoryKey = 'quiz_history';
  static const _purchaseHistoryKey = 'purchase_history';
  static const _notificationHistoryKey = 'notification_history';
  static const _chapterSetsKey = 'chapter_set_progress';
  static const _battleUsedQuestionsKey = 'battle_used_questions';
  static const _battleProcessedRoomsKey = 'battle_processed_rooms';

  /// How many question ids are remembered before the no-repeat cycle restarts.
  static const battleUsedQuestionsCap = 1000;

  /// How many finished room ids are remembered so a room can never pay out
  /// coins twice on the same device.
  static const battleProcessedRoomsCap = 50;

  // Legacy keys (v1 schema, single box).
  static const _bestScoreKey = 'best_daily_score';
  static const _bestTimeKey = 'best_daily_time';
  static const _lastRewardKey = 'last_daily_reward_date';
  static const _playedDailyKey = 'has_played_daily';

  // Meta keys.
  static const metaSchemaVersion = 'schema_version';
  static const metaLastSyncAt = 'last_sync_at_ms';
  static const metaLastPullAt = 'last_pull_at_ms';
  static const metaMigratedV2 = 'migrated_v2';

  /// Current on-disk schema version.
  static const int schemaVersion = 2;

  /// Cache keys used across the app. Keep them here so no screen invents its
  /// own string and they can all be invalidated in one place.
  static const cacheLeaderboard = 'leaderboard_today';
  static const cacheChampions = 'champions_yesterday';
  static const cacheChapters = 'chapters_list_v2';
  static const cacheDailyQuiz = 'daily_quiz_questions';
  static const cacheShopItems = 'shop_items';

  // ------------------------------------------------------------- Internals --

  static late Box _userBox;
  static late Box _statsBox;
  static late Box _cacheBox;
  static late Box _metaBox;
  static late Box _pendingBox;
  static Box? _legacyBox;

  static bool _initialized = false;
  static bool get isInitialized => _initialized;

  // ------------------------------------------------------------------ Init --

  /// Opens every box and runs the v1 → v2 migration once.
  static Future<void> initialize() async {
    if (_initialized) return;

    _userBox = await Hive.openBox(userBoxName);
    _statsBox = await Hive.openBox(statsBoxName);
    _cacheBox = await Hive.openBox(cacheBoxName);
    _metaBox = await Hive.openBox(metaBoxName);
    _pendingBox = await Hive.openBox(pendingBoxName);

    // The old single box may still exist on devices updating from v1.
    try {
      _legacyBox = await Hive.openBox(_legacyBoxName);
    } catch (e) {
      debugPrint('Hive: legacy box unavailable – $e');
      _legacyBox = null;
    }

    _initialized = true;
    await _migrateLegacyIfNeeded();
    await _metaBox.put(metaSchemaVersion, schemaVersion);
  }

  /// Moves v1 data from `quizbaaz_box` into the new boxes exactly once.
  static Future<void> _migrateLegacyIfNeeded() async {
    final legacy = _legacyBox;
    if (legacy == null) return;
    if (_metaBox.get(metaMigratedV2) == true) return;
    if (legacy.isEmpty) {
      await _metaBox.put(metaMigratedV2, true);
      return;
    }

    try {
      final rawUser = legacy.get(_userKey);
      if (rawUser is String && _userBox.get(_userKey) == null) {
        await _userBox.put(_userKey, rawUser);
      }

      // Fold the loose v1 progress keys into a UserStats object.
      final stats = loadStats();
      final legacyBest = (legacy.get(_bestScoreKey) as num?)?.toInt() ?? 0;
      final legacyTime = (legacy.get(_bestTimeKey) as num?)?.toDouble() ?? 0;
      if (legacyBest > stats.bestDailyScore) {
        stats.bestDailyScore = legacyBest;
      }
      if (legacyTime > 0 &&
          (stats.bestDailyTimeSeconds == 0 ||
              legacyTime < stats.bestDailyTimeSeconds)) {
        stats.bestDailyTimeSeconds = legacyTime;
      }
      await saveStats(stats);

      final lastReward = legacy.get(_lastRewardKey) as String?;
      if (lastReward != null) await setMeta(_lastRewardKey, lastReward);

      final played = legacy.get(_playedDailyKey) as bool?;
      if (played != null) await setMeta(_playedDailyKey, played);

      await _metaBox.put(metaMigratedV2, true);
      debugPrint('Hive: migrated legacy box to schema v$schemaVersion');
    } catch (e) {
      debugPrint('Hive: legacy migration failed – $e');
    }
  }

  // ------------------------------------------------------------ User data --

  /// Saves the current user model to Hive.
  static Future<void> saveUser(UserModel user) async {
    await _userBox.put(_userKey, jsonEncode(user.toJson()));
  }

  /// Loads the previously saved user model, or null when none exists.
  static UserModel? loadUser() {
    final raw = _userBox.get(_userKey);
    if (raw is! String) return null;
    try {
      return UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Hive: failed to decode user – $e');
      return null;
    }
  }

  /// True when a user has ever been persisted on this device.
  static bool get hasUser => _userBox.get(_userKey) != null;

  /// Clears the persisted user (on sign-out).
  static Future<void> clearUser() async {
    await _userBox.delete(_userKey);
  }

  // ----------------------------------------------------------------- Stats --

  /// Loads gameplay stats, always returning a usable object.
  static UserStats loadStats() {
    final raw = _statsBox.get(_statsKey);
    if (raw is! String) return UserStats.empty();
    try {
      return UserStats.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Hive: failed to decode stats – $e');
      return UserStats.empty();
    }
  }

  static Future<void> saveStats(UserStats stats) async {
    await _statsBox.put(_statsKey, jsonEncode(stats.toJson()));
  }

  static Future<void> clearStats() async {
    await _statsBox.delete(_statsKey);
  }

  // --------------------------------------------------------- Quiz History --

  /// Saves a quiz result to the history list (newest first, max 100 entries).
  static Future<void> saveQuizHistory(Map<String, dynamic> result) async {
    final List<dynamic> existing = _statsBox.get(_quizHistoryKey) != null
        ? List<dynamic>.from(
            jsonDecode(_statsBox.get(_quizHistoryKey) as String) as List)
        : [];
    existing.insert(0, result); // newest first
    if (existing.length > 100) existing.removeLast(); // keep max 100
    await _statsBox.put(_quizHistoryKey, jsonEncode(existing));
  }

  /// Loads all quiz history entries (newest first).
  static List<Map<String, dynamic>> loadQuizHistory() {
    final raw = _statsBox.get(_quizHistoryKey);
    if (raw is! String) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      debugPrint('Hive: failed to decode quiz history – $e');
      return const [];
    }
  }

  // ------------------------------------------------------------ battle --

  /// The ids of questions already used in past battles, oldest first.
  ///
  /// The battle question generator filters these out so every match throws
  /// NEW questions; once the unseen pool runs dry the list is cleared and the
  /// cycle restarts (see `battle_used_questions` in the generator docs).
  static List<String> loadBattleUsedQuestionIds() {
    final raw = _statsBox.get(_battleUsedQuestionsKey);
    if (raw is! String) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint('Hive: failed to decode battle used questions – $e');
      return const [];
    }
  }

  /// Appends battle question ids, keeping the newest [battleUsedQuestionsCap].
  static Future<void> recordBattleUsedQuestionIds(List<String> ids) async {
    if (ids.isEmpty) return;
    final current = loadBattleUsedQuestionIds().toList();
    final seen = current.toSet();
    for (final id in ids) {
      if (seen.add(id)) current.add(id);
    }
    if (current.length > battleUsedQuestionsCap) {
      current.removeRange(0, current.length - battleUsedQuestionsCap);
    }
    await _statsBox.put(_battleUsedQuestionsKey, jsonEncode(current));
  }

  /// Clears the used-question ledger (cycle restart).
  static Future<void> clearBattleUsedQuestionIds() async {
    await _statsBox.delete(_battleUsedQuestionsKey);
  }

  /// Marks a live room as paid out on this device (single-award guard).
  static Future<bool> markBattleRoomProcessed(String roomId) async {
    final raw = _statsBox.get(_battleProcessedRoomsKey);
    final List<String> processed = raw is String
        ? (jsonDecode(raw) as List).map((e) => e.toString()).toList()
        : <String>[];
    if (processed.contains(roomId)) return false;
    processed.add(roomId);
    if (processed.length > battleProcessedRoomsCap) {
      processed.removeRange(0, processed.length - battleProcessedRoomsCap);
    }
    await _statsBox.put(_battleProcessedRoomsKey, jsonEncode(processed));
    return true;
  }

  /// True when this device already processed rewards for [roomId].
  static bool isBattleRoomProcessed(String roomId) {
    final raw = _statsBox.get(_battleProcessedRoomsKey);
    if (raw is! String) return false;
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).contains(roomId);
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------- chapter sets --

  /// Per-set progress for every chapter, keyed `chapterId#setIndex`.
  ///
  /// Stored as one blob rather than a box per chapter: the whole map is small
  /// (a few hundred bytes per completed set), it is read on every chapter
  /// screen, and one decode beats fifty lookups.
  static Map<String, ChapterSetProgress> loadChapterSets() {
    final raw = _statsBox.get(_chapterSetsKey);
    if (raw is! String) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(
            key,
            ChapterSetProgress.fromJson(Map<String, dynamic>.from(value as Map)),
          ));
    } catch (e) {
      debugPrint('Hive: failed to decode chapter set progress – $e');
      return {};
    }
  }

  /// Progress for a single set, or null when it has never been completed.
  static ChapterSetProgress? loadChapterSet(String chapterId, int setIndex) =>
      loadChapterSets()[ChapterSetProgress.keyFor(chapterId, setIndex)];

  /// Records a completed set, keeping the better of the old and new results.
  static Future<ChapterSetProgress> saveChapterSet({
    required String chapterId,
    required int setIndex,
    required int score,
    required int correct,
    required int total,
  }) async {
    final all = loadChapterSets();
    final key = ChapterSetProgress.keyFor(chapterId, setIndex);
    final now = DateTime.now();

    final existing = all[key];
    final updated = existing == null
        ? ChapterSetProgress(
            chapterId: chapterId,
            setIndex: setIndex,
            bestScore: score,
            bestCorrect: correct,
            totalQuestions: total,
            completedAt: now,
            lastPlayedAt: now,
          )
        : existing.merge(
            score: score, correct: correct, total: total, playedAt: now);

    all[key] = updated;
    await _statsBox.put(
      _chapterSetsKey,
      jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))),
    );
    return updated;
  }

  /// Completed sets for one chapter, lowest set first.
  static List<ChapterSetProgress> chapterSetsFor(String chapterId) {
    final all = loadChapterSets().values
        .where((p) => p.chapterId == chapterId)
        .toList()
      ..sort((a, b) => a.setIndex.compareTo(b.setIndex));
    return all;
  }

  /// The first set the student has not finished — what "Continue" plays.
  ///
  /// Returns null when every set is done, which the UI turns into "replay any
  /// set" rather than silently restarting from the top.
  static int? nextUnplayedSet(String chapterId, int setCount) {
    final completed = chapterSetsFor(chapterId).map((p) => p.setIndex).toSet();
    for (var i = 0; i < setCount; i++) {
      if (!completed.contains(i)) return i;
    }
    return null;
  }

  /// Clears all quiz history.
  static Future<void> clearQuizHistory() async {
    await _statsBox.delete(_quizHistoryKey);
  }

  // ------------------------------------------------------ Purchase History --

  /// Saves a purchase to the history list (newest first, max 100 entries).
  static Future<void> savePurchaseHistory(Map<String, dynamic> purchase) async {
    final List<dynamic> existing = _statsBox.get(_purchaseHistoryKey) != null
        ? List<dynamic>.from(
            jsonDecode(_statsBox.get(_purchaseHistoryKey) as String) as List)
        : [];
    existing.insert(0, purchase); // newest first
    if (existing.length > 100) existing.removeLast(); // keep max 100
    await _statsBox.put(_purchaseHistoryKey, jsonEncode(existing));
  }

  /// Loads all purchase history entries (newest first).
  static List<Map<String, dynamic>> loadPurchaseHistory() {
    final raw = _statsBox.get(_purchaseHistoryKey);
    if (raw is! String) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      debugPrint('Hive: failed to decode purchase history – $e');
      return const [];
    }
  }

  /// Clears all purchase history.
  static Future<void> clearPurchaseHistory() async {
    await _statsBox.delete(_purchaseHistoryKey);
  }

  // ------------------------------------------------- Notification inbox --

  /// Newest-first inbox rows. Empty when none have been captured yet.
  static List<NotificationItem> loadNotificationHistory() {
    final raw = _statsBox.get(_notificationHistoryKey);
    if (raw is! String) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => NotificationItem.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('Hive: failed to decode notification history – $e');
      return const [];
    }
  }

  static Future<void> saveNotificationHistory(
      List<NotificationItem> items) async {
    await _statsBox.put(
      _notificationHistoryKey,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> clearNotificationHistory() async {
    await _statsBox.delete(_notificationHistoryKey);
  }

  // ------------------------------------------------------------ TTL cache --

  /// Stores [value] (any JSON-encodable structure) under [key] with the
  /// current timestamp so freshness can be checked later.
  static Future<void> cachePut(String key, Object value) async {
    await _cacheBox.put(key, {
      'ts': DateTime.now().millisecondsSinceEpoch,
      'data': jsonEncode(value),
    });
  }

  /// Returns the decoded cached value, or null when missing / expired.
  /// Pass [maxAge] to reject stale entries; omit it to accept any age.
  static dynamic cacheGet(String key, {Duration? maxAge}) {
    final entry = _cacheBox.get(key);
    if (entry is! Map) return null;
    final ts = (entry['ts'] as num?)?.toInt();
    final raw = entry['data'];
    if (ts == null || raw is! String) return null;
    if (maxAge != null) {
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (age > maxAge.inMilliseconds) return null;
    }
    try {
      return jsonDecode(raw);
    } catch (e) {
      debugPrint('Hive: failed to decode cache "$key" – $e');
      return null;
    }
  }

  /// Convenience wrapper returning a typed list of maps.
  static List<Map<String, dynamic>> cacheGetList(
    String key, {
    Duration? maxAge,
  }) {
    final value = cacheGet(key, maxAge: maxAge);
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// How long ago [key] was cached, or null when absent.
  static Duration? cacheAge(String key) {
    final entry = _cacheBox.get(key);
    if (entry is! Map) return null;
    final ts = (entry['ts'] as num?)?.toInt();
    if (ts == null) return null;
    return Duration(
      milliseconds: DateTime.now().millisecondsSinceEpoch - ts,
    );
  }

  /// True when [key] exists and is newer than [maxAge].
  static bool isCacheFresh(String key, Duration maxAge) {
    final age = cacheAge(key);
    return age != null && age <= maxAge;
  }

  static Future<void> cacheRemove(String key) async {
    await _cacheBox.delete(key);
  }

  static Future<void> clearCache() async {
    await _cacheBox.clear();
  }

  // -------------------------------------------------- Offline write queue --

  /// Queues a Firestore write to be replayed when connectivity returns.
  ///
  /// [type] is a short verb such as `save_user`, `save_stats` or
  /// `leaderboard_entry`; [payload] must be JSON-encodable.
  static Future<void> enqueuePending(
    String type,
    Map<String, dynamic> payload,
  ) async {
    await _pendingBox.add(jsonEncode({
      'type': type,
      'payload': payload,
      'queued_at': DateTime.now().millisecondsSinceEpoch,
    }));
  }

  /// All queued operations as `(key, decoded map)` pairs, oldest first.
  static List<MapEntry<dynamic, Map<String, dynamic>>> pendingOps() {
    final ops = <MapEntry<dynamic, Map<String, dynamic>>>[];
    for (final key in _pendingBox.keys) {
      final raw = _pendingBox.get(key);
      if (raw is! String) continue;
      try {
        ops.add(MapEntry(key, jsonDecode(raw) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('Hive: dropping malformed pending op – $e');
      }
    }
    return ops;
  }

  static int get pendingCount => _pendingBox.length;

  static Future<void> removePending(dynamic key) async {
    await _pendingBox.delete(key);
  }

  static Future<void> clearPending() async {
    await _pendingBox.clear();
  }

  // ------------------------------------------------------------------ Meta --

  static Future<void> setMeta(String key, Object? value) async {
    if (value == null) {
      await _metaBox.delete(key);
    } else {
      await _metaBox.put(key, value);
    }
  }

  static T? getMeta<T>(String key) {
    final value = _metaBox.get(key);
    return value is T ? value : null;
  }

  static Future<void> markSynced() =>
      setMeta(metaLastSyncAt, DateTime.now().millisecondsSinceEpoch);

  static Future<void> markPulled() =>
      setMeta(metaLastPullAt, DateTime.now().millisecondsSinceEpoch);

  static DateTime? get lastSyncAt {
    final ms = getMeta<int>(metaLastSyncAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static DateTime? get lastPullAt {
    final ms = getMeta<int>(metaLastPullAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  // --------------------------------------------------------------- General --

  /// Wipes user + stats + cache + queue (used on sign-out / reset).
  static Future<void> clearAll() async {
    await _userBox.clear();
    await _statsBox.clear();
    await _cacheBox.clear();
    await _pendingBox.clear();
    await _legacyBox?.clear();
    // Meta keeps schema info, only sync markers are reset.
    await _metaBox.delete(metaLastSyncAt);
    await _metaBox.delete(metaLastPullAt);
    // Clear quiz, purchase and notification history
    await clearQuizHistory();
    await clearPurchaseHistory();
    await clearNotificationHistory();
  }

  /// Debug helper: a snapshot of what is currently stored.
  static Map<String, dynamic> debugSummary() => {
        'schemaVersion': getMeta<int>(metaSchemaVersion),
        'hasUser': hasUser,
        'stats': loadStats().toJson(),
        'cacheKeys': _cacheBox.keys.toList(),
        'pending': pendingCount,
        'lastSyncAt': lastSyncAt?.toIso8601String(),
      };
}
