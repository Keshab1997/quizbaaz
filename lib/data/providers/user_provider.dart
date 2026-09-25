import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_config.dart';
import '../models/champion_model.dart';
import '../models/leaderboard_model.dart';
import '../models/purchase_history.dart';
import '../models/quiz_result_history.dart';
import '../models/shop_item.dart';
import '../models/user_model.dart';
import '../models/user_stats.dart';
import '../repositories/leaderboard_repository.dart';
import '../services/competition_clock.dart';
import '../services/daily_score_lock.dart';
import '../services/hive_service.dart';
import '../services/push_sync.dart';
import '../services/sync_service.dart';
import '../services/trusted_ops_service.dart';

/// Result of a shop purchase attempt.
enum PurchaseStatus { success, insufficientFunds, alreadyOwned }

/// Reward details when claiming yesterday's daily leaderboard rank prizes.
class DailyRewardResult {
  final int rank;
  final int coins;
  final int gems;
  final List<String> itemNames;
  final int winningStreak;
  final String? milestonePrizeTitle;

  const DailyRewardResult({
    required this.rank,
    required this.coins,
    required this.gems,
    required this.itemNames,
    required this.winningStreak,
    this.milestonePrizeTitle,
  });
}

/// Details when a user's daily streak gets reset due to missing a day.
class StreakResetDetails {
  final int lostStreak;
  final bool hasShield;

  const StreakResetDetails({
    required this.lostStreak,
    required this.hasShield,
  });
}

/// Owns the player's profile, stats and ranking data.
///
/// **Hive is the source of truth.** Every mutation writes to Hive first and
/// then asks [SyncService] to mirror it to Firestore (queued when offline).
/// Nothing in this class invents data: a fresh install starts at zero.
class UserProvider extends ChangeNotifier {
  final LeaderboardRepository _rankings = LeaderboardRepository();

  UserModel _user = UserModel.newPlayer();
  UserStats _stats = UserStats.empty();
  AppConfig _config = const AppConfig();

  List<ChampionModel> _champions = const [];
  List<LeaderboardItem> _leaderboard = const [];

  bool _isLoading = false;
  bool _isInitialized = false;
  String? _lastDailyRewardDate;

  /// Highest daily score the current flat scoring can produce: 10 questions ×
  /// 10 points, doubled by the Double Points booster. Anything above this is
  /// a leftover from the old time-bonus scoring and must be reset.
  static const int kMaxPossibleDailyScore = 200;

  // ------------------------------------------------------------- Getters --

  UserModel get user => _user;
  UserStats get stats => _stats;
  AppConfig get config => _config;
  List<ChampionModel> get champions => _champions;
  List<LeaderboardItem> get leaderboard => _leaderboard;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;

  /// Yesterday's #1 champion (matched by date), or null when no champion
  /// has been published for yesterday yet.
  ChampionModel? get yesterdayTopChampion {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final key = '${yesterday.year}-'
        '${yesterday.month.toString().padLeft(2, '0')}-'
        '${yesterday.day.toString().padLeft(2, '0')}';
    for (final c in _champions) {
      if (c.dateKey == key && c.rank == 1) return c;
    }
    return null;
  }

  /// Only real admins (Firestore flag or the config allow-list) see the panel.
  bool get isAdmin => _user.isAdmin || _config.isAdmin(_user.userId);

  int get bestDailyScore => _stats.bestDailyScore;
  double get bestDailyTime => _stats.bestDailyTimeSeconds;
  bool get hasPlayedDailyQuiz => _stats.totalQuizzes > 0 && _playedDailyToday;
  bool get hasStats => _stats.hasData;

  bool get _playedDailyToday => _user.playedTodayDailyQuiz;

  /// When the ranking data was last refreshed from Firestore.
  DateTime? get rankingsUpdatedAt => _rankings.lastUpdated;

  /// The player's own row in today's live leaderboard, if present.
  LeaderboardItem? get myLeaderboardEntry {
    for (final item in _leaderboard) {
      // Identity is the uid, and only the uid: usernames are mutable and not
      // unique, so matching on them could hand one player another player's
      // row — and another player's prize (R12).
      if (leaderboardRowBelongsToUser(item, userId: _user.userId)) return item;
    }
    return null;
  }

  /// Today's **counted** daily score — the one number this player has on
  /// today's leaderboard, written by their first ranked run of the day (or by
  /// the Score Shield retry that replaced it). 0 when they have none yet.
  ///
  /// This is NOT [bestDailyScore], which is a lifetime best that never
  /// decreases and can still carry a phantom value from the old time-bonus
  /// scoring (e.g. 370) long after a 90-point quiz — and it is not
  /// "the best run of the day" either: replays are never counted. See
  /// [DailyScoreLock].
  int get todayCountedScore {
    final dayKey = _todayKey();
    final counted = DailyScoreLock.countedRun(dayKey);
    if (counted != null) return counted.score;
    return myLeaderboardEntry?.score ?? 0;
  }

