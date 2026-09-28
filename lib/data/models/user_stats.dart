/// Gameplay statistics for the current user.
///
/// Stored in Hive (`qb_stats` box) and synced to Firestore under
/// `users/{userId}/stats/summary`. Every number the UI shows about the
/// player's performance must come from here — never hardcoded.
class UserStats {
  /// Total questions the user has answered (all quiz modes).
  int totalAnswered;

  /// How many of those were correct.
  int totalCorrect;

  /// Total finished quizzes (daily + chapter + battle).
  int totalQuizzes;

  /// Daily-quiz personal bests.
  int bestDailyScore;
  double bestDailyTimeSeconds;

  /// Cumulative time spent answering, in seconds.
  double totalTimeSeconds;

  /// Battle record.
  int battlesPlayed;
  int battlesWon;

  /// Longest streak ever reached (current streak lives on UserModel).
  int longestStreak;

  /// Chapter id -> number of correct answers in that chapter.
  Map<String, int> chapterCorrect;

  /// Chapter id -> number of questions attempted in that chapter.
  Map<String, int> chapterAttempted;

  /// `yyyy-MM-dd` of the last day the user played anything.
  String? lastPlayedDate;

  /// Last time these stats were pushed to / pulled from Firestore.
  int? lastSyncedAtMs;

  UserStats({
    this.totalAnswered = 0,
    this.totalCorrect = 0,
    this.totalQuizzes = 0,
    this.bestDailyScore = 0,
    this.bestDailyTimeSeconds = 0,
    this.totalTimeSeconds = 0,
    this.battlesPlayed = 0,
    this.battlesWon = 0,
    this.longestStreak = 0,
    Map<String, int>? chapterCorrect,
    Map<String, int>? chapterAttempted,
    this.lastPlayedDate,
    this.lastSyncedAtMs,
  }) : chapterCorrect = chapterCorrect ?? <String, int>{},
       chapterAttempted = chapterAttempted ?? <String, int>{};

  /// Empty stats for a brand-new player. Deliberately all zeros so the UI
  /// shows a real "no data yet" state instead of fake numbers.
  factory UserStats.empty() => UserStats();

  // ------------------------------------------------------------ Derived --

  /// Accuracy as a 0–100 percentage. Returns 0 when nothing was answered.
  double get accuracyPercent =>
      totalAnswered == 0 ? 0 : (totalCorrect / totalAnswered) * 100;

  /// Accuracy rounded for display, e.g. `72`.
  int get accuracyRounded => accuracyPercent.round();

  /// `"72%"` when data exists, otherwise `"--"`.
  String get accuracyLabel => hasData ? '$accuracyRounded%' : '--';

  /// Average seconds spent per question.
  double get averageSecondsPerQuestion =>
      totalAnswered == 0 ? 0 : totalTimeSeconds / totalAnswered;

  /// Battle win-rate as a 0–100 percentage.
  double get winRatePercent =>
      battlesPlayed == 0 ? 0 : (battlesWon / battlesPlayed) * 100;

  /// True once the user has answered at least one question.
  bool get hasData => totalAnswered > 0;

  /// Accuracy for a single chapter as a 0–100 percentage.
  double chapterAccuracy(String chapterId) {
    final attempted = chapterAttempted[chapterId] ?? 0;
    if (attempted == 0) return 0;
    return ((chapterCorrect[chapterId] ?? 0) / attempted) * 100;
  }

  /// The chapter with the highest accuracy (min 3 attempts), or null.
  String? get strongestChapter {
    String? best;
    double bestValue = -1;
    chapterAttempted.forEach((id, attempted) {
      if (attempted < 3) return;
      final value = chapterAccuracy(id);
      if (value > bestValue) {
        bestValue = value;
        best = id;
      }
    });
    return best;
  }

  /// The chapter with the lowest accuracy (min 3 attempts), or null.
  String? get weakestChapter {
    String? worst;
    double worstValue = 101;
    chapterAttempted.forEach((id, attempted) {
      if (attempted < 3) return;
      final value = chapterAccuracy(id);
      if (value < worstValue) {
        worstValue = value;
        worst = id;
      }
    });
    return worst;
  }

  // ------------------------------------------------------------ Mutators --

  /// Records the outcome of a finished quiz.
  void recordQuiz({
    required int answered,
    required int correct,
    required double timeSeconds,
    String? chapterId,
    bool isDaily = false,
    int? dailyScore,
  }) {
    totalAnswered += answered;
    totalCorrect += correct;
    totalQuizzes += 1;
    totalTimeSeconds += timeSeconds;
    lastPlayedDate = _todayKey();

    if (chapterId != null && chapterId.isNotEmpty) {
      chapterAttempted[chapterId] =
          (chapterAttempted[chapterId] ?? 0) + answered;
      chapterCorrect[chapterId] = (chapterCorrect[chapterId] ?? 0) + correct;
    }

    if (isDaily) {
      final score = dailyScore ?? correct;
      final isBetter =
          score > bestDailyScore ||
          (score == bestDailyScore &&
              score > 0 &&
              (bestDailyTimeSeconds == 0 ||
                  timeSeconds < bestDailyTimeSeconds));
      if (isBetter) {
        bestDailyScore = score;
        bestDailyTimeSeconds = timeSeconds;
      }
    }
  }

