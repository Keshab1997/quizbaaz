/// How a chapter is broken into playable sets.
///
/// A chapter grows over months — the admin panel is built to append to it
/// forever — so serving the whole bank as one quiz would eventually mean a
/// 200-question sitting that nobody finishes. Ten at a time is a session a
/// student will actually complete, and it gives them somewhere to come back
/// to tomorrow.
const int kQuestionsPerSet = 10;

/// Number of sets a chapter of [questionCount] questions splits into.
///
/// The last set is short rather than dropped: four leftover questions are
/// still four questions the student has not seen.
int setCountFor(int questionCount) {
  if (questionCount <= 0) return 0;
  return (questionCount + kQuestionsPerSet - 1) ~/ kQuestionsPerSet;
}

/// Index of the first question in [setIndex].
int setStartIndex(int setIndex) => setIndex * kQuestionsPerSet;

/// How many questions [setIndex] actually holds.
int setLengthFor(int questionCount, int setIndex) {
  final remaining = questionCount - setStartIndex(setIndex);
  return remaining <= 0
      ? 0
      : (remaining < kQuestionsPerSet ? remaining : kQuestionsPerSet);
}

/// A student's record for one set of one chapter.
///
/// Sets are addressed by position, and positions are stable because questions
/// are only ever **appended** to a bank — set 1 is the same ten questions next
/// month as it is today. Adding questions creates new sets at the end; it
/// never reshuffles what someone has already completed.
class ChapterSetProgress {
  final String chapterId;

  /// 0-based.
  final int setIndex;

  /// Best score across every attempt, including practice runs.
  final int bestScore;

  /// Correct answers in the best attempt.
  final int bestCorrect;

  /// Questions the set had when it was last played.
  final int totalQuestions;

  /// When it was first completed — what unlocks the next set.
  final DateTime completedAt;

  /// When it was last played, practice included.
  final DateTime lastPlayedAt;

  /// Total plays, practice included.
  final int attempts;

  const ChapterSetProgress({
    required this.chapterId,
    required this.setIndex,
    required this.bestScore,
    required this.bestCorrect,
    required this.totalQuestions,
    required this.completedAt,
    required this.lastPlayedAt,
    this.attempts = 1,
  });

  /// Key used to store and look this up.
  String get key => '$chapterId#$setIndex';

  static String keyFor(String chapterId, int setIndex) =>
      '$chapterId#$setIndex';

  /// Human-facing set number.
  int get setNumber => setIndex + 1;

  /// 0.0–1.0, for the progress ring on the set card.
  double get accuracy => totalQuestions == 0 ? 0 : bestCorrect / totalQuestions;

  int get accuracyPercent => (accuracy * 100).round();

  /// Every question right on the best attempt.
  bool get isPerfect => totalQuestions > 0 && bestCorrect == totalQuestions;

  /// Folds a new attempt in, keeping the better result.
  ///
  /// [completedAt] deliberately never moves: it marks when the set was first
  /// cleared, and a practice run months later must not make the set look new.
  ChapterSetProgress merge({
    required int score,
    required int correct,
    required int total,
    required DateTime playedAt,
  }) {
    return ChapterSetProgress(
      chapterId: chapterId,
      setIndex: setIndex,
      bestScore: score > bestScore ? score : bestScore,
      bestCorrect: correct > bestCorrect ? correct : bestCorrect,
      totalQuestions: total,
      completedAt: completedAt,
      lastPlayedAt: playedAt,
      attempts: attempts + 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'chapter_id': chapterId,
        'set_index': setIndex,
        'best_score': bestScore,
        'best_correct': bestCorrect,
        'total_questions': totalQuestions,
        'completed_at': completedAt.toIso8601String(),
        'last_played_at': lastPlayedAt.toIso8601String(),
        'attempts': attempts,
      };

  factory ChapterSetProgress.fromJson(Map<String, dynamic> json) {
    final completed =
        DateTime.tryParse(json['completed_at'] as String? ?? '') ??
            DateTime.now();
    return ChapterSetProgress(
      chapterId: json['chapter_id'] as String? ?? '',
      setIndex: (json['set_index'] as num?)?.toInt() ?? 0,
      bestScore: (json['best_score'] as num?)?.toInt() ?? 0,
      bestCorrect: (json['best_correct'] as num?)?.toInt() ?? 0,
      totalQuestions: (json['total_questions'] as num?)?.toInt() ?? 0,
      completedAt: completed,
      lastPlayedAt:
          DateTime.tryParse(json['last_played_at'] as String? ?? '') ??
              completed,
      attempts: (json['attempts'] as num?)?.toInt() ?? 1,
    );
  }
}
