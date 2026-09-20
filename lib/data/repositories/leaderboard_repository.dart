import '../models/champion_model.dart';
import '../models/leaderboard_model.dart';
import '../services/competition_clock.dart';
import '../services/hive_service.dart';
import '../services/sync_service.dart';

/// Hive-first access to ranking data.
///
/// Reading is always instant: the cached rows in Hive are returned straight
/// away, then Firestore is queried in the background and the cache refreshed.
/// There is no bundled JSON fallback any more — if there is no data, the
/// screens show a real empty state instead of invented players.
class LeaderboardRepository {
  /// Cached leaderboard rows for one competition day (may be empty).
  ///
  /// The cache is date-scoped, so a failed refresh on a new day shows an empty
  /// state (correct) instead of yesterday's standings (wrong) — R12.
  List<LeaderboardItem> cachedLeaderboard({DateTime? date}) {
    return HiveService.cacheGetList(
      HiveService.cacheLeaderboardFor(CompetitionClock.dateKey(date)),
      allowStale: true,
    ).map(LeaderboardItem.fromJson).toList();
  }

  /// Cached champions (may be empty).
  List<ChampionModel> cachedChampions() {
    return HiveService.cacheGetList(HiveService.cacheChampions)
        .map(ChampionModel.fromJson)
        .toList();
  }

  /// True when today's cached leaderboard is still fresh enough to skip a
  /// fetch.
  bool isLeaderboardFresh(Duration ttl, {DateTime? date}) =>
      HiveService.isCacheFresh(
        HiveService.cacheLeaderboardFor(CompetitionClock.dateKey(date)),
        ttl,
      );

  bool areChampionsFresh(Duration ttl) =>
      HiveService.isCacheFresh(HiveService.cacheChampions, ttl);

  /// Pulls today's leaderboard from Firestore into the Hive cache.
  Future<List<LeaderboardItem>> refreshLeaderboard({int limit = 50}) async {
    final rows = await SyncService.pullLeaderboard(limit: limit);
    if (rows.isEmpty) return cachedLeaderboard();
    return rows.map(LeaderboardItem.fromJson).toList();
  }

  /// Pulls the daily winner history (last [days] completed days) from
  /// Firestore into the Hive cache, newest day first.
  Future<List<ChampionModel>> refreshChampions({int limit = 10, int days = 7}) async {
    final rows = await SyncService.pullChampions(limit: limit, days: days);
    if (rows.isEmpty) return cachedChampions();
    return rows.map(ChampionModel.fromJson).toList();
  }

  /// When today's ranking data was last downloaded, or null.
  DateTime? get lastUpdated {
    final age = HiveService.cacheAge(
      HiveService.cacheLeaderboardFor(CompetitionClock.dateKey()),
    );
    if (age == null) return null;
    return DateTime.now().subtract(age);
  }
}