  /// Today's counted time (seconds) for the tie-breaker, matching
  /// [todayCountedScore].
  double get todayCountedTimeSeconds {
    final dayKey = _todayKey();
    final counted = DailyScoreLock.countedRun(dayKey);
    if (counted != null) return counted.timeSeconds;
    return myLeaderboardEntry?.timeSeconds ?? 0;
  }

  /// True when today's leaderboard score is locked in: any further daily run
  /// is played for coins, XP and the streak, but cannot change the row.
  bool get isDailyScoreLockedToday =>
      DailyScoreLock.isLocked(_todayKey());

  /// How many ranked daily runs the player finished today (counted or not).
  int get dailyRunsToday => DailyScoreLock.attempts(_todayKey());

  /// True when a Score Shield has reopened today's score: the player's next
  /// ranked daily run replaces it instead of being ignored.
  bool get isDailyRetryUnlockedToday =>
      DailyScoreLock.isRetryUnlocked(_todayKey());

  /// True when a Score Shield can still reopen today's score: the day is
  /// locked, the player owns a shield, and the day's one retry has not been
  /// used yet.
  bool get canRetryDailyScoreWithShield =>
      hasItem(ShopItemIds.scoreShield) &&
      isDailyScoreLockedToday &&
      !DailyScoreLock.isRetryUnlocked(_todayKey()) &&
      DailyScoreLock.retriesUsed(_todayKey()) == 0;

  /// Position among the cached leaderboard rows, or null when not ranked yet.
  int? get playerRank {
    if (!hasPlayedDailyQuiz) return null;
    final myScore = todayCountedScore;
    final myTime = todayCountedTimeSeconds;
    var rank = 1;
    for (final item in _leaderboard) {
      if (leaderboardRowBelongsToUser(item, userId: _user.userId)) continue;
      final isAhead = item.score > myScore ||
          (item.score == myScore &&
              myScore > 0 &&
              myTime > 0 &&
              item.timeSeconds < myTime);
      if (isAhead) rank++;
    }
    return rank;
  }

  /// "Top X%" text for the dashboard, or null when there is nothing to rank.
  String? get percentileLabel {
    final rank = playerRank;
    if (rank == null || _leaderboard.isEmpty) return null;
    final total = _leaderboard.length;
    final percent = ((rank / total) * 100).clamp(1, 100).round();
    return 'Top $percent% today';
  }

  // ---------------------------------------------------------------- Init --

  /// Loads everything from Hive (instant), then refreshes from Firestore.
  Future<void> initialize() async {
    if (_isInitialized) {
      await refreshRankings();
      return;
    }
    _isInitialized = true;

    _loadFromHive();
    notifyListeners();

    await _normalizeLegacyBest();

    await loadInitialData();
    await _syncWithRemote();
  }

  /// Reads the persisted profile, stats and cached rankings out of Hive.
  void _loadFromHive() {
    final storedUser = HiveService.loadUser();
    if (storedUser != null) {
      _user = storedUser;
      _user.refreshDailyFlags(DateTime.now());
    }
    _stats = HiveService.loadStats();
    _config = SyncService.cachedConfig();
    _lastDailyRewardDate = HiveService.getMeta<String>('last_daily_reward_date');
    _champions = _rankings.cachedChampions();
    _leaderboard = _rankings.cachedLeaderboard();
  }

  /// Refreshes rankings, using the Hive cache while the network call runs.
  Future<void> loadInitialData() async {
    _isLoading = true;
    notifyListeners();

    _champions = _rankings.cachedChampions();
    _leaderboard = _rankings.cachedLeaderboard();

    await refreshRankings();

    _isLoading = false;
    notifyListeners();
  }

  /// Pull-to-refresh entry point.
  Future<void> refreshRankings({bool force = false}) async {
    try {
      if (force || !_rankings.isLeaderboardFresh(_config.leaderboardTtl)) {
        _leaderboard = await _rankings.refreshLeaderboard();
      }
      if (force || !_rankings.areChampionsFresh(_config.leaderboardTtl)) {
        _champions = await _rankings.refreshChampions();
      }
    } catch (e) {
      debugPrint('UserProvider: ranking refresh failed – $e');
    }
    notifyListeners();
  }

