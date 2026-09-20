import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_assets.dart';
import '../models/chapter_model.dart';
import '../models/question_model.dart';
import '../services/hive_service.dart';
import '../services/chapter_catalog_service.dart';
import '../services/daily_quiz_generator.dart';
import '../services/question_bank_service.dart';

/// Question-bank access.
///
/// A chapter's questions come from two places and are **merged**:
///
/// ```text
///   assets/data/*.json   the offline floor — every install has these,
///                        no network, no account, works on first launch
///          +
///   Firestore            the live layer — questions an admin added since
///                        the last release
///          =
///   merged by id, Firestore winning on a clash, cached in Hive
/// ```
///
/// Merging rather than replacing is what lets the admin panel grow a chapter
/// without an app update while keeping the app fully usable offline. Firestore
/// wins on a clash so a correction made in the admin panel beats the stale
/// bundled copy of the same question id.
///
/// Nothing here invents placeholder questions: an unavailable bank returns an
/// empty list and the UI shows an empty state.
class QuizRepository {
  QuizRepository({
    QuestionBankService? bankService,
    ChapterCatalogService? catalogService,
  })  : _bankService = bankService ?? QuestionBankService(),
        _catalogService = catalogService ?? ChapterCatalogService();

  final QuestionBankService _bankService;
  final ChapterCatalogService _catalogService;

  /// Admin-authored questions are cached briefly — long enough to keep a quiz
  /// snappy, short enough that a newly added batch shows up the same session.
  static const _remoteCacheTtl = Duration(minutes: 15);

  /// Daily quiz questions — dynamically pooled & mixed across chapters for today's date.
  Future<List<QuestionModel>> getDailyQuizQuestions() async {
    final generator = DailyQuizGenerator(
      bankService: _bankService,
      quizRepository: this,
    );
    return generator.generateDailyQuestions();
  }

  /// Chapter/category tree: bundled catalogue merged with admin edits.
  ///
  /// Cached as the *merged* result, so the chapter list renders from Hive on a
  /// cold start without waiting on Firestore.
  Future<List<CategoryModel>> getCategoriesAndChapters({
    bool forceRefresh = false,
    bool includeDisabled = false,
  }) async {
    if (!forceRefresh) {
      final cached = HiveService.cacheGetList(
        HiveService.cacheChapters,
        maxAge: _remoteCacheTtl,
      );
      if (cached.isNotEmpty) {
        return filterForStudents(
          cached.map(CategoryModel.fromJson).toList(),
          includeDisabled: includeDisabled,
        );
      }
    }

    final assetRows = await _readJsonList(AppAssets.jsonChapters, 'categories');
    final assetCategories = assetRows.map(CategoryModel.fromJson).toList();

    final remoteCategories = await _catalogService.fetchCategories();

    final merged = _withLiveCounts(
      ChapterCatalogService.mergeWithAssets(
        assetCategories,
        remoteCategories,
      ),
      await _bankService.fetchQuestionCounts(),
    );

    if (merged.isNotEmpty) {
      await HiveService.cachePut(
        HiveService.cacheChapters,
        merged.map((c) => c.toJson()).toList(),
      );
    }
    return filterForStudents(merged, includeDisabled: includeDisabled);
  }

  /// Removes disabled chapters and categories that contain no visible chapter.
  /// The admin manager opts into [includeDisabled] so an admin can turn a
  /// hidden chapter back on; all student-facing callers get the safe default.
  static List<CategoryModel> filterForStudents(
    List<CategoryModel> categories, {
    bool includeDisabled = false,
  }) {
    if (includeDisabled) return categories;

    return categories
        .map((category) => category.copyWith(
              chapters: category.chapters
                  .where((chapter) => chapter.isEnabled)
                  .toList(),
            ))
        .where((category) => category.chapters.isNotEmpty)
        .toList();
  }

