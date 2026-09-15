import 'package:flutter/foundation.dart';

import '../models/app_config.dart';
import '../models/user_model.dart';
import '../models/user_stats.dart';
import 'firestore_service.dart';
import 'hive_service.dart';

/// Keeps Hive (source of truth) and Firestore (mirror) in agreement.
///
/// Push rules
/// * Every write goes to Hive first — done by the providers.
/// * [pushUser] / [pushStats] / [pushLeaderboardEntry] then try Firestore.
/// * A failed or offline write is queued in `qb_pending` and replayed by
///   [drainPending] on the next successful sync.
///
/// Pull rules
/// * [pullUser] / [pullStats] merge remote data into the local copy, never
///   blindly overwrite it (highest value / latest date wins).
/// * Leaderboard, champions and config are cached in Hive with a TTL.
class SyncService {
  SyncService._();

  static bool get isOnline => FirestoreService.isReady;

  // ------------------------------------------------------------- Pushing --

  /// Mirrors the user profile to Firestore, queueing it when offline.
  static Future<void> pushUser(UserModel user) async {
    if (user.isGuest || user.userId.isEmpty) return;
    final ok = await FirestoreService.saveUser(user);
    if (ok) {
      await HiveService.markSynced();
    } else {
      await HiveService.enqueuePending('save_user', user.toJson());
    }
  }

  /// Mirrors gameplay stats to Firestore.
  static Future<void> pushStats(String userId, UserStats stats) async {
    if (userId.isEmpty) return;
    final ok = await FirestoreService.saveStats(userId, stats);
    if (ok) {
      stats.lastSyncedAtMs = DateTime.now().millisecondsSinceEpoch;
      await HiveService.saveStats(stats);
      await HiveService.markSynced();
    } else {
      await HiveService.enqueuePending('save_stats', {
        'user_id': userId,
        'stats': stats.toJson(),
      });
    }
  }

  /// Mirrors today's leaderboard entry.
  static Future<void> pushLeaderboardEntry({
    required UserModel user,
    required int score,
    required double timeSeconds,
    DateTime? date,
  }) async {
    if (user.isGuest || user.userId.isEmpty) return;
    final when = date ?? DateTime.now();
    final ok = await FirestoreService.saveLeaderboardEntry(
      userId: user.userId,
      username: user.username,
      fullName: user.fullName,
      avatarPath: user.effectiveAvatar,
      nameEffect: user.nameEffect,
      score: score,
      timeSeconds: timeSeconds,
      streak: user.dailyStreak,
      date: when,
    );
    if (!ok) {
      await HiveService.enqueuePending('leaderboard_entry', {
        'user_id': user.userId,
        'username': user.username,
        'name': user.fullName,
        'avatar_path': user.effectiveAvatar,
        'name_effect': user.nameEffect ?? '',
        'score': score,
        'time_seconds': timeSeconds,
        'streak': user.dailyStreak,
        'date': FirestoreService.dateKey(when),
      });
    }
  }

  /// Mirrors a quiz result to Firestore.
  static Future<void> pushQuizHistory(
    String userId,
    Map<String, dynamic> result,
  ) async {
    if (userId.isEmpty) return;
    final ok = await FirestoreService.saveQuizHistory(userId, result);
    if (!ok) {
      await HiveService.enqueuePending('save_quiz_history', {
        'user_id': userId,
        'result': result,
      });
    }
  }

  /// Pulls the user's quiz history from Firestore into Hive cache.
  static Future<List<Map<String, dynamic>>> pullQuizHistory(
    String userId, {
    int limit = 50,
  }) async {
    final rows = await FirestoreService.getQuizHistory(userId, limit: limit);
    if (rows.isNotEmpty) {
      await HiveService.cachePut('quiz_history', rows);
    }
    return rows;
  }