  /// Drains the offline queue and merges remote profile/stats/config.
  Future<void> _syncWithRemote() async {
    if (!SyncService.isOnline) return;
    try {
      await SyncService.drainPending();

      final remoteConfig = await SyncService.pullConfig();
      if (remoteConfig != null) _config = remoteConfig;

      if (!_user.isGuest) {
        _user = await SyncService.pullUser(_user);
        _stats = await SyncService.pullStats(_user.userId, _stats);
        await _normalizeLegacyBest();
        // Correct today's leaderboard entry if it holds a phantom legacy
        // score, or if the write that should have created it was lost.
        await _reconcileTodayLeaderboard();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('UserProvider: remote sync failed – $e');
    }
  }

  /// Resets an impossible lifetime-best daily score left over from the old
  /// time-bonus scoring (10 + seconds-remaining × 2 could reach 500+), so the
  /// profile and the "your position" card stop showing a phantom number like
  /// 370 after the flat 10-points-per-correct change. Mirrors the correction
  /// to Firestore so it never comes back on a reinstall.
  Future<void> _normalizeLegacyBest() async {
    // Today's per-day best (what gets pushed to the leaderboard) can also be
    // a phantom if the player used an old build earlier the same day.
    final dayKey = _todayKey();
    final counted = DailyScoreLock.countedRun(dayKey);
    if (counted != null && counted.score > kMaxPossibleDailyScore) {
      // Today's counted score is a phantom from an old build: drop it and
      // unlock the day so the player still gets a real counted run today.
      await DailyScoreLock.reset(dayKey);
    }

    if (_stats.bestDailyScore <= kMaxPossibleDailyScore) return;
    debugPrint(
      'UserProvider: resetting legacy best daily score '
      '${_stats.bestDailyScore} → 0',
    );
    _stats.bestDailyScore = 0;
    _stats.bestDailyTimeSeconds = 0;
    notifyListeners();
    await HiveService.saveStats(_stats);
    if (!_user.isGuest) {
      await SyncService.pushStats(_user.userId, _stats);
    }
  }

  /// Puts today's remote leaderboard row back in line with the player's
  /// counted run.
  ///
  /// The counted score in Hive is the source of truth, so the row is corrected
  /// whenever it disagrees — a phantom left by an old build (which pushed the
  /// *lifetime* best, e.g. 370), a lost write, or an entry the player posted
  /// before this device ever pushed it. Nothing happens when the player has no
  /// counted run today: only a counted run may create the row.
  Future<void> _reconcileTodayLeaderboard() async {
    if (_user.isGuest || _user.userId.isEmpty) return;
    final dayKey = _todayKey();
    final counted = DailyScoreLock.countedRun(dayKey);
    if (counted == null) return; // No counted run today — nothing to fix.

    final remote = await SyncService.pullLeaderboardEntry(_user.userId);
    final remoteScore = (remote?['score'] as num?)?.toInt();
    if (remoteScore == counted.score) return;

    debugPrint(
      'UserProvider: reconciling today leaderboard '
      '${remoteScore ?? '—'} → ${counted.score}',
    );
    await SyncService.pushLeaderboardEntry(
      user: _user,
      score: counted.score,
      timeSeconds: counted.timeSeconds,
    );
    await refreshRankings(force: true);
  }

  // ------------------------------------------------------------- Settings --

  /// Toggle settings persisted in Hive (`qb_meta`) and mirrored to Firestore
  /// with the profile, so they survive reinstalls.
  static const settingNotifications = 'setting_notifications';
  static const settingSound = 'setting_sound';
  static const settingVibration = 'setting_vibration';
  static const settingDarkMode = 'setting_dark_mode';

  bool setting(String key, {bool defaultValue = true}) =>
      HiveService.getMeta<bool>(key) ?? defaultValue;

  Future<void> setSetting(String key, bool value) async {
    await HiveService.setMeta(key, value);
    notifyListeners();
    if (key == settingNotifications || key == settingVibration) {
      unawaited(PushSync.syncFromHive());
    }
  }

  // ------------------------------------------------------------ Inventory --

  int inventoryCount(String itemId) => _user.inventoryCount(itemId);
  bool hasItem(String itemId) => inventoryCount(itemId) > 0;

  bool canAfford(ShopItem item) =>
      item.costsCoins ? _user.coins >= item.cost : _user.gems >= item.cost;

  PurchaseStatus purchaseItem(ShopItem item) {
    if (item.isCosmetic && (hasItem(item.id) || hasItem('cloud_avatar_${item.id}'))) {
      return PurchaseStatus.alreadyOwned;
    }
    if (!canAfford(item)) {
      return PurchaseStatus.insufficientFunds;
    }

    if (item.costsCoins) {
      _user.coins -= item.cost;
    } else {
      _user.gems -= item.cost;
    }

    // Handle special packs
    if (item.category == 'packs') {
      _handlePackPurchase(item);
    } else {
      _user.inventory[item.id] = inventoryCount(item.id) + item.quantity;
      if (item.category == 'avatars' || item.isCosmetic) {
        if (!item.id.startsWith('cloud_avatar_')) {
          _user.inventory['cloud_avatar_${item.id}'] = 1;
        } else {
          final rawId = item.id.replaceFirst('cloud_avatar_', '');
          _user.inventory[rawId] = 1;
        }
      }
    }

    notifyListeners();
    _persistUser();
    _savePurchaseHistory(item);

    // P0 (R02): mirror the purchase server-side (atomic wallet ledger,
    // idempotent per purchaseId). Fail-soft for guests/offline/not-deployed.
    if (!_user.isGuest) {
      final purchaseId =
          'p${DateTime.now().millisecondsSinceEpoch}x${item.id}';
      TrustedOpsService.purchaseItem(
        itemId: item.id,
        purchaseId: purchaseId,
      );
    }
    return PurchaseStatus.success;
  }

  /// Saves purchase history to Hive and mirrors to Firestore.
  Future<void> _savePurchaseHistory(ShopItem item) async {
    final history = PurchaseHistory(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userId: _user.userId,
      itemId: item.id,
      itemName: item.name,
      category: item.category,
      quantity: item.quantity,
      cost: item.cost,
      currency: item.costsCoins ? 'coins' : 'gems',
      purchasedAt: DateTime.now(),
    );
    final json = history.toJson();
    await HiveService.savePurchaseHistory(json);
    if (!_user.isGuest) {
      await SyncService.pushPurchaseHistory(_user.userId, json);
    }
  }

  /// Handles special pack purchases that grant multiple items.
  void _handlePackPurchase(ShopItem item) {
    switch (item.id) {
      case ShopItemIds.starterPack:
        // 5x 50-50 + 3x Freeze + 500 Coins
        _user.inventory[ShopItemIds.fiftyFifty] =
            inventoryCount(ShopItemIds.fiftyFifty) + 5;
        _user.inventory[ShopItemIds.freezeTime] =
            inventoryCount(ShopItemIds.freezeTime) + 3;
        _user.coins += 500;
        break;

      case ShopItemIds.megaPack:
        // 10x 50-50 + 5x Freeze + 5x Skip + 2000 Coins
        _user.inventory[ShopItemIds.fiftyFifty] =
            inventoryCount(ShopItemIds.fiftyFifty) + 10;
        _user.inventory[ShopItemIds.freezeTime] =
            inventoryCount(ShopItemIds.freezeTime) + 5;
        _user.inventory[ShopItemIds.skipQuestion] =
            inventoryCount(ShopItemIds.skipQuestion) + 5;
        _user.coins += 2000;
        break;

      case ShopItemIds.legendPack:
        // All lifelines x10 + VIP Avatar + 5000 Coins
        _user.inventory[ShopItemIds.fiftyFifty] =
            inventoryCount(ShopItemIds.fiftyFifty) + 10;
        _user.inventory[ShopItemIds.freezeTime] =
            inventoryCount(ShopItemIds.freezeTime) + 10;
        _user.inventory[ShopItemIds.skipQuestion] =
            inventoryCount(ShopItemIds.skipQuestion) + 10;
        _user.inventory[ShopItemIds.hintReveal] =
            inventoryCount(ShopItemIds.hintReveal) + 10;
        _user.inventory[ShopItemIds.audiencePoll] =
            inventoryCount(ShopItemIds.audiencePoll) + 10;
        _user.inventory[ShopItemIds.extraLife] =
            inventoryCount(ShopItemIds.extraLife) + 10;
        _user.inventory[ShopItemIds.doublePoints] =
            inventoryCount(ShopItemIds.doublePoints) + 10;
        _user.inventory[ShopItemIds.vipAvatar] = 1; // Unlock VIP Avatar
        _user.coins += 5000;
        break;
    }
  }

  /// Loads purchase history from Hive (instant) then refreshes from Firestore.
  Future<List<PurchaseHistory>> loadPurchaseHistory({int limit = 50}) async {
    // Load from Hive first (instant)
    final localData = HiveService.loadPurchaseHistory();
    var history = localData.map(PurchaseHistory.fromJson).toList();

    // Refresh from Firestore if online
    if (!_user.isGuest && SyncService.isOnline) {
      try {
        final remoteData =
            await SyncService.pullPurchaseHistory(_user.userId, limit: limit);
        if (remoteData.isNotEmpty) {
          history = remoteData.map(PurchaseHistory.fromJson).toList();
        }
      } catch (e) {
        debugPrint('UserProvider: purchase history refresh failed – $e');
      }
    }

    return history;
  }

  bool consumeItem(String itemId) {
    final count = inventoryCount(itemId);
    if (count <= 0) return false;

    _user.inventory[itemId] = count - 1;
    notifyListeners();
    _persistUser();
    return true;
  }

  // -------------------------------------------------------------- Rewards --

  /// Day key of the *competition* day (one fixed timezone for everybody).
  ///
  /// The leaderboard rows, the local daily-best markers and the reward
  /// once-per-day guards all have to agree on what "today" is: with a
  /// device-local date a player who travels (or whose phone is in another
  /// timezone) could post two scores for one competition day, or see a
  /// yesterday cache as today's standings (R12).
  static String _dateKey(DateTime d) => CompetitionClock.dateKey(d);

  static String _todayKey() => _dateKey(DateTime.now());

  bool get canEarnDailyRewards => _lastDailyRewardDate != _todayKey();

  /// Detects a lost daily streak (a full day was missed) and resets it.
  ///
  /// Returns the details for the reset dialog, or null. The reset actually
  /// happens here — before, the old streak stayed on the profile so the
  /// dashboard still showed e.g. "12 days" while the dialog claimed it was
  /// lost, and the same warning nagged on every app open. Now:
  ///   * the streak is zeroed once and pushed, so every streak UI is
  ///     consistent and the dialog never repeats;
  ///   * `UserStats.longestStreak` (history) is untouched.
  StreakResetDetails? checkStreakResetWarning() {
    final now = DateTime.now();
    final today = _dateKey(now);
    final yesterday = _dateKey(now.subtract(const Duration(days: 1)));

    final lastDate = _user.lastStreakDate;
    if (lastDate == null || lastDate == today || lastDate == yesterday) {
      return null;
    }

    final lostStreak = _user.dailyStreak;
    if (lostStreak <= 0) return null;

    final String lastWarnedDate =
        HiveService.getMeta<String>('warned_streak_reset_date') ?? '';
    if (lastWarnedDate == today) return null;

    // The streak is truly gone — zero it now and persist, so the flame card,
    // calendar dots and profile all agree with the dialog.
    _user.dailyStreak = 0;
    notifyListeners();
    _persistUser();

    // Record warned today.
    HiveService.setMeta('warned_streak_reset_date', today);

    return StreakResetDetails(
      lostStreak: lostStreak,
      hasShield: hasItem(ShopItemIds.streakShield),
    );
  }

  /// Restores player's streak using 1 Streak Freeze Shield from inventory.
  bool restoreStreakWithShield(int lostStreak) {
    if (lostStreak <= 0) return false;
    if (!consumeItem(ShopItemIds.streakShield)) return false;
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final m = yesterday.month.toString().padLeft(2, '0');
    final d = yesterday.day.toString().padLeft(2, '0');
    _user.lastStreakDate = '${yesterday.year}-$m-$d';
    _user.dailyStreak = lostStreak;
    notifyListeners();
    _persistUser();
    return true;
  }

  /// Checks yesterday's leaderboard rank and automatically claims shop gifts,
  /// coins, gems, and winning streak grand prizes if player placed in Top 10!
  Future<DailyRewardResult?> checkAndClaimDailyLeaderboardRewards() async {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    final m = yesterday.month.toString().padLeft(2, '0');
    final d = yesterday.day.toString().padLeft(2, '0');
    final yesterdayKey = '${yesterday.year}-$m-$d';

    final claimedKey = 'claimed_daily_rank_$yesterdayKey';
    if (HiveService.getMeta<bool>(claimedKey) == true) return null;

    if (_user.username.isEmpty || _user.isGuest) return null;

    try {
      // Pull yesterday's champions / leaderboard, then only look at the
      // rows that actually belong to yesterday's winners.
      final champions = await _rankings.refreshChampions(limit: 10, days: 1);
      final yesterdayWinners =
          champions.where((c) => c.dateKey == yesterdayKey).toList();
      var userRank = -1;

      for (var i = 0; i < yesterdayWinners.length; i++) {
        if (championRowBelongsToUser(
          yesterdayWinners[i],
          userId: _user.userId,
        )) {
          userRank = i + 1;
          break;
        }
      }

      if (userRank <= 0 || userRank > 10) return null;

      // Mark as claimed for yesterday
      await HiveService.setMeta(claimedKey, true);

      int coins = 0;
      int gems = 0;
      final itemNames = <String>[];
      final itemIdsToGrant = <String>[];

      if (userRank == 1) {
        coins = 100;
        gems = 10;
        itemIdsToGrant.add(ShopItemIds.freezeTime);
        itemNames.add('+10s Freeze Time');
      } else if (userRank == 2) {
        coins = 50;
        gems = 5;
        itemIdsToGrant.add(ShopItemIds.fiftyFifty);
        itemNames.add('50-50 Lifeline');
      } else if (userRank == 3) {
        coins = 30;
        gems = 2;
      } else {
        coins = 15;
        gems = 1;
      }

      // Track Winning Streak
      var streak = (HiveService.getMeta<int>('winning_streak') ?? 0);
      if (userRank <= 3) {
        streak += 1;
      } else {
        streak = 0;
      }
      await HiveService.setMeta('winning_streak', streak);

      String? milestoneTitle;
      if (streak == 3) {
        milestoneTitle = '3-Day Streak Bonus';
        gems += 20;
        itemIdsToGrant.add(ShopItemIds.streakShield);
        itemNames.add('Streak Freeze Shield (+20 Gems)');
      } else if (streak == 7) {
        milestoneTitle = '7-Day Champion Bonus';
        gems += 50;
        itemIdsToGrant.add(ShopItemIds.coinBooster);
        itemNames.add('2x Coin Booster (+50 Gems)');
      } else if (streak >= 14 && streak % 7 == 0) {
        milestoneTitle = 'Quiz Monarch Bonus';
        gems += 100;
        itemIdsToGrant.add(ShopItemIds.championBadge);
        itemNames.add('Champion Badge (+100 Gems)');
      }

      // Credit Coins & Gems
      _user.coins += coins;
      _user.gems += gems;

      // Credit items to inventory
      for (final id in itemIdsToGrant) {
        _user.inventory[id] = inventoryCount(id) + 1;
        if (id.startsWith('vip_avatar') || id.startsWith('golden_avatar')) {
          _user.inventory['cloud_avatar_$id'] = 1;
        }
      }

      notifyListeners();
      await _persistUser();

      return DailyRewardResult(
        rank: userRank,
        coins: coins,
        gems: gems,
        itemNames: itemNames,
        winningStreak: streak,
        milestonePrizeTitle: milestoneTitle,
      );
    } catch (e) {
      debugPrint('UserProvider: checkAndClaimDailyLeaderboardRewards failed – $e');
      return null;
    }
  }

  bool grantQuizRewards({
    required int coins,
    required int gems,
    required bool isDailyQuiz,
  }) {
    if (isDailyQuiz) {
      final today = _todayKey();
      if (_lastDailyRewardDate == today) return false;
      _lastDailyRewardDate = today;
      HiveService.setMeta('last_daily_reward_date', today);
    }

    _user.coins += coins;
    _user.gems += gems;
    notifyListeners();
    _persistUser();
    return true;
  }

  /// Grants XP based on quiz performance. Returns true if the player leveled up.
  bool grantXp({required int score, required int correctCount, required bool isDailyQuiz}) {
    int baseXp = correctCount * 10;
    if (isDailyQuiz) baseXp += score * 2;

    // Apply XP booster if active
    if (hasItem(ShopItemIds.xpBooster)) {
      baseXp *= 2;
      consumeItem(ShopItemIds.xpBooster);
    }

    _user.xp += baseXp;

    // Level up: every 1000 XP = 1 level
    final newLevel = (_user.xp ~/ 1000) + 1;
    final leveledUp = newLevel > _user.level;
    if (leveledUp) {
      _user.level = newLevel;
      // Bonus gems on level up
      _user.gems += 5 * (newLevel - _user.level + 1);
    }

    notifyListeners();
    _persistUser();
    return leveledUp;
  }

  int get userXp => _user.xp;
  int get userLevel => _user.level;
  int get xpForNextLevel => ((_user.level) * 1000) - _user.xp;
  double get xpProgressPercent {
    final currentLevelXp = (_user.level - 1) * 1000;
    final nextLevelXp = _user.level * 1000;
    final range = nextLevelXp - currentLevelXp;
    if (range == 0) return 1.0;
    return (_user.xp - currentLevelXp) / range;
  }

  // ---------------------------------------------------------------- Stats --

  /// Records a finished quiz: updates [UserStats], the daily streak and —
  /// when it is the player's first ranked run of the day — the leaderboard
  /// entry. Everything lands in Hive first.
  ///
  /// Returns what the run did to today's leaderboard row, so the result screen
  /// can tell the player whether their score counted.
  Future<DailyScoreOutcome> recordQuizResult({
    required int answered,
    required int correct,
    required double timeSeconds,
    required bool isDaily,
    /// Whether this daily run may be ranked. Unranked runs (the practice
    /// fallback when no packet is available) are recorded as quiz history and
    /// feed stats/streak, but never touch the day's leaderboard row (R12).
    bool ranked = true,
    int? score,
    String? chapterId,
    String? categoryTitle,
    String? categoryTitleBn,
    String? chapterTitle,
    String? chapterTitleBn,
    int? coinsEarned,
    int? gemsEarned,
  }) async {
    _stats.recordQuiz(
      answered: answered,
      correct: correct,
      timeSeconds: timeSeconds,
      chapterId: chapterId,
      isDaily: isDaily,
      dailyScore: score,
    );

    if (isDaily) {
      // Check for streak shield before updating streak. This is the fallback
      // auto-freeze path (used when the reset was not seen, e.g. the app was
      // reopened straight into the quiz): if the streak was just reset to 1
      // and the player owned a shield, the shield restores it.
      final hadStreakShield = hasItem(ShopItemIds.streakShield);
      final previousStreak = _user.dailyStreak;

      _user.registerPlayOn(DateTime.now());

      // If streak was reset (went to 1) but shield is active, restore streak
      if (hadStreakShield && _user.dailyStreak == 1 && previousStreak > 1) {
        consumeItem(ShopItemIds.streakShield);
        _user.dailyStreak = previousStreak; // Restore previous streak
      }

      _stats.touchStreak(_user.dailyStreak);
    }

    notifyListeners();

    await HiveService.saveStats(_stats);
    await HiveService.saveUser(_user);

    // Save quiz result history
    final wrong = answered - correct;
    final accuracy = answered > 0 ? (correct / answered) * 100 : 0.0;
    final history = QuizResultHistory(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userId: _user.userId,
      quizType: isDaily ? 'daily' : 'chapter',
      categoryTitle: categoryTitle,
      categoryTitleBn: categoryTitleBn,
      chapterTitle: chapterTitle,
      chapterTitleBn: chapterTitleBn,
      chapterId: chapterId,
      totalQuestions: answered,
      correctAnswers: correct,
      wrongAnswers: wrong,
      score: score ?? 0,
      coinsEarned: coinsEarned ?? 0,
      gemsEarned: gemsEarned ?? 0,
      timeSeconds: timeSeconds,
      accuracy: accuracy,
      playedAt: DateTime.now(),
    );
    await _saveQuizHistory(history);

    final outcome = isDaily && ranked && !_user.isGuest
        // One counted score per competition day — see [DailyScoreLock].
        ? await _settleDailyScore(
            score: score ?? 0,
            timeSeconds: timeSeconds,
          )
        : DailyScoreOutcome.notApplicable;

    await SyncService.pushUser(_user);
    await SyncService.pushStats(_user.userId, _stats);
    if (isDaily) {
      unawaited(PushSync.syncFromHive());
    }
    return outcome;
  }

  /// Applies the one-score-per-day rule to a finished ranked daily run.
  ///
  /// The first ranked run of the day is written to the leaderboard and locks
  /// the day; every later run is ignored by the ranking (it still lands in the
  /// player's own history, stats and streak). A Score Shield reopens the day
  /// for exactly one more run, which then *replaces* the locked score.
  Future<DailyScoreOutcome> _settleDailyScore({
    required int score,
    required double timeSeconds,
  }) async {
    final dayKey = _todayKey();
    final retry = DailyScoreLock.isRetryUnlocked(dayKey);

    if (DailyScoreLock.isLocked(dayKey) && !retry) {
      final locked = DailyScoreLock.countedRun(dayKey);
      await DailyScoreLock.registerAttempt(dayKey);
      debugPrint(
        'UserProvider: $dayKey is already locked at ${locked?.score ?? 0} — '
        'this run ($score) is not counted',
      );
      notifyListeners();
      return DailyScoreOutcome.ignored;
    }

    await DailyScoreLock.lock(
      dayKey,
      score: score,
      timeSeconds: timeSeconds,
    );
    await DailyScoreLock.registerAttempt(dayKey);
    notifyListeners();

    await SyncService.pushLeaderboardEntry(
      user: _user,
      score: score,
      timeSeconds: timeSeconds,
    );
    await refreshRankings(force: true);
    return retry ? DailyScoreOutcome.replaced : DailyScoreOutcome.counted;
  }

  /// Spends a Score Shield to reopen today's locked leaderboard score.
  ///
  /// Only one retry is sold per day, however many shields the player owns:
  /// buying unlimited attempts would put back the grind this rule removes.
  ///
  /// Returns false when there is nothing to replace (no counted run today, a
  /// retry is already open, or the day's one retry is used up) or when the
  /// player owns no shield — a shield is never spent for nothing. When it
  /// succeeds, the player's next ranked daily run replaces today's score and
  /// locks the day again.
  Future<bool> unlockDailyScoreWithShield() async {
    if (!canRetryDailyScoreWithShield) return false;
    consumeItem(ShopItemIds.scoreShield);
    await DailyScoreLock.unlockForRetry(_todayKey());
    debugPrint('UserProvider: score shield opened a retry for ${_todayKey()}');
    notifyListeners();
    return true;
  }

  /// Saves quiz history to Hive and mirrors to Firestore.
  Future<void> _saveQuizHistory(QuizResultHistory history) async {
    final json = history.toJson();
    await HiveService.saveQuizHistory(json);
    if (!_user.isGuest) {
      await SyncService.pushQuizHistory(_user.userId, json);
    }
  }

  /// Loads quiz history from Hive (instant) then refreshes from Firestore.
  Future<List<QuizResultHistory>> loadQuizHistory({int limit = 50}) async {
    // Load from Hive first (instant)
    final localData = HiveService.loadQuizHistory();
    var history =
        localData.map(QuizResultHistory.fromJson).toList();

    // Refresh from Firestore if online
    if (!_user.isGuest && SyncService.isOnline) {
      try {
        final remoteData =
            await SyncService.pullQuizHistory(_user.userId, limit: limit);
        if (remoteData.isNotEmpty) {
          history = remoteData.map(QuizResultHistory.fromJson).toList();
        }
      } catch (e) {
        debugPrint('UserProvider: quiz history refresh failed – $e');
      }
    }

    return history;
  }

  /// Records a battle result.
  Future<void> recordBattleResult({required bool won}) async {
    _stats.recordBattle(won: won);
    notifyListeners();
    await HiveService.saveStats(_stats);
    await SyncService.pushStats(_user.userId, _stats);
  }

  /// Kept for older call sites: updates the personal best only.
  bool updateDailyBest({required int score, required double timeSeconds}) {
    final isBest = score > _stats.bestDailyScore ||
        (score == _stats.bestDailyScore &&
            score > 0 &&
            (_stats.bestDailyTimeSeconds == 0 ||
                timeSeconds < _stats.bestDailyTimeSeconds));
    if (isBest) {
      _stats.bestDailyScore = score;
      _stats.bestDailyTimeSeconds = timeSeconds;
      notifyListeners();
      HiveService.saveStats(_stats);
    }
    return isBest;
  }

  // -------------------------------------------------------------- Profile --

  void toggleGender() {
    _user.toggleGender();
    notifyListeners();
    _persistUser();
    _refreshLeaderboardAvatar();
  }

  void setGuestMode(bool isGuest) {
    _user = UserModel.newPlayer(isGuest: isGuest);
    _stats = UserStats.empty();
    notifyListeners();
    HiveService.saveStats(_stats);
    _persistUser();
  }

  void updateUsername(String newUsername) {
    _user.username = newUsername;
    notifyListeners();
    _persistUser();
  }

  void updateGender(UserGender gender) {
    _user.setGender(gender);
    notifyListeners();
    _persistUser();
    _refreshLeaderboardAvatar();
  }

  /// Updates the user's avatar.
  ///
  /// Local assets are stored in [avatarPath]. Remote/cloud avatars are stored
  /// in [avatarUrl] while keeping [avatarPath] as a safe local fallback for
  /// older widgets that still use AssetImage.
  void updateAvatar(String avatarPath) {
    final isRemoteAvatar = avatarPath.startsWith('http://') || avatarPath.startsWith('https://');
    if (isRemoteAvatar) {
      _user.avatarUrl = avatarPath;
      if (_user.avatarPath.startsWith('http://') ||
          _user.avatarPath.startsWith('https://') ||
          _user.avatarPath.isEmpty) {
        _user.avatarPath = _user.gender == UserGender.male
            ? 'assets/images/avatars/quizbaaz_avatar_boy.png'
            : 'assets/images/avatars/quizbaaz_avatar_girl.png';
      }
    } else {
      _user.avatarPath = avatarPath;
      _user.avatarUrl = null;
    }
    notifyListeners();
    _persistUser();
    _refreshLeaderboardAvatar();
  }

  /// Applies a name effect (or clears it when [effectId] is null).
  ///
  /// The chosen effect is stored on the profile, mirrored to Firestore and
  /// re-pushed to today's leaderboard entry so other players see it too.
  void setNameEffect(String? effectId) {
    _user.nameEffect = effectId;
    notifyListeners();
    _persistUser();
    _refreshLeaderboardAvatar();
  }

  /// Whether the player owns the given cosmetic name effect.
  bool ownsNameEffect(String effectId) => hasItem(effectId);

  /// Links a Google account, keeping all local progress.
  Future<void> linkGoogleAccount(
    String fullName,
    String email, {
    String? photoURL,
    String? uid,
  }) async {
    final wasGuest = _user.isGuest;
    _user = UserModel(
      userId: uid ?? email,
      username: email.split('@').first,
      fullName: fullName,
      avatarPath: _user.avatarPath,
      avatarUrl: photoURL,
      nameEffect: _user.nameEffect,
      gender: _user.gender,
      coins: _user.coins + (wasGuest ? _config.signupBonusCoins : 0),
      gems: _user.gems + (wasGuest ? _config.signupBonusGems : 0),
      dailyStreak: _user.dailyStreak,
      xp: _user.xp,
      level: _user.level,
      isGuest: false,
      playedTodayDailyQuiz: _user.playedTodayDailyQuiz,
      isAdmin: _user.isAdmin,
      lastStreakDate: _user.lastStreakDate,
      inventory: _user.inventory,
    );
    notifyListeners();

    await HiveService.saveUser(_user);
    _user = await SyncService.pullUser(_user);
    _stats = await SyncService.pullStats(_user.userId, _stats);
    notifyListeners();
    await SyncService.pushUser(_user);
    await SyncService.pushStats(_user.userId, _stats);
    unawaited(PushSync.syncFromHive());
  }

  void saveProfile({
    required String username,
    required String fullName,
    required UserGender gender,
  }) {
    _user = _user.copyWith(
      username: username,
      fullName: fullName,
      gender: gender,
      avatarPath: gender == UserGender.male
          ? 'assets/images/avatars/quizbaaz_avatar_boy.png'
          : 'assets/images/avatars/quizbaaz_avatar_girl.png',
    );
    notifyListeners();
    _persistUser();
    _refreshLeaderboardAvatar();
  }

  /// Sign-out: clears the local profile and every cached value.
  Future<void> signOutLocal() async {
    await HiveService.clearAll();
    _user = UserModel.newPlayer();
    _stats = UserStats.empty();
    _champions = const [];
    _leaderboard = const [];
    _lastDailyRewardDate = null;
    notifyListeners();
    unawaited(PushSync.syncFromHive());
  }

  // ---------------------------------------------------------- Persistence --

  Future<void> _persistUser() async {
    await HiveService.saveUser(_user);
    await SyncService.pushUser(_user);
  }

  /// Re-syncs today's leaderboard entry with the player's current avatar.
  ///
  /// The leaderboard entry is normally written once when the daily quiz is
  /// finished. If the player changes their avatar afterwards, the home screen
  /// leaderboard preview and champion card would still show the stale one.
  /// This re-pushes the entry (Firestore merges by user id) so the freshly
  /// chosen avatar shows up immediately. Skipped for guests and for players
  /// who haven't played today's daily quiz (no entry to update).
  ///
  /// The score re-pushed here is TODAY's counted score (from Hive meta),
  /// never the lifetime [UserStats.bestDailyScore] — pushing the lifetime best
  /// could resurrect a phantom legacy score (e.g. 370) into today's ranking,
  /// and a later run must never overwrite the one that counted.
  Future<void> _refreshLeaderboardAvatar() async {
    if (_user.isGuest || !_user.playedTodayDailyQuiz) return;
    final counted = DailyScoreLock.countedRun(_todayKey());
    if (counted == null) return; // no counted run today — no entry to update
    await SyncService.pushLeaderboardEntry(
      user: _user,
      score: counted.score,
      timeSeconds: counted.timeSeconds,
    );
  }
}
