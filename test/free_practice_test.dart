import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:quizbaaz/data/models/chapter_model.dart';
import 'package:quizbaaz/data/models/localized_text.dart';
import 'package:quizbaaz/data/models/question_model.dart';
import 'package:quizbaaz/data/providers/quiz_provider.dart';
import 'package:quizbaaz/data/providers/user_provider.dart';
import 'package:quizbaaz/data/repositories/quiz_repository.dart';
import 'package:quizbaaz/data/services/hive_service.dart';

/// Serves a canned mixed pool and mirrors the subject filter, so a broken
/// filter would surface as the wrong questions in a run.
class _PoolRepository extends QuizRepository {
  _PoolRepository(this.pool, {this.onPoolRequest});

  final List<QuestionModel> pool;
  final void Function(String? categoryId)? onPoolRequest;

  @override
  Future<List<QuestionModel>> getPracticePool({String? categoryId}) {
    onPoolRequest?.call(categoryId);
    return Future.value([
      for (final q in pool)
        if (categoryId == null || q.id.startsWith('$categoryId-')) q,
    ]);
  }
}

/// Serves a canned chapter catalogue, so the repository pool logic can be
/// exercised without assets or Firestore.
class _CatalogRepository extends QuizRepository {
  _CatalogRepository({required this.categories, required this.banks});

  final List<CategoryModel> categories;
  final Map<String, List<QuestionModel>> banks;

  @override
  Future<List<CategoryModel>> getCategoriesAndChapters({
    bool forceRefresh = false,
    bool includeDisabled = false,
  }) async => categories;

  @override
  Future<List<QuestionModel>> getChapterQuestions(
    String jsonFilePath, {
    String? chapterId,
    bool forceRefresh = false,
  }) async => banks[jsonFilePath] ?? const [];
}

QuestionModel _question(String id, {String? stem}) => QuestionModel(
  id: id,
  questionText: LocalizedText({'en': stem ?? 'Question $id'}),
  optionTexts: const [
    LocalizedText({'en': 'First'}),
    LocalizedText({'en': 'Second'}),
  ],
  correctIndex: 0,
);

