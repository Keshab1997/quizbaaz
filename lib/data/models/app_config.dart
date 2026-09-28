/// Remote-controllable app configuration.
///
/// Everything that used to be a magic number sprinkled across the UI lives
/// here. Defaults are the app's built-in game rules (not fake user data);
/// they are overridden by the Firestore document `config/app` and cached in
/// Hive so the app boots with the correct values while offline.
class AppConfig {
  /// How many questions a daily quiz contains.
  final int dailyQuestionCount;

  /// Seconds allowed per question.
  final int secondsPerQuestion;

  /// Coins granted per correct answer in the daily quiz.
  final int coinsPerCorrectDaily;

  /// Extra coins for a perfect daily run.
  final int perfectBonusCoins;

  /// Coins granted per correct answer in practice / chapter quizzes.
  final int coinsPerCorrectPractice;

  /// Gems for a perfect run.
  final int gemsPerfect;

  /// Gems for a high (but not perfect) score.
  final int gemsHighScore;

  /// Minimum correct answers needed for [gemsHighScore].
  final int highScoreThreshold;

  /// One-time bonus when a guest links a real account.
  final int signupBonusCoins;
  final int signupBonusGems;

  /// Length of the streak ring shown on the dashboard.
  final int streakGoalDays;

  /// Battle length (1v1 questions per match).
  final int battleQuestionCount;

  /// Base points for a correct battle answer (both sides).
  final int battleBasePoints;

  /// Max time-scaled speed bonus: instant answer pays it all, answering with
  /// the last second pays ~0 (Kahoot-style continuous speed scoring).
  final int battleSpeedBonus;

  /// Flat race bonus: locked in before the opponent answered.
  /// Flat bonus for locking in an answer before the opponent (default 2).
  final int battleFirstBonus;

  /// Bonus per consecutive correct answer streak (multiplied by streak count).
  final int battleStreakBonus;

  /// Cap for the streak bonus so long battles can't snowball forever (default 6).
  final int battleMaxStreakBonus;

  /// Seconds spent looking for a real player before falling back to a bot
  /// (guests and offline players use a short 3 s scan).
  final int battleSearchSeconds;

  /// User ids allowed to open the admin panel.
  final List<String> adminUserIds;

  /// Minutes before cached leaderboard data is considered stale.
  final int leaderboardCacheMinutes;

  const AppConfig({
    this.dailyQuestionCount = 10,
    this.secondsPerQuestion = 30,
    this.coinsPerCorrectDaily = 50,
    this.perfectBonusCoins = 100,
    this.coinsPerCorrectPractice = 25,
    this.gemsPerfect = 10,
    this.gemsHighScore = 5,
    this.highScoreThreshold = 8,
    this.signupBonusCoins = 500,
    this.signupBonusGems = 20,
    this.streakGoalDays = 7,
    this.battleQuestionCount = 5,
    this.battleBasePoints = 10,
    this.battleSpeedBonus = 10,
    this.battleFirstBonus = 2,
    this.battleStreakBonus = 2,
    this.battleMaxStreakBonus = 6,
    this.battleSearchSeconds = 6,
    this.adminUserIds = const <String>[],
    this.leaderboardCacheMinutes = 10,
  });

  /// Maximum points a single battle question can pay out
  /// (base 10 + speed 10 + first 2 + capped streak 6 = 28).
  int get battleMaxPointsPerQuestion =>
      battleBasePoints +
      battleSpeedBonus +
      battleFirstBonus +
      battleMaxStreakBonus;

  /// Total seconds a full daily quiz can take.
  int get dailyTotalSeconds => dailyQuestionCount * secondsPerQuestion;

