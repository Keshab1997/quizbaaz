import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/question_model.dart';
import '../repositories/quiz_repository.dart';
import '../services/hive_service.dart';
import 'competition_clock.dart';
import 'daily_quiz_packet_service.dart';
import 'question_bank_service.dart';

/// Builds the day's question set.
///
/// **Ranked path (the competition).** The day's questions are published by the
/// backend as a packet (`daily_quiz_packets/{date}`) naming the exact question
/// ids to play. Every device resolves those same ids, so the set is identical
/// everywhere and the score is comparable (R12). See
/// [DailyQuizPacketService].
///
/// **Practice path (fallback).** When no usable packet exists — nothing
/// published, not approved, incomplete, closed, or the ids cannot be resolved
/// offline — the app still plays a mixed pool built from the local banks, but
/// the run is explicitly **unranked**: it never reaches the leaderboard or the
/// daily competition credit.
class DailyQuizGenerator {
  final QuestionBankService _bankService;
  final QuizRepository _quizRepository;
  final DailyQuizPacketService _packetService;

  DailyQuizGenerator({
    QuestionBankService? bankService,
    QuizRepository? quizRepository,
    DailyQuizPacketService? packetService,
  })  : _bankService = bankService ?? QuestionBankService(),
        _quizRepository = quizRepository ?? QuizRepository(),
        _packetService = packetService ?? DailyQuizPacketService();

  /// Integer seed derived from date key `yyyyMMdd` (e.g. 20260825).
  static int _dateSeed(DateTime date) {
    return date.year * 10000 + date.month * 100 + date.day;
  }

  /// Date key string `yyyy-MM-dd` in the **competition** timezone.
  static String dateKey([DateTime? date]) =>
      CompetitionClock.dateKey(date);

  /// Today's set together with whether the run may be ranked.
  ///
  /// Ranked only when the published packet resolves completely; every other
  /// outcome is an unranked practice set (possibly empty — the UI then shows
  /// its empty state instead of inventing questions).
  Future<DailyQuizSet> generateDailySet({
    DateTime? date,
    bool forceRefresh = false,
  }) async {
    final now = date ?? DateTime.now();
    final dateKey = CompetitionClock.dateKey(now);

    final packetSet = await _packetService.resolve(
      now: now,
      forceRefresh: forceRefresh,
    );
    if (packetSet.ranked && packetSet.questions.isNotEmpty) {
      return packetSet;
    }

    debugPrint(
      'DailyQuizGenerator: unranked practice set for $dateKey – '
      '${packetSet.unrankedReason ?? 'packet unavailable'}',
    );
    final practice = await _practicePool(dateKey, forceRefresh: forceRefresh);
    return DailyQuizSet(
      questions: practice,
      ranked: false,
      packet: packetSet.packet,
      unrankedReason: packetSet.unrankedReason ?? 'packet unavailable',
    );
  }

  /// The practice pool: the local banks, mixed with the day's date seed.
  ///
  /// Deterministic per date so the practice set is at least consistent for
  /// this device, and cached under a `practice` key so the ranked set and the
  /// practice set can never be mistaken for each other.
  Future<List<QuestionModel>> _practicePool(
    String dateKey, {
    bool forceRefresh = false,
  }) async {
    final cacheKey = 'daily_quiz_practice_$dateKey';
    if (!forceRefresh) {
      final cached = HiveService.cacheGetList(
        cacheKey,
        maxAge: const Duration(hours: 24),
      );
      if (cached.isNotEmpty) {
        return cached.map(QuestionModel.fromJson).toList();
      }
    }

    final dayStart = CompetitionClock.dayStart(dateKey);
    final pooled = await _poolQuestions();
    if (pooled.isEmpty) return const [];

    final rng = Random(_dateSeed(dayStart.add(CompetitionClock.utcOffset)));
    final shuffled = [...pooled]..shuffle(rng);
    final selected = shuffled.take(min(10, shuffled.length)).toList();
    await HiveService.cachePut(cacheKey, selected);
    return selected.map(QuestionModel.fromJson).toList();
  }

  /// Backwards-compatible wrapper: the questions of today's set, ranked or
  /// not. Prefer [generateDailySet] — it tells you whether the run counts.
  Future<List<QuestionModel>> generateDailyQuestions({
    DateTime? date,
    bool forceRefresh = false,
  }) async =>
      (await generateDailySet(date: date, forceRefresh: forceRefresh))
          .questions;

  /// Pools every bundled + Firestore question the device can see, de-duplicated
  /// by stem.
  Future<List<Map<String, dynamic>>> _poolQuestions() async {
    final pooledQuestions = <Map<String, dynamic>>[];
    final seenStems = <String>{};

    final categories = await _quizRepository.getCategoriesAndChapters();
    for (final category in categories) {
      for (final chapter in category.chapters) {
        if (chapter.jsonFile.isNotEmpty) {
          final assetRows = await _readJsonList(chapter.jsonFile, 'questions');
          for (final row in assetRows) {
            final q = QuestionModel.fromJson(row);
            final stem = q.questionText.resolve('en').trim().toLowerCase();
            if (stem.isNotEmpty && !seenStems.contains(stem)) {
              seenStems.add(stem);
              pooledQuestions.add(row);
            }
          }
        }

        try {
          final remoteQuestions =
              await _bankService.fetchQuestions(chapter.chapterId);
          for (final q in remoteQuestions) {
            final stem = q.questionText.resolve('en').trim().toLowerCase();
            if (stem.isNotEmpty && !seenStems.contains(stem)) {
              seenStems.add(stem);
              pooledQuestions.add(q.toJson());
            }
          }
        } catch (e) {
          debugPrint(
            'DailyQuizGenerator: remote fetch skipped for ${chapter.chapterId}',
          );
        }
      }
    }
    return pooledQuestions;
  }

  static Future<List<Map<String, dynamic>>> _readJsonList(String assetPath, String key) async {
    try {
      final jsonStr = await rootBundle.loadString(assetPath);
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      final list = data[key] as List<dynamic>? ?? const [];
      return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return const [];
    }
  }
}
