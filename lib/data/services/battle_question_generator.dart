import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/chapter_model.dart';
import '../models/question_model.dart';
import '../repositories/quiz_repository.dart';
import 'hive_service.dart';

/// Builds the question set for a 1-vs-1 battle.
///
/// Rules (see `docs/12_BATTLE_1V1_REAL_PLAYER_PLAN.md`):
///
/// 1. **Pooled from ALL chapters** — bundled assets **and** the Firestore
///    layer are merged per chapter (the same source the daily quiz uses, so
///    admin-authored questions flow straight into battles).
/// 2. **Mixed** — one question per chapter, round-robin across a shuffled
///    subject order, so one battle spans several subjects.
/// 3. **No repeats** — every selected id lands in `battle_used_questions`
///    (Hive). The next battle filters those out; when the unseen pool runs
///    dry the ledger clears and the cycle restarts, so a battle is always
///    possible and never repeats a question within a cycle.
/// 4. Options are shuffled once per battle (anti pattern-matching rule, same
///    as the daily quiz).
///
/// Only the **room creator** in a live battle calls this — the opponent reads
/// the same set from the room document, so both sides play identical
/// questions and only one side touches the used-ids ledger.
class BattleQuestionGenerator {
  final QuizRepository _quizRepository;

  BattleQuestionGenerator({QuizRepository? quizRepository})
    : _quizRepository = quizRepository ?? QuizRepository();

  final Random _rng = Random();

  /// How many chapter fetches run in parallel while pooling.
  static const _fetchConcurrency = 6;

  /// Generates up to [count] fresh, mixed battle questions.
  ///
  /// Returns an empty list only when the whole bank is empty — the UI shows
  /// an empty state in that case (same contract as the daily quiz).
  Future<List<QuestionModel>> generateBattleQuestions({int? count}) async {
    final need = count ?? 5;
    if (need <= 0) return const [];

    final used = HiveService.loadBattleUsedQuestionIds().toSet();

    var pool = await _poolQuestions(excludeIds: used);
    if (pool.length < need && used.isNotEmpty) {
      // The no-repeat cycle is exhausted — restart it. Always prefer fresh
      // questions over a shorter battle.
      debugPrint('BattleQuestionGenerator: cycle exhausted, restarting ledger');
      await HiveService.clearBattleUsedQuestionIds();
      pool = await _poolQuestions(excludeIds: const {});
    }

    final selected = _pickMixed(pool, need);
    if (selected.isEmpty) return const [];

    await HiveService.recordBattleUsedQuestionIds([
      for (final q in selected) q.id,
    ]);

    final battleRng = Random(DateTime.now().millisecondsSinceEpoch);
    return [for (final q in selected) q.withShuffledOptions(battleRng)];
  }

  // ------------------------------------------------------------------ pool --

  /// Merged question pool as (chapterId, question) pairs, excluding used ids.
  ///
  /// Chapters whose catalogued `total_questions > 0` are fetched first (they
  /// are the ones with real content — bundled or admin-authored); the rest are
  /// fetched only if the pool still runs short.
  Future<List<(String, QuestionModel)>> _poolQuestions({
    required Set<String> excludeIds,
  }) async {
    final categories = await _quizRepository.getCategoriesAndChapters();
    final chapters = <ChapterModel>[
      for (final category in categories) ...category.chapters,
    ];

    final withContent = chapters.where((c) => c.totalQuestions > 0).toList()
      ..shuffle(_rng);
    final mayBeEmpty = chapters.where((c) => c.totalQuestions <= 0).toList()
      ..shuffle(_rng);
    final ordered = [...withContent, ...mayBeEmpty];

    final results = <(String, QuestionModel)>[];
    final seenStems = <String>{};
    final seenIds = <String>{};
    final queue = List<ChapterModel>.from(ordered);

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final chapter = queue.removeAt(0);
        try {
          final questions = await _quizRepository.getChapterQuestions(
            chapter.jsonFile,
            chapterId: chapter.chapterId,
          );
          for (final question in questions) {
            if (excludeIds.contains(question.id)) continue;
            if (!seenIds.add(question.id)) continue;
            final stem = question.questionText
                .resolve('en')
                .trim()
                .toLowerCase();
            if (stem.isEmpty || !seenStems.add(stem)) continue;
            results.add((chapter.chapterId, question));
          }
        } catch (e) {
          // One dead chapter must never sink the whole pool.
          debugPrint(
            'BattleQuestionGenerator: ${chapter.chapterId} skipped – $e',
          );
        }
      }
    }

    await Future.wait([for (var i = 0; i < _fetchConcurrency; i++) worker()]);
    return results;
  }

  // ---------------------------------------------------------------- select --

  /// Round-robin pick: one question per chapter until [need] is reached, so
  /// a 5-question battle spans several subjects instead of one.
  List<QuestionModel> _pickMixed(List<(String, QuestionModel)> pool, int need) {
    if (pool.isEmpty) return const [];

    final byChapter = <String, List<QuestionModel>>{};
    for (final (chapterId, question) in pool) {
      byChapter.putIfAbsent(chapterId, () => []).add(question);
    }
    for (final list in byChapter.values) {
      list.shuffle(_rng);
    }

    final chapterOrder = byChapter.keys.toList()..shuffle(_rng);

    final selected = <QuestionModel>[];
    var safety = 0;
    while (selected.length < need && safety < byChapter.length * need + 5) {
      safety++;
      var added = false;
      for (final chapterId in chapterOrder) {
        final list = byChapter[chapterId]!;
        if (list.isEmpty) continue;
        selected.add(list.removeAt(0));
        added = true;
        if (selected.length >= need) break;
      }
      if (!added) break;
    }
    return selected;
  }
}
