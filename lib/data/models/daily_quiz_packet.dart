/// The backend-published daily competition packet.
///
/// The daily quiz used to be assembled on the device: each client pooled its
/// own asset banks + Firestore chapter caches and shuffled them with a date
/// seed. Same seed, but different pools (a device with a stale cache, or one
/// that missed a chapter fetch) meant different questions on different phones —
/// and a `min(10, pool.length)` run could be a three-question "competition"
/// (R12).
///
/// Now the day's set is published once, server-side, and every device plays
/// exactly those question ids. The packet also carries the rules of the
/// competition: how many questions, when submissions close (in the competition
/// timezone), and which scoring contract applies.
library;

/// One question of the packet: which chapter bank holds it.
class DailyQuizQuestionRef {
  final String chapterId;
  final String questionId;

  const DailyQuizQuestionRef({
    required this.chapterId,
    required this.questionId,
  });

  Map<String, dynamic> toJson() => {
        'chapter_id': chapterId,
        'question_id': questionId,
      };

  static DailyQuizQuestionRef? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final chapterId = raw['chapter_id']?.toString() ?? '';
    final questionId = raw['question_id']?.toString() ?? '';
    if (chapterId.isEmpty || questionId.isEmpty) return null;
    return DailyQuizQuestionRef(chapterId: chapterId, questionId: questionId);
  }

  @override
  String toString() => '$chapterId/$questionId';
}

/// The packet document: `daily_quiz_packets/{yyyy-MM-dd}`.
class DailyQuizPacket {
  final String dateKey;

  /// Bumped by the publisher when a day's packet has to be re-issued. Part of
  /// every cache key, so a re-issue is never mixed with the previous set.
  final int version;

  final List<DailyQuizQuestionRef> questions;

  /// How many questions the day is *supposed* to have. A packet that does not
  /// match is not a competition packet.
  final int count;

  /// Submission deadline (ms since epoch, UTC) — the end of the competition
  /// day in [CompetitionClock.utcOffset].
  final int deadlineMs;

  /// Scoring contract version the backend scores this packet with.
  final String scoringContract;

  /// The publisher marks a packet approved only once it has been reviewed.
  final bool approved;

  final int publishedAtMs;

  const DailyQuizPacket({
    required this.dateKey,
    required this.version,
    required this.questions,
    required this.count,
    required this.deadlineMs,
    this.scoringContract = 'v1',
    this.approved = false,
    this.publishedAtMs = 0,
  });

  /// A packet is complete when it is approved, has the announced number of
  /// question ids and no duplicates.
  bool get isComplete {
    if (!approved) return false;
    if (questions.isEmpty) return false;
    if (count > 0 && questions.length != count) return false;
    final seen = <String>{};
    for (final q in questions) {
      if (!seen.add(q.toString())) return false;
    }
    return true;
  }

  /// True while scores may still be submitted for this packet.
  bool isOpen(DateTime now) =>
      deadlineMs <= 0 || now.toUtc().millisecondsSinceEpoch <= deadlineMs;

  /// Why this packet cannot be played as a ranked competition run — null when
  /// it can.
  String? get rejectionReason {
    if (!approved) return 'packet not approved yet';
    if (questions.isEmpty) return 'packet has no questions';
    if (count > 0 && questions.length != count) {
      return 'packet has ${questions.length} of $count questions';
    }
    final seen = <String>{};
    for (final q in questions) {
      if (!seen.add(q.toString())) return 'packet repeats ${q.toString()}';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'date_key': dateKey,
        'version': version,
        'questions': [for (final q in questions) q.toJson()],
        'count': count,
        'deadline_ms': deadlineMs,
        'scoring_contract': scoringContract,
        'approved': approved,
        'published_at': publishedAtMs,
      };

  /// Returns null when the document does not describe a usable packet.
  static DailyQuizPacket? fromJson(String dateKey, Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final questions = <DailyQuizQuestionRef>[];
    final rawQuestions = map['questions'];
    if (rawQuestions is List) {
      for (final entry in rawQuestions) {
        final ref = DailyQuizQuestionRef.fromJson(entry);
        if (ref != null) questions.add(ref);
      }
    }
    return DailyQuizPacket(
      dateKey: map['date_key']?.toString() ?? dateKey,
      version: (map['version'] as num?)?.toInt() ?? 1,
      questions: questions,
      count: (map['count'] as num?)?.toInt() ?? questions.length,
      deadlineMs: (map['deadline_ms'] as num?)?.toInt() ?? 0,
      scoringContract: map['scoring_contract']?.toString() ?? 'v1',
      approved: map['approved'] as bool? ?? false,
      publishedAtMs: (map['published_at'] as num?)?.toInt() ?? 0,
    );
  }

  /// Cache key for the resolved question rows of this exact packet.
  String get cacheKey => 'daily_quiz_set_${dateKey}_v$version';
}