  /// Records the result of a battle.
  void recordBattle({required bool won}) {
    battlesPlayed += 1;
    if (won) battlesWon += 1;
  }

  /// Keeps [longestStreak] up to date with the current streak.
  void touchStreak(int currentStreak) {
    if (currentStreak > longestStreak) longestStreak = currentStreak;
  }

  static String _todayKey() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  // ---------------------------------------------------------------- JSON --

  Map<String, dynamic> toJson() => {
    'total_answered': totalAnswered,
    'total_correct': totalCorrect,
    'total_quizzes': totalQuizzes,
    'best_daily_score': bestDailyScore,
    'best_daily_time_seconds': bestDailyTimeSeconds,
    'total_time_seconds': totalTimeSeconds,
    'battles_played': battlesPlayed,
    'battles_won': battlesWon,
    'longest_streak': longestStreak,
    'chapter_correct': chapterCorrect,
    'chapter_attempted': chapterAttempted,
    'last_played_date': lastPlayedDate,
    'last_synced_at_ms': lastSyncedAtMs,
  };

  factory UserStats.fromJson(Map<String, dynamic> json) {
    Map<String, int> intMap(dynamic raw) {
      if (raw is Map) {
        return raw.map(
          (key, value) => MapEntry('$key', (value as num?)?.toInt() ?? 0),
        );
      }
      return <String, int>{};
    }

    return UserStats(
      totalAnswered: (json['total_answered'] as num?)?.toInt() ?? 0,
      totalCorrect: (json['total_correct'] as num?)?.toInt() ?? 0,
      totalQuizzes: (json['total_quizzes'] as num?)?.toInt() ?? 0,
      bestDailyScore: (json['best_daily_score'] as num?)?.toInt() ?? 0,
      bestDailyTimeSeconds:
          (json['best_daily_time_seconds'] as num?)?.toDouble() ?? 0,
      totalTimeSeconds: (json['total_time_seconds'] as num?)?.toDouble() ?? 0,
      battlesPlayed: (json['battles_played'] as num?)?.toInt() ?? 0,
      battlesWon: (json['battles_won'] as num?)?.toInt() ?? 0,
      longestStreak: (json['longest_streak'] as num?)?.toInt() ?? 0,
      chapterCorrect: intMap(json['chapter_correct']),
      chapterAttempted: intMap(json['chapter_attempted']),
      lastPlayedDate: json['last_played_date'] as String?,
      lastSyncedAtMs: (json['last_synced_at_ms'] as num?)?.toInt(),
    );
  }

  UserStats copy() => UserStats.fromJson(toJson());

  /// Merges a remote copy with this local one, keeping the highest values.
  /// Used when Firestore data is pulled onto a fresh device.
  UserStats mergeWith(UserStats remote) {
    final merged = copy();
    merged.totalAnswered = totalAnswered > remote.totalAnswered
        ? totalAnswered
        : remote.totalAnswered;
    merged.totalCorrect = totalCorrect > remote.totalCorrect
        ? totalCorrect
        : remote.totalCorrect;
    merged.totalQuizzes = totalQuizzes > remote.totalQuizzes
        ? totalQuizzes
        : remote.totalQuizzes;
    merged.bestDailyScore = bestDailyScore > remote.bestDailyScore
        ? bestDailyScore
        : remote.bestDailyScore;
    merged.totalTimeSeconds = totalTimeSeconds > remote.totalTimeSeconds
        ? totalTimeSeconds
        : remote.totalTimeSeconds;
    merged.battlesPlayed = battlesPlayed > remote.battlesPlayed
        ? battlesPlayed
        : remote.battlesPlayed;
    merged.battlesWon = battlesWon > remote.battlesWon
        ? battlesWon
        : remote.battlesWon;
    merged.longestStreak = longestStreak > remote.longestStreak
        ? longestStreak
        : remote.longestStreak;

    // Best time: the smaller non-zero value wins.
    final times = <double>[
      bestDailyTimeSeconds,
      remote.bestDailyTimeSeconds,
    ].where((t) => t > 0).toList();
    merged.bestDailyTimeSeconds = times.isEmpty
        ? 0
        : times.reduce((a, b) => a < b ? a : b);

    for (final entry in remote.chapterAttempted.entries) {
      final local = chapterAttempted[entry.key] ?? 0;
      merged.chapterAttempted[entry.key] = local > entry.value
          ? local
          : entry.value;
    }
    for (final entry in remote.chapterCorrect.entries) {
      final local = chapterCorrect[entry.key] ?? 0;
      merged.chapterCorrect[entry.key] = local > entry.value
          ? local
          : entry.value;
    }

    merged.lastPlayedDate = _laterDate(lastPlayedDate, remote.lastPlayedDate);
    return merged;
  }

  static String? _laterDate(String? a, String? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.compareTo(b) >= 0 ? a : b;
  }
}