  /// Questions for one chapter: bundled asset + admin-authored, merged.
  ///
  /// [chapterId] is optional so existing callers keep working, but without it
  /// only the bundled bank is returned — the Firestore layer is keyed by
  /// chapter id, not by asset path.
  Future<List<QuestionModel>> getChapterQuestions(
    String jsonFilePath, {
    String? chapterId,
  }) async {
    final cacheKey = 'chapter_questions:$jsonFilePath';
    final cached = HiveService.cacheGetList(cacheKey, maxAge: _remoteCacheTtl);
    if (cached.isNotEmpty) {
      return cached.map(QuestionModel.fromJson).toList();
    }

    final assetRows = await _readJsonList(jsonFilePath, 'questions');

    final remoteRows = chapterId == null
        ? const <Map<String, dynamic>>[]
        : await _fetchRemoteQuestions(chapterId);

    final merged = _mergeById(assetRows, remoteRows);
    if (merged.isNotEmpty) {
      await HiveService.cachePut(cacheKey, merged);
    }
    return merged.map(QuestionModel.fromJson).toList();
  }

  /// Folds admin-authored question counts into each chapter's total.
  ///
  /// `total_questions` in the asset catalogue counts only the bundled
  /// questions, so a chapter filled entirely from the admin panel would
  /// otherwise keep advertising 0 — which is what a student sees on the
  /// chapter card. The displayed number is bundled + admin-authored.
  ///
  /// Ids never overlap between the two sources: admin ids continue from the
  /// highest existing one, so adding rather than de-duplicating is correct.
  static List<CategoryModel> _withLiveCounts(
    List<CategoryModel> categories,
    Map<String, int> remoteCounts,
  ) {
    if (remoteCounts.isEmpty) return categories;

    return categories
        .map((category) => category.copyWith(
              chapters: category.chapters.map((chapter) {
                final remote = remoteCounts[chapter.chapterId] ?? 0;
                if (remote == 0) return chapter;
                // Already bundled — most likely pulled in by
                // tool/pull_firestore_questions.py, so the live count is a
                // subset of what the card already shows. Adding it again
                // would advertise double. Until the next pull refreshes
                // total_questions, the bundle is the better number.
                if (chapter.totalQuestions > 0) return chapter;
                return chapter.copyWith(
                  totalQuestions: chapter.totalQuestions + remote,
                );
              }).toList(),
            ))
        .toList();
  }

  /// Admin-authored questions, or an empty list when Firestore is unreachable.
  ///
  /// Failing soft is deliberate: a student offline, or one whose Firestore
  /// read is refused, still gets the bundled bank rather than an error screen.
  Future<List<Map<String, dynamic>>> _fetchRemoteQuestions(
    String chapterId,
  ) async {
    try {
      final questions = await _bankService.fetchQuestions(chapterId);
      return questions.map((q) => q.toJson()).toList();
    } catch (e) {
      debugPrint('QuizRepository: remote questions unavailable — $e');
      return const [];
    }
  }

  /// Merges two question lists on `id`, with [overrides] taking precedence.
  ///
  /// Order is preserved: bundled questions keep their authored sequence and
  /// anything new is appended, so a chapter does not reshuffle itself when the
  /// admin adds to it.
  static List<Map<String, dynamic>> _mergeById(
    List<Map<String, dynamic>> base,
    List<Map<String, dynamic>> overrides,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    final order = <String>[];

    void put(Map<String, dynamic> row) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) return;
      if (!merged.containsKey(id)) order.add(id);
      merged[id] = row;
    }

    base.forEach(put);
    overrides.forEach(put);

    return [for (final id in order) merged[id]!];
  }

  /// Drops every cached question bank (used after an admin write).
  Future<void> invalidateQuestionCache({String? jsonFilePath}) async {
    await HiveService.cacheRemove(HiveService.cacheDailyQuiz);
    await HiveService.cacheRemove(HiveService.cacheChapters);
    if (jsonFilePath != null) {
      await HiveService.cacheRemove('chapter_questions:$jsonFilePath');
    }
  }

  // -------------------------------------------------------------- Helpers --

  Future<List<Map<String, dynamic>>> _readJsonList(
    String assetPath,
    String key,
  ) async {
    try {
      final jsonStr = await rootBundle.loadString(assetPath);
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      final list = data[key] as List<dynamic>? ?? const [];
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      // No bank available — callers show an empty state.
      return const [];
    }
  }
}
