import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:quizbaaz/data/models/app_config.dart';
import 'package:quizbaaz/data/models/localized_text.dart';
import 'package:quizbaaz/data/models/question_model.dart';
import 'package:quizbaaz/data/models/shop_item.dart';
import 'package:quizbaaz/data/providers/quiz_provider.dart';
import 'package:quizbaaz/data/providers/user_provider.dart';
import 'package:quizbaaz/data/repositories/quiz_repository.dart';
import 'package:quizbaaz/data/services/hive_service.dart';

/// R08 (practice runs must change no economy) and R09 (lifelines and delayed
/// transitions must not corrupt timing, skip answers, or complete a run twice).
class _FixedRepository extends QuizRepository {
  _FixedRepository(this.questions);

  final List<QuestionModel> questions;

  @override
  Future<List<QuestionModel>> getChapterQuestions(
    String jsonFilePath, {
    String? chapterId,
    bool forceRefresh = false,
  }) async =>
      questions;
}

QuestionModel _question(String id, {int correctIndex = 0}) => QuestionModel(
      id: id,
      questionText: LocalizedText({'en': 'Question $id'}),
      optionTexts: const [
        LocalizedText({'en': 'First'}),
        LocalizedText({'en': 'Second'}),
        LocalizedText({'en': 'Third'}),
        LocalizedText({'en': 'Fourth'}),
      ],
      correctIndex: correctIndex,
    );