  /// Mirrors a purchase to Firestore.
  static Future<void> pushPurchaseHistory(
    String userId,
    Map<String, dynamic> purchase,
  ) async {
    if (userId.isEmpty) return;
    final ok = await FirestoreService.savePurchaseHistory(userId, purchase);
    if (!ok) {
      await HiveService.enqueuePending('save_purchase_history', {
        'user_id': userId,
        'purchase': purchase,
      });
    }
  }

  /// Pulls the user's purchase history from Firestore into Hive cache.
  static Future<List<Map<String, dynamic>>> pullPurchaseHistory(
    String userId, {
    int limit = 50,
  }) async {
    final rows = await FirestoreService.getPurchaseHistory(userId, limit: limit);
    if (rows.isNotEmpty) {
      await HiveService.cachePut('purchase_history', rows);
    }
    return rows;
  }

  /// Gift claims are recorded locally (Hive) only.
  ///
  /// P0 (R02): `users/{uid}/gifts` is now **admin/server-writable only** —
  /// the trusted backend dispatches gifts and clients may not mint, claim or
  /// delete them remotely. Pushing claims would be denied by
  /// `firestore.rules`, and queueing a write that can never succeed would
  /// clog the outbox (R14). Trusted gift settlement (server-confirmed
  /// claim state) is a P1 follow-up.
  static Future<void> pushGift(String userId, Map<String, dynamic> gift) async {
    return; // local-only by design (see comment above)
  }

  /// Replays everything queued while offline. Safe to call often.
  static Future<int> drainPending() async {
    if (!isOnline) return 0;
    var replayed = 0;

    for (final entry in HiveService.pendingOps()) {
      final op = entry.value;
      final type = op['type'] as String? ?? '';
      final payload = (op['payload'] as Map?)?.cast<String, dynamic>() ?? {};
      var ok = false;

      try {
        switch (type) {
          case 'save_user':
            ok = await FirestoreService.saveUser(UserModel.fromJson(payload));
            break;
          case 'save_stats':
            ok = await FirestoreService.saveStats(
              payload['user_id'] as String? ?? '',
              UserStats.fromJson(
                (payload['stats'] as Map?)?.cast<String, dynamic>() ?? {},
              ),
            );
            break;
          case 'leaderboard_entry':
            ok = await FirestoreService.saveLeaderboardEntry(
              userId: payload['user_id'] as String? ?? '',
              username: payload['username'] as String? ?? '',
              fullName: payload['name'] as String? ?? '',
              avatarPath: payload['avatar_path'] as String? ?? '',
              nameEffect: payload['name_effect'] as String?,
              score: (payload['score'] as num?)?.toInt() ?? 0,
              timeSeconds: (payload['time_seconds'] as num?)?.toDouble() ?? 0,
              streak: (payload['streak'] as num?)?.toInt() ?? 0,
              date: _parseDate(payload['date'] as String?) ?? DateTime.now(),
            );
            break;
          case 'save_gift':
            // Legacy queued op. Gift writes are server-owned now (P0 R02),
            // so drop it instead of replaying a write that would be denied
            // and clog the queue.
            ok = true;
            break;
          case 'save_quiz_history':
            ok = await FirestoreService.saveQuizHistory(
              payload['user_id'] as String? ?? '',
              (payload['result'] as Map?)?.cast<String, dynamic>() ?? {},
            );
            break;
          case 'save_purchase_history':
            ok = await FirestoreService.savePurchaseHistory(
              payload['user_id'] as String? ?? '',
              (payload['purchase'] as Map?)?.cast<String, dynamic>() ?? {},
            );
            break;
          default:
            ok = true; // unknown op: drop it instead of blocking the queue
        }
      } catch (e) {
        debugPrint('Sync: replay failed for "$type" – $e');
        ok = false;
      }

      if (ok) {
        await HiveService.removePending(entry.key);
        replayed++;
      } else {
        break; // still offline — keep the rest for later
      }
    }

    if (replayed > 0) await HiveService.markSynced();
    return replayed;
  }

  // ------------------------------------------------------------- Pulling --

