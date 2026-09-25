import 'hive_service.dart';

/// What a finished daily run did to the player's leaderboard row.
enum DailyScoreOutcome {
  /// Not a rankable daily run: a chapter quiz, an unranked (practice) daily
  /// run, or a guest — nothing was ever going to be counted.
  notApplicable,

  /// The run is today's leaderboard score: it was the first ranked run of
  /// the competition day.
  counted,

  /// A Score Shield reopened the day and this run replaced the old score.
  replaced,

  /// Today already had a counted score, so this run was played for coins, XP
  /// and the streak only — the leaderboard row was left exactly as it was.
  ignored,
}

/// The one-score-per-day rule for the daily competition.
///
/// A competition day, one score per player:
///
/// * the **first** ranked run of the day is written to
///   `leaderboard/{yyyy-MM-dd}/scores/{uid}` and the day is then **locked**;
/// * every later ranked run that day is played normally (history, stats,
///   streak and — on the first run — coins/gems/XP) but never touches the
///   leaderboard row, not even with a much better score;
/// * the only way to reopen a locked day is a **Score Shield** (see
///   [UserProvider.unlockDailyScoreWithShield]): it buys **one** retry, whose
///   run replaces the locked score and re-locks the day. One per day, however
///   many shields the player owns.
///
/// Why "first", not "best": a daily competition is one attempt at a shared
/// set of questions, not a grind for a high score. Best-of-day quietly turned
/// the leaderboard into "who had time to replay", and it made the row jump
/// around all evening while the player watched it. One attempt, one number.
///
/// Everything lives in Hive (`qb_meta`), keyed by the **competition** day, so
/// a player who travels cannot unlock a second attempt by changing timezone
/// (R12). The trusted backend enforces the same shape independently:
/// `submitDailyResult` in `functions/src/daily.ts` is idempotent per day.
class DailyScoreLock {
  DailyScoreLock._();

  /// Hive key of the score counted for [dayKey].
  ///
  /// The key is still the historical `daily_best_score_*` one on purpose: a
  /// build that ships in the middle of a competition day must not orphan the
  /// score the player already posted that morning. The *meaning* changed (the
  /// first counted run, not the best of the day); the storage did not.
  static String scoreKey(String dayKey) => 'daily_best_score_$dayKey';

  /// Hive key of the time (seconds) of the counted run, for the tie-breaker.
  static String timeKey(String dayKey) => 'daily_best_time_$dayKey';

  /// Hive key of the "this day already has a counted score" flag.
  static String lockedKey(String dayKey) => 'daily_score_locked_$dayKey';

  /// Hive key of how many ranked runs the player finished that day.
  static String attemptKey(String dayKey) => 'daily_score_attempts_$dayKey';

  /// Hive key of "a Score Shield reopened this day" flag.
  static String retryKey(String dayKey) => 'daily_score_retry_$dayKey';

  /// Hive key of how many Score Shield retries the player used that day.
  ///
  /// Capped at one on purpose: a player with a stack of shields buying an
  /// unlimited number of attempts is exactly the grind the one-attempt rule
  /// removes.
  static String retriesUsedKey(String dayKey) =>
      'daily_score_retries_used_$dayKey';

  /// True when the day already carries a counted score.
  static bool isLocked(String dayKey) =>
      HiveService.getMeta<bool>(lockedKey(dayKey)) ?? false;

  /// True when a Score Shield has reopened the day: the next ranked run
  /// replaces the locked score instead of being ignored.
  static bool isRetryUnlocked(String dayKey) =>
      HiveService.getMeta<bool>(retryKey(dayKey)) ?? false;

  /// How many ranked runs the player finished on [dayKey].
  static int attempts(String dayKey) =>
      HiveService.getMeta<int>(attemptKey(dayKey)) ?? 0;

  /// How many Score Shield retries the player has spent on [dayKey] (0 or 1).
  static int retriesUsed(String dayKey) =>
      HiveService.getMeta<int>(retriesUsedKey(dayKey)) ?? 0;

  /// The counted run of [dayKey] — its score and the time it took — or null
  /// when the player has no counted run that day.
  ///
  /// A locked day with a zero score still counts (the player posted a zero and
  /// the row must not be rewritten by a replay), and a score without the flag
  /// is honoured too: that is a player who played with the previous build
  /// earlier the same day.
  static ({int score, double timeSeconds})? countedRun(String dayKey) {
    final score = HiveService.getMeta<int>(scoreKey(dayKey)) ?? 0;
    if (score <= 0 && !isLocked(dayKey)) return null;
    return (
      score: score,
      timeSeconds: HiveService.getMeta<double>(timeKey(dayKey)) ?? 0.0,
    );
  }

  /// Stores [score] as the day's counted run and locks the day.
  ///
  /// Consumes the retry flag when one was open: the replacement run has been
  /// played, so the day is locked again.
  static Future<void> lock(
    String dayKey, {
    required int score,
    required double timeSeconds,
  }) async {
    await HiveService.setMeta(scoreKey(dayKey), score);
    await HiveService.setMeta(timeKey(dayKey), timeSeconds);
    await HiveService.setMeta(lockedKey(dayKey), true);
    await HiveService.setMeta(retryKey(dayKey), false);
  }

  /// Counts one more finished ranked run for [dayKey] and returns the total.
  static Future<int> registerAttempt(String dayKey) async {
    final next = attempts(dayKey) + 1;
    await HiveService.setMeta(attemptKey(dayKey), next);
    return next;
  }

  /// Reopens a locked day for the player's next ranked run (Score Shield)
  /// and counts the retry — a day can only be reopened once.
  static Future<void> unlockForRetry(String dayKey) async {
    await HiveService.setMeta(retryKey(dayKey), true);
    await HiveService.setMeta(retriesUsedKey(dayKey), retriesUsed(dayKey) + 1);
  }

  /// Drops the day's counted score and unlocks the day.
  ///
  /// Only used when the stored value is impossible — a phantom left behind by
  /// an old build's time-bonus scoring — so the player still gets a real
  /// counted run for that day.
  static Future<void> reset(String dayKey) async {
    await HiveService.setMeta(scoreKey(dayKey), 0);
    await HiveService.setMeta(timeKey(dayKey), 0.0);
    await HiveService.setMeta(lockedKey(dayKey), false);
    await HiveService.setMeta(retryKey(dayKey), false);
    await HiveService.setMeta(retriesUsedKey(dayKey), 0);
  }
}