CategoryModel _category(String id, Map<String, int> bankSizes) => CategoryModel(
  categoryId: id,
  nameText: LocalizedText({'en': 'Subject $id'}),
  categoryIcon: '📘',
  colorHex: '#3B82F6',
  totalChapters: bankSizes.length,
  chapters: [
    for (final entry in bankSizes.entries)
      ChapterModel(
        chapterId: '${entry.key}-chapter',
        chapterNumber: 1,
        titleText: LocalizedText({'en': 'Chapter ${entry.key}'}),
        descriptionText: const LocalizedText({'en': 'Description'}),
        totalQuestions: entry.value,
        jsonFile: '${entry.key}.json',
        isUnlocked: true,
        stars: 0,
        bestScore: 0,
      ),
  ],
);

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('quizbaaz_free_practice_');
    Hive.init(tempDir.path);
    // Question attempts are recorded into Hive while a run plays.
    await HiveService.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  QuizProvider makeQuiz(QuizRepository repository) {
    final quiz = QuizProvider(UserProvider(), repository: repository);
    // quitQuiz disarms any delayed advance; dispose stops the countdown.
    addTearDown(() {
      quiz.quitQuiz();
      quiz.dispose();
    });
    return quiz;
  }

  group('QuizRepository.getPracticePool', () {
    test('merges every chapter and de-duplicates identical stems', () async {
      final repository = _CatalogRepository(
        categories: [
          _category('math', {'m1': 2, 'm2': 1}),
          _category('hist', {'h1': 1}),
        ],
        banks: {
          'm1.json': [
            _question('m1-a', stem: 'Shared stem'),
            _question('m1-b', stem: 'Math only'),
          ],
          'm2.json': [
            // Same stem as m1-a — must be played once, not twice.
            _question('m2-a', stem: 'shared stem  '),
          ],
          'h1.json': [_question('h1-a', stem: 'History only')],
        },
      );

      final pool = await repository.getPracticePool();

      expect(pool.map((q) => q.id).toSet(), {'m1-a', 'm1-b', 'h1-a'});
    });

    test('a subject filter narrows the pool to that subject', () async {
      final repository = _CatalogRepository(
        categories: [
          _category('math', {'m1': 1}),
          _category('hist', {'h1': 1}),
        ],
        banks: {
          'm1.json': [_question('m1-a')],
          'h1.json': [_question('h1-a')],
        },
      );

      final pool = await repository.getPracticePool(categoryId: 'math');

      expect(pool.map((q) => q.id), ['m1-a']);
    });
  });

  group('QuizProvider.startFreePractice', () {
    test('draws at most one set and marks the run as free practice', () async {
      final quiz = makeQuiz(
        _PoolRepository([for (var i = 0; i < 25; i++) _question('all-$i')]),
      );

      await quiz.startFreePractice();

      expect(quiz.isFreePractice, isTrue);
      expect(quiz.isPractice, isTrue);
      expect(quiz.isDailyQuiz, isFalse);
      expect(quiz.isChapterRun, isFalse);
      expect(quiz.questions.length, 10);
    });

    test('passes the subject filter and keeps it across a retry', () async {
      final requested = <String?>[];
      final quiz = makeQuiz(
        _PoolRepository([
          for (var i = 0; i < 5; i++) _question('math-$i'),
          for (var i = 0; i < 5; i++) _question('hist-$i'),
        ], onPoolRequest: requested.add),
      );

      await quiz.startFreePractice(categoryId: 'math');
      expect(quiz.questions, isNotEmpty);
      expect(
        quiz.questions.every((q) => q.id.startsWith('math-')),
        isTrue,
        reason: 'a math run must never contain other subjects',
      );

      await quiz.retryFreePractice();
      expect(requested, ['math', 'math']);
      expect(quiz.practiceCategoryId, 'math');
      expect(quiz.questions.every((q) => q.id.startsWith('math-')), isTrue);
    });

    test('finishing a round credits nothing', () async {
      // Two questions, so the round can be finished inside a test without
      // waiting out ten auto-advance delays.
      final quiz = makeQuiz(_PoolRepository([_question('a'), _question('b')]));
      await quiz.startFreePractice();
      expect(quiz.questions.length, 2);

      for (var i = 0; i < 2; i++) {
        quiz.selectOption(quiz.currentQuestion!.correctIndex);
        await Future<void>.delayed(const Duration(milliseconds: 1900));
      }

      expect(quiz.isQuizCompleted, isTrue);
      expect(quiz.score, 20); // in-run feedback still shows
      // The economy must stay untouched: unlimited rounds can never farm.
      expect(quiz.earnedCoins, 0);
      expect(quiz.earnedGems, 0);
      expect(quiz.isPractice, isTrue);
      expect(quiz.dailyRewardSkipped, isTrue);
    });

    test('quitting while the pool loads ignores its late result', () async {
      final result = Completer<List<QuestionModel>>();
      final quiz = QuizProvider(
        UserProvider(),
        repository: _LatePoolRepository(result.future),
      );
      addTearDown(quiz.dispose);

      final starting = quiz.startFreePractice();
      expect(quiz.isLoading, isTrue);

      quiz.quitQuiz();
      result.complete([_question('late-question')]);
      await starting;

      expect(quiz.isLoading, isFalse);
      expect(quiz.questions, isEmpty);
      expect(quiz.isQuizCompleted, isFalse);
    });
  });
}

/// A pool that resolves only when its completer does.
class _LatePoolRepository extends QuizRepository {
  _LatePoolRepository(this.pool);

  final Future<List<QuestionModel>> pool;

  @override
  Future<List<QuestionModel>> getPracticePool({String? categoryId}) => pool;
}