  /// Merges the remote profile into [local] and returns the merged copy.
  /// Coins/gems/streak keep the higher value so nothing is ever lost.
  static Future<UserModel> pullUser(UserModel local) async {
    if (local.isGuest || local.userId.isEmpty) return local;
    final remote = await FirestoreService.loadUser(local.userId);
    if (remote == null) return local;

    // The daily streak and its date are ONE logical unit and must be merged
    // together. Merging them independently could produce an impossible state
    // (e.g. a "6-day streak ending 09-04") or resurrect a streak that was
    // deliberately reset to 0 on another device.
    //
    // Rules:
    //   * Same date on both sides (or both empty): an intentional reset
    //     (0 with a date set) wins; otherwise keep the higher streak.
    //   * Different dates: the LATER date is ahead in time, so its whole
    //     (streak, date) pair wins.
    final localDate = local.lastStreakDate;
    final remoteDate = remote.lastStreakDate;
    int mergedStreak;
    String? mergedDate;
    if (localDate == remoteDate) {
      mergedDate = localDate;
      if (local.dailyStreak == 0 || remote.dailyStreak == 0) {
        mergedStreak =
            local.dailyStreak == 0 ? local.dailyStreak : remote.dailyStreak;
      } else {
        mergedStreak = local.dailyStreak >= remote.dailyStreak
            ? local.dailyStreak
            : remote.dailyStreak;
      }
    } else if (remoteDate != null &&
        (localDate == null || remoteDate.compareTo(localDate) > 0)) {
      mergedDate = remoteDate;
      mergedStreak = remote.dailyStreak;
    } else {
      mergedDate = localDate;
      mergedStreak = local.dailyStreak;
    }

    final merged = local.copyWith(
      coins: local.coins >= remote.coins ? local.coins : remote.coins,
      gems: local.gems >= remote.gems ? local.gems : remote.gems,
      dailyStreak: mergedStreak,
      isAdmin: local.isAdmin || remote.isAdmin,
      lastStreakDate: mergedDate,
      avatarUrl: local.avatarUrl ?? remote.avatarUrl,
      nameEffect: local.nameEffect ?? remote.nameEffect,
    );

    // Inventory: keep the larger count per item.
    remote.inventory.forEach((key, value) {
      final mine = merged.inventory[key] ?? 0;
      merged.inventory[key] = mine > value ? mine : value;
    });

    await HiveService.saveUser(merged);
    await HiveService.markPulled();
    return merged;
  }

  /// Merges remote stats into the local ones and persists the result.
  static Future<UserStats> pullStats(String userId, UserStats local) async {
    if (userId.isEmpty) return local;
    final remote = await FirestoreService.loadStats(userId);
    if (remote == null) return local;
    final merged = local.mergeWith(remote);
    await HiveService.saveStats(merged);
    return merged;
  }

  /// Downloads this user's own leaderboard entry for today, or null.
  static Future<Map<String, dynamic>?> pullLeaderboardEntry(
    String userId, {
    DateTime? date,
  }) async {
    if (userId.isEmpty) return null;
    return FirestoreService.getLeaderboardEntry(userId, date ?? DateTime.now());
  }