void main() {
  late Directory tempDir;
  late UserProvider user;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('quizbaaz_economy_test_');
    Hive.init(tempDir.path);
    await HiveService.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Builds the provider the tests share. The app config is written first so
  /// `initialize()` cannot pick up a clock an earlier test left behind.
  Future<void> resetUser({int secondsPerQuestion = 15}) async {
    await HiveService.cachePut(
      'app_config',
      AppConfig(secondsPerQuestion: secondsPerQuestion).toJson(),
    );
    user = UserProvider()..initialize();
    await Future<void>.delayed(Duration.zero);
  }

  /// Every test needs an initialised provider; without this the R08 tests
  /// (which never touch the clock) died on an uninitialised `late` variable.
  setUp(() async {
    await resetUser();
  });

  /// A two-second question limit instead of the built-in fifteen, so the
  /// timeout test does not spend fifteen seconds waiting for a clock.
  Future<void> useFastClock() => resetUser(secondsPerQuestion: 2);

  /// Plays a chapter to the end, answering everything correctly.
  Future<QuizProvider> playToEnd(
    UserProvider user, {
    required bool practice,
    int questionCount = 3,
  }) async {
    final quiz = QuizProvider(
      user,
      repository: _FixedRepository(
        [for (var i = 0; i < questionCount; i++) _question('q$i')],
      ),
    );
    await quiz.startChapterQuiz('chapter.json',
        chapterId: 'test_chapter', practice: practice);
    for (var i = 0; i < questionCount; i++) {
      quiz.selectOption(quiz.currentQuestion!.correctIndex);
      await Future<void>.delayed(const Duration(milliseconds: 1850));
    }
    return quiz;
  }

  group('R08 — a practice run changes no economy', () {
    test('no coins, gems or XP are credited', () async {
      final coinsBefore = user.user.coins;
      final gemsBefore = user.user.gems;
      final xpBefore = user.user.xp;

      final quiz = await playToEnd(user, practice: true);

      expect(quiz.isQuizCompleted, isTrue);
      expect(quiz.correctCount, 3);
      expect(quiz.earnedCoins, 0);
      expect(quiz.earnedGems, 0);
      expect(user.user.coins, coinsBefore);
      expect(user.user.gems, gemsBefore);
      expect(user.user.xp, xpBefore);
    });

    test('no stats or history entry is written', () async {
      final statsBefore = HiveService.loadStats();
      final historyBefore = HiveService.loadQuizHistory().length;

      await playToEnd(user, practice: true);

      final statsAfter = HiveService.loadStats();
      expect(statsAfter.totalQuizzes, statsBefore.totalQuizzes);
      expect(statsAfter.totalCorrect, statsBefore.totalCorrect);
      expect(HiveService.loadQuizHistory().length, historyBefore);
    });

    test('lifelines do not consume the inventory', () async {
      // Give the player a full set of power-ups and run a practice quiz using
      // every one of them.
      user.user.inventory[ShopItemIds.fiftyFifty] = 1;
      user.user.inventory[ShopItemIds.freezeTime] = 1;
      user.user.inventory[ShopItemIds.skipQuestion] = 1;
      user.user.inventory[ShopItemIds.hintReveal] = 1;
      user.user.inventory[ShopItemIds.extraLife] = 1;

      final quiz = QuizProvider(
        user,
        repository: _FixedRepository([
          _question('q0', correctIndex: 1),
          _question('q1'),
          _question('q2'),
        ]),
      );
      await quiz.startChapterQuiz('chapter.json',
          chapterId: 'test_chapter', practice: true);

      expect(quiz.useFiftyFifty(), isTrue);
      expect(quiz.useHintReveal(), isTrue);
      expect(quiz.useFreezeTime(), isTrue);

      // Wrong answer → extra life → correct answer. 50-50 has already hidden
      // two of the options, and taps on a hidden option are ignored, so pick a
      // wrong option that is still on screen.
      final correct = quiz.currentQuestion!.correctIndex;
      final wrong = [0, 1, 2, 3].firstWhere(
        (i) => i != correct && !quiz.disabledOptionIndices.contains(i),
      );
      quiz.selectOption(wrong);
      expect(quiz.extraLifeUsed, isTrue, reason: 'extra life did not fire');
      quiz.selectOption(correct);

      await Future<void>.delayed(const Duration(milliseconds: 1900));
      expect(quiz.useSkipQuestion(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      for (var i = 0; i < 3; i++) {
        final q = quiz.currentQuestion;
        if (q == null) break;
        quiz.selectOption(q.correctIndex);
        await Future<void>.delayed(const Duration(milliseconds: 1850));
      }

      for (final item in [
        ShopItemIds.fiftyFifty,
        ShopItemIds.freezeTime,
        ShopItemIds.skipQuestion,
        ShopItemIds.hintReveal,
        ShopItemIds.extraLife,
      ]) {
        expect(user.inventoryCount(item), 1, reason: '$item was spent in practice');
      }
    });

    test('an eligible run still pays out', () async {
      // The guard must not swallow the real thing.
      final coinsBefore = user.user.coins;
      final quiz = await playToEnd(user, practice: false);
      expect(quiz.isQuizCompleted, isTrue);
      expect(user.user.coins, greaterThan(coinsBefore));
    });
  });

  group('R09 — timers, lifelines and transitions', () {
    test('freeze time never produces a negative elapsed time', () async {
      final quiz = QuizProvider(
        user,
        repository: _FixedRepository([_question('q0'), _question('q1')]),
      );
      user.user.inventory[ShopItemIds.freezeTime] = 5;
      await quiz.startChapterQuiz('chapter.json', chapterId: 'test_chapter');

      expect(quiz.useFreezeTime(), isTrue);
      // Answer straight after freezing: remaining (limit + 10) is larger than
      // the configured question time, so the old subtraction went negative.
      quiz.selectOption(quiz.currentQuestion!.correctIndex);

      expect(quiz.totalTimeSeconds, greaterThanOrEqualTo(0));
    });

    test('extra life on a wrong answer restarts the countdown', () async {
      user.user.inventory[ShopItemIds.extraLife] = 1;
      final quiz = QuizProvider(
        user,
        repository: _FixedRepository([_question('q0', correctIndex: 2)]),
      );
      addTearDown(() {
        quiz.quitQuiz();
        quiz.dispose();
      });
      await quiz.startChapterQuiz('chapter.json', chapterId: 'test_chapter');
      expect(quiz.extraLifeAvailable, isTrue);
      expect(quiz.extraLifeUsed, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final remainingBefore = quiz.secondsRemaining;

      // startChapterQuiz shuffles options, so authored index 2 need not stay
      // correct and index 0 is not guaranteed to be wrong after loading.
      final question = quiz.currentQuestion!;
      final wrong = question.optionTexts.asMap().keys.firstWhere(
            (index) => index != question.correctIndex,
          );
      quiz.selectOption(wrong);
      expect(quiz.extraLifeUsed, isTrue);
      expect(quiz.extraLifeStock, 0);
      expect(quiz.isAnswerSubmitted, isFalse);
      expect(quiz.correctCount, 0);
      expect(quiz.wrongCount, 0);
      expect(quiz.secondsRemaining, remainingBefore,
          reason: 'a wrong-answer extra life must preserve the remaining time');

      // The run must be ticking again, or the player would have unlimited time.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(quiz.secondsRemaining, lessThan(remainingBefore),
          reason: 'the timer stayed cancelled after the extra life');
    });

    test('extra life on a timeout hands back five seconds, not a fresh question',
        () async {
      await useFastClock();
      user.user.inventory[ShopItemIds.extraLife] = 1;
      final quiz = QuizProvider(
        user,
        repository: _FixedRepository([_question('q0', correctIndex: 0)]),
      );
      await quiz.startChapterQuiz('chapter.json', chapterId: 'test_chapter');

      expect(quiz.questionTimeSec, 2, reason: 'the fast clock was not applied');
      // The countdown ticks once per second and only times out on the tick
      // *after* it reaches zero, so a two-second question needs ~3 s.
      await Future<void>.delayed(const Duration(milliseconds: 3500));
      expect(quiz.extraLifeUsed, isTrue, reason: 'the timeout never fired');
      expect(quiz.secondsRemaining, lessThanOrEqualTo(QuizProvider.kExtraLifeSeconds),
          reason: 'the countdown was reset to the full question time instead');

      quiz.quitQuiz();
    });

    test('skip and answer inside the skip window advance only once', () async {
      user.user.inventory[ShopItemIds.skipQuestion] = 1;
      final quiz = QuizProvider(
        user,
        repository: _FixedRepository([
          _question('q0'),
          _question('q1'),
          _question('q2'),
          _question('q3'),
        ]),
      );
      await quiz.startChapterQuiz('chapter.json', chapterId: 'test_chapter');

      expect(quiz.useSkipQuestion(), isTrue);
      // Tap inside the skip's 500 ms window: this used to enqueue a second
      // advance, and the two together could complete (and reward) the run twice.
      quiz.selectOption(quiz.currentQuestion!.correctIndex);
      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(quiz.currentIndex, 1, reason: 'two advances were applied');
      quiz.quitQuiz();
    });

    test('a completion cannot be rewarded twice', () async {
      user.user.inventory.clear();
      final quiz = QuizProvider(
        user,
        repository: _FixedRepository([_question('only')]),
      );
      await quiz.startChapterQuiz('chapter.json', chapterId: 'test_chapter');

      quiz.selectOption(quiz.currentQuestion!.correctIndex);
      expect(quiz.isQuizCompleted, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 1850));
      expect(quiz.isQuizCompleted, isTrue);

      final coinsAfterFirst = user.user.coins;
      // A stray second advance (the old code produced these) must be inert.
      quiz.nextQuestion();
      quiz.nextQuestion();
      expect(user.user.coins, coinsAfterFirst);
    });
  });
}