  /// `mm:ss` label for the daily quiz duration.
  String get dailyDurationLabel {
    final total = dailyTotalSeconds;
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Maximum coins a perfect daily run can pay out.
  int get dailyMaxCoins =>
      dailyQuestionCount * coinsPerCorrectDaily + perfectBonusCoins;

  /// How long cached leaderboard/champion data stays fresh.
  Duration get leaderboardTtl => Duration(minutes: leaderboardCacheMinutes);

  bool isAdmin(String userId) =>
      userId.isNotEmpty && adminUserIds.contains(userId);

  Map<String, dynamic> toJson() => {
    'daily_question_count': dailyQuestionCount,
    'seconds_per_question': secondsPerQuestion,
    'coins_per_correct_daily': coinsPerCorrectDaily,
    'perfect_bonus_coins': perfectBonusCoins,
    'coins_per_correct_practice': coinsPerCorrectPractice,
    'gems_perfect': gemsPerfect,
    'gems_high_score': gemsHighScore,
    'high_score_threshold': highScoreThreshold,
    'signup_bonus_coins': signupBonusCoins,
    'signup_bonus_gems': signupBonusGems,
    'streak_goal_days': streakGoalDays,
    'battle_question_count': battleQuestionCount,
    'battle_base_points': battleBasePoints,
    'battle_speed_bonus': battleSpeedBonus,
    'battle_first_bonus': battleFirstBonus,
    'battle_streak_bonus': battleStreakBonus,
    'battle_max_streak_bonus': battleMaxStreakBonus,
    'battle_search_seconds': battleSearchSeconds,
    'admin_user_ids': adminUserIds,
    'leaderboard_cache_minutes': leaderboardCacheMinutes,
  };

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    const fallback = AppConfig();
    int intOr(String key, int def) => (json[key] as num?)?.toInt() ?? def;
    return AppConfig(
      dailyQuestionCount: intOr(
        'daily_question_count',
        fallback.dailyQuestionCount,
      ),
      secondsPerQuestion: intOr(
        'seconds_per_question',
        fallback.secondsPerQuestion,
      ),
      coinsPerCorrectDaily: intOr(
        'coins_per_correct_daily',
        fallback.coinsPerCorrectDaily,
      ),
      perfectBonusCoins: intOr(
        'perfect_bonus_coins',
        fallback.perfectBonusCoins,
      ),
      coinsPerCorrectPractice: intOr(
        'coins_per_correct_practice',
        fallback.coinsPerCorrectPractice,
      ),
      gemsPerfect: intOr('gems_perfect', fallback.gemsPerfect),
      gemsHighScore: intOr('gems_high_score', fallback.gemsHighScore),
      highScoreThreshold: intOr(
        'high_score_threshold',
        fallback.highScoreThreshold,
      ),
      signupBonusCoins: intOr('signup_bonus_coins', fallback.signupBonusCoins),
      signupBonusGems: intOr('signup_bonus_gems', fallback.signupBonusGems),
      streakGoalDays: intOr('streak_goal_days', fallback.streakGoalDays),
      battleQuestionCount: intOr(
        'battle_question_count',
        fallback.battleQuestionCount,
      ),
      battleBasePoints: intOr('battle_base_points', fallback.battleBasePoints),
      battleSpeedBonus: intOr('battle_speed_bonus', fallback.battleSpeedBonus),
      battleFirstBonus: intOr('battle_first_bonus', fallback.battleFirstBonus),
      battleStreakBonus: intOr(
        'battle_streak_bonus',
        fallback.battleStreakBonus,
      ),
      battleMaxStreakBonus: intOr(
        'battle_max_streak_bonus',
        fallback.battleMaxStreakBonus,
      ),
      battleSearchSeconds: intOr(
        'battle_search_seconds',
        fallback.battleSearchSeconds,
      ),
      adminUserIds:
          (json['admin_user_ids'] as List<dynamic>?)
              ?.map((e) => '$e')
              .toList() ??
          const <String>[],
      leaderboardCacheMinutes: intOr(
        'leaderboard_cache_minutes',
        fallback.leaderboardCacheMinutes,
      ),
    );
  }
}
