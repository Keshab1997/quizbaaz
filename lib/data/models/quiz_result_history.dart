import '../../l10n/app_strings.dart';

/// Represents a single quiz attempt stored in the history.
///
/// Every finished quiz (daily or chapter) creates one of these records so the
/// player can review their past performance on the Result History screen.
class QuizResultHistory {
  final String id; // unique id (uuid or timestamp-based)
  final String userId;
  final String quizType; // 'daily' or 'chapter'
  final String? categoryTitle; // e.g. "Physical Science"
  final String? categoryTitleBn; // e.g. "ভৌতবিজ্ঞান"
  final String? chapterTitle; // e.g. "Chemical Reactions"
  final String? chapterTitleBn; // e.g. "রাসায়নিক বিক্রিয়া"
  final String? chapterId; // e.g. "phys_ch_01"
  final int totalQuestions;
  final int correctAnswers;
  final int wrongAnswers;
  final int skippedAnswers;
  final int score;
  final int coinsEarned;
  final int gemsEarned;
  final double timeSeconds;
  final double accuracy; // 0.0 to 100.0
  final DateTime playedAt;

  QuizResultHistory({
    required this.id,
    required this.userId,
    required this.quizType,
    this.categoryTitle,
    this.categoryTitleBn,
    this.chapterTitle,
    this.chapterTitleBn,
    this.chapterId,
    required this.totalQuestions,
    required this.correctAnswers,
    required this.wrongAnswers,
    this.skippedAnswers = 0,
    required this.score,
    this.coinsEarned = 0,
    this.gemsEarned = 0,
    required this.timeSeconds,
    required this.accuracy,
    required this.playedAt,
  });

  /// Human-readable quiz label.
  String get displayTitle {
    if (quizType == 'daily') return S.dashDailyQuiz;
    return chapterTitle ?? 'Chapter Quiz';
  }

  /// Bengali label.
  String get displayTitleBn {
    if (quizType == 'daily') return 'দৈনিক কুইজ';
    return chapterTitleBn ?? chapterTitle ?? 'চ্যাপ্টার কুইজ';
  }

  /// Category + chapter combined.
  String get fullSubjectPath {
    if (quizType == 'daily') return S.dashDailyQuiz;
    if (categoryTitle != null && chapterTitle != null) {
      return '$categoryTitle → $chapterTitle';
    }
    return chapterTitle ?? 'Unknown';
  }

  /// Formatted time string.
  String get timeFormatted {
    final mins = (timeSeconds / 60).floor();
    final secs = (timeSeconds % 60).floor();
    if (mins > 0) return '${mins}m ${secs}s';
    return '${secs}s';
  }

  /// Accuracy percentage string.
  String get accuracyLabel => '${accuracy.toStringAsFixed(0)}%';

  /// Grade based on accuracy.
  String get grade {
    if (accuracy >= 90) return 'S';
    if (accuracy >= 80) return 'A';
    if (accuracy >= 70) return 'B';
    if (accuracy >= 60) return 'C';
    if (accuracy >= 50) return 'D';
    return 'F';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'quiz_type': quizType,
        'category_title': categoryTitle,
        'category_title_bn': categoryTitleBn,
        'chapter_title': chapterTitle,
        'chapter_title_bn': chapterTitleBn,
        'chapter_id': chapterId,
        'total_questions': totalQuestions,
        'correct_answers': correctAnswers,
        'wrong_answers': wrongAnswers,
        'skipped_answers': skippedAnswers,
        'score': score,
        'coins_earned': coinsEarned,
        'gems_earned': gemsEarned,
        'time_seconds': timeSeconds,
        'accuracy': accuracy,
        'played_at': playedAt.toIso8601String(),
      };

  factory QuizResultHistory.fromJson(Map<String, dynamic> json) {
    return QuizResultHistory(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      quizType: json['quiz_type'] as String? ?? 'daily',
      categoryTitle: json['category_title'] as String?,
      categoryTitleBn: json['category_title_bn'] as String?,
      chapterTitle: json['chapter_title'] as String?,
      chapterTitleBn: json['chapter_title_bn'] as String?,
      chapterId: json['chapter_id'] as String?,
      totalQuestions: (json['total_questions'] as num?)?.toInt() ?? 0,
      correctAnswers: (json['correct_answers'] as num?)?.toInt() ?? 0,
      wrongAnswers: (json['wrong_answers'] as num?)?.toInt() ?? 0,
      skippedAnswers: (json['skipped_answers'] as num?)?.toInt() ?? 0,
      score: (json['score'] as num?)?.toInt() ?? 0,
      coinsEarned: (json['coins_earned'] as num?)?.toInt() ?? 0,
      gemsEarned: (json['gems_earned'] as num?)?.toInt() ?? 0,
      timeSeconds: (json['time_seconds'] as num?)?.toDouble() ?? 0.0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0.0,
      playedAt: DateTime.tryParse(json['played_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