  /// Downloads today's leaderboard into the Hive cache and returns the rows.
  static Future<List<Map<String, dynamic>>> pullLeaderboard({
    DateTime? date,
    int limit = 50,
  }) async {
    final rows = await FirestoreService.getLeaderboard(
      date ?? DateTime.now(),
      limit: limit,
    );

    // Fresh rows when they arrived, otherwise fall back to the cache — the
    // ordering below is enforced either way so ranks stay deterministic.
    final source = rows.isNotEmpty
        ? rows
        : HiveService.cacheGetList(HiveService.cacheLeaderboard);
    if (source.isEmpty) return const [];

    // Tie-breaker: highest score wins; on EQUAL scores the FASTEST time wins.
    // This mirrors the Firestore query (score DESC, time_seconds ASC) and
    // keeps the offline cache consistent too.
    source.sort((a, b) {
      final sa = (a['score'] as num?)?.toInt() ?? 0;
      final sb = (b['score'] as num?)?.toInt() ?? 0;
      if (sa != sb) return sb.compareTo(sa);
      final ta = (a['time_seconds'] as num?)?.toDouble() ?? double.infinity;
      final tb = (b['time_seconds'] as num?)?.toDouble() ?? double.infinity;
      return ta.compareTo(tb);
    });

    // Re-assign ranks so they always match the on-screen order.
    for (var i = 0; i < source.length; i++) {
      source[i]['rank'] = i + 1;
    }

    if (rows.isNotEmpty) {
      await HiveService.cachePut(HiveService.cacheLeaderboard, source);
      await HiveService.markPulled();
    }
    return source;
  }

  /// Downloads yesterday's champions into the Hive cache.
  /// Pulls the daily winner history for the last [days] completed days
  /// (1 = yesterday only, 7 = a full week). Every row is tagged with its
  /// `date_key` (yyyy-MM-dd) so the UI can group winners by day.
  ///
  /// Newer days are fetched first and always win over older cached entries,
  /// so the cache naturally accumulates a growing winner history.
  static Future<List<Map<String, dynamic>>> pullChampions({
    DateTime? date,
    int limit = 10,
    int days = 7,
  }) async {
    final today = date ?? DateTime.now();

    // Seed with whatever history is already cached, then overlay fresh days.
    final byKey = <String, List<Map<String, dynamic>>>{};
    for (final cached in HiveService.cacheGetList(HiveService.cacheChampions)) {
      final key = (cached['date_key'] ?? cached['date'] ?? '') as String;
      if (key.isNotEmpty) byKey.putIfAbsent(key, () => []).add(cached);
    }

    var fetchedAny = false;
    for (var i = 1; i <= days; i++) {
      final when = today.subtract(Duration(days: i));
      final key = FirestoreService.dateKey(when);
      final rows = await FirestoreService.getChampions(when, limit: limit);
      if (rows.isNotEmpty) {
        byKey[key] = rows.map((r) => {...r, 'date_key': key}).toList();
        fetchedAny = true;
      }
    }

    if (!fetchedAny) {
      // Nothing new from Firestore — fall back to the cached history.
      return HiveService.cacheGetList(HiveService.cacheChampions);
    }

    // Newest day first, winners ordered by rank within each day.
    final keys = byKey.keys.toList()..sort((a, b) => b.compareTo(a));
    final merged = <Map<String, dynamic>>[];
    for (final k in keys) {
      merged.addAll(byKey[k]!);
    }

    await HiveService.cachePut(HiveService.cacheChampions, merged);
    await HiveService.markPulled();
    return merged;
  }

  /// Loads remote config, caching it in Hive. Returns null when unchanged
  /// or unavailable so callers can keep the cached/default values.
  static Future<AppConfig?> pullConfig() async {
    final config = await FirestoreService.loadConfig();
    if (config != null) {
      await HiveService.cachePut('app_config', config.toJson());
    }
    return config;
  }

  /// Reads the cached config (or the built-in defaults).
  static AppConfig cachedConfig() {
    final raw = HiveService.cacheGet('app_config');
    if (raw is Map) {
      try {
        return AppConfig.fromJson(Map<String, dynamic>.from(raw));
      } catch (e) {
        debugPrint('Sync: bad cached config – $e');
      }
    }
    return const AppConfig();
  }

  /// Full sync pass: replay the queue, then refresh remote data.
  static Future<void> syncAll(UserModel user) async {
    if (!isOnline) return;
    await drainPending();
    await pushUser(user);
    await pullConfig();
    await pullLeaderboard();
    await pullChampions();
    await HiveService.markSynced();
  }

  // -------------------------------------------------------------- Helpers --

  static DateTime? _parseDate(String? key) {
    if (key == null) return null;
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }
}
