import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/answer_record.dart';
import '../models/chapter_set_progress.dart';
import '../models/question_model.dart';
import '../models/shop_item.dart';
import '../repositories/quiz_repository.dart';
import '../services/haptic_service.dart';
import '../services/competition_clock.dart';
import '../services/hive_service.dart';
import '../services/sound_service.dart';
import '../services/trusted_ops_service.dart';
import 'user_provider.dart';
import '../../l10n/app_strings.dart';

/// Drives a quiz run. All timings and reward amounts come from
/// [UserProvider.config] (Hive/Firestore), never from magic numbers here.
class QuizProvider extends ChangeNotifier {
  final QuizRepository _repository;
  final UserProvider _userProvider;

  QuizProvider(this._userProvider, {QuizRepository? repository})
      : _repository = repository ?? QuizRepository();

  List<QuestionModel> _questions = [];

  /// One generator for the whole session, so option order is unpredictable
  /// but reproducible within a run when seeded in tests.
  final Random _rng = Random();

  /// Which set of the chapter is being played (0-based).
  int _setIndex = 0;

  /// True when this run is a replay and must not credit anything.
  bool _isPractice = false;

  /// True after the player quits mid-run.
  ///
  /// Quitting must freeze the run completely: the countdown stops, and the
  /// delayed `nextQuestion` callbacks already scheduled by an answer or a
  /// timeout become no-ops. Otherwise the abandoned quiz keeps playing
  /// tick/timeout sounds in the background and eventually grants rewards for
  /// a run the player walked away from.
  bool _abandoned = false;

  /// True while an advance to the next question is queued (after an answer, a
  /// timeout, or a skip). Without it, a skip and a tap inside the skip's 500 ms
  /// window both enqueued an advance — and the second one completed the run a
  /// second time, granting its rewards again.
  bool _transitionPending = false;

  /// Monotonic clock for the question on screen.
  ///
  /// Elapsed time used to be computed as `questionTimeSec - _secondsRemaining`,
  /// which goes negative the moment a freeze-time lifeline pushes the remaining
  /// seconds past the configured limit — poisoning the accuracy and tie-break
  /// numbers the run reports.
  final Stopwatch _questionClock = Stopwatch();

  /// Seconds handed back by an extra life.
  static const int kExtraLifeSeconds = 5;

  /// Bumped by every start and every quit. Async work carries the generation it
  /// belongs to, so a slow Firestore read that resolves after the player left
  /// cannot hand questions to a screen that is already gone.
  int _runGeneration = 0;

  /// True after [quitQuiz] until the next run starts.
  bool get isAbandoned => _abandoned;

  /// Questions the whole chapter holds, for "set 2 of 7".
  int _chapterQuestionCount = 0;

  /// Language the *questions* are shown in, independent of the app language.
  ///
  /// A Bengali student often wants the stem in Bangla but the technical terms
  /// in English, and switching the whole app mid-quiz would rebuild the tree
  /// and lose the run. So this is a view toggle over content that already
  /// ships in all three languages — nothing is translated at runtime.
  String? _displayLanguage;
  int _currentIndex = 0;
  int _score = 0;
  int _correctCount = 0;
  int _wrongCount = 0;
  int? _selectedOptionIndex;
  bool _isAnswerSubmitted = false;
  bool _isQuizCompleted = false;
  bool _isLoading = false;

  // Lifelines (per-question reset)
  bool _fiftyFiftyUsed = false;
  bool _freezeUsed = false;
  bool _skipUsed = false;
  bool _hintUsed = false;
  bool _audienceUsed = false;
  List<int> _disabledOptionIndices = [];

  // Active boosters (from inventory)
  bool _doublePointsActive = false;
  bool _extraLifeUsed = false;
  bool _extraLifeAvailable = false;

  // Hint & Audience data
  String? _currentHint;
  Map<int, int>? _audiencePollResults; // option index -> percentage

  // Quiz type + rewards
  bool _isDailyQuiz = false;

  /// True when the current daily run may be ranked: it plays the day's
  /// backend-published packet, so its score is comparable (R12). A daily run
  /// that fell back to a locally assembled practice set is played normally —
  /// coins, stats, streak — but is never submitted as a competition result.
  bool _isDailyRanked = false;

  /// Why today's daily run is not ranked, when it is not.
  String? _dailyUnrankedReason;
  String? _chapterId;
  String? _categoryTitle;
  String? _categoryTitleBn;
  String? _chapterTitle;
  String? _chapterTitleBn;
  int _earnedCoins = 0;
  int _earnedGems = 0;
  bool _dailyRewardSkipped = false;

  // Answer history (for the review screen)
  final List<AnswerRecord> _answerRecords = [];

  // Total time spent answering the current quiz (seconds).
  double _totalTimeSeconds = 0;

  // Timer
  int _secondsRemaining = 0;
  Timer? _timer;

  // ---------------------------------------------------------------- Getters --

  /// Seconds allowed per question (remote-configurable).
  int get questionTimeSec => _userProvider.config.secondsPerQuestion;

  List<QuestionModel> get questions => _questions;
  int get currentIndex => _currentIndex;
  int get score => _score;
  int get correctCount => _correctCount;
  int get wrongCount => _wrongCount;
  int? get selectedOptionIndex => _selectedOptionIndex;
  bool get isAnswerSubmitted => _isAnswerSubmitted;
  bool get isQuizCompleted => _isQuizCompleted;
  bool get isLoading => _isLoading;
  bool get isDailyQuiz => _isDailyQuiz;
  bool get isDailyRanked => _isDailyQuiz && _isDailyRanked;
  String? get dailyUnrankedReason => _dailyUnrankedReason;
  int get secondsRemaining => _secondsRemaining;
  List<int> get disabledOptionIndices => _disabledOptionIndices;

  /// True when the question bank was empty — the screen shows an empty state
  /// instead of placeholder questions.
  bool get hasNoQuestions => !_isLoading && _questions.isEmpty;

  // Inventory stocks
  int get fiftyFiftyStock =>
      _userProvider.inventoryCount(ShopItemIds.fiftyFifty);
  int get freezeTimeStock =>
      _userProvider.inventoryCount(ShopItemIds.freezeTime);
  int get skipQuestionStock =>
      _userProvider.inventoryCount(ShopItemIds.skipQuestion);
  int get hintRevealStock =>
      _userProvider.inventoryCount(ShopItemIds.hintReveal);
  int get audiencePollStock =>
      _userProvider.inventoryCount(ShopItemIds.audiencePoll);
  int get extraLifeStock => _userProvider.inventoryCount(ShopItemIds.extraLife);
  int get doublePointsStock =>
      _userProvider.inventoryCount(ShopItemIds.doublePoints);

  // Per-question usage flags
  bool get fiftyFiftyUsed => _fiftyFiftyUsed;
  bool get freezeUsed => _freezeUsed;
  bool get skipUsed => _skipUsed;
  bool get hintUsed => _hintUsed;
  bool get audienceUsed => _audienceUsed;

  // Active booster states
  bool get doublePointsActive => _doublePointsActive;
  bool get extraLifeAvailable => _extraLifeAvailable;
  bool get extraLifeUsed => _extraLifeUsed;

  // Hint & Audience data
  String? get currentHint => _currentHint;
  Map<int, int>? get audiencePollResults => _audiencePollResults;

  /// Coins actually credited for the finished quiz (0 if replay denied).
  int get earnedCoins => _earnedCoins;

  /// Gems actually credited for the finished quiz (0 if replay denied).
  int get earnedGems => _earnedGems;

  /// True when this daily quiz earned nothing because today's reward was
  /// already claimed.
  bool get dailyRewardSkipped => _dailyRewardSkipped;

  /// The player's answer history for the finished quiz (for the review screen).
  List<AnswerRecord> get answerRecords => List.unmodifiable(_answerRecords);

  /// Total seconds spent answering the finished quiz.
  double get totalTimeSeconds => _totalTimeSeconds;

  QuestionModel? get currentQuestion =>
      _questions.isNotEmpty && _currentIndex < _questions.length
          ? _questions[_currentIndex]
          : null;

  // ------------------------------------------------------------- Lifecycle --

  /// How long the 3D loading card stays up so it can actually be seen.
  /// Local JSON loads in milliseconds otherwise, and the intro would flash.
  static const Duration _dailyIntroMin = Duration(milliseconds: 2000);

  /// Initialize the Daily Quiz.
  Future<void> startDailyQuiz() async {
    _resetQuizState();
    final runGeneration = _runGeneration;
    _isDailyQuiz = true;
    _isLoading = true;
    notifyListeners();

    final sw = Stopwatch()..start();
    final dailySet = await _repository.getDailyQuizSet();
    final dailyQuestions = dailySet.questions;
    _isDailyRanked = dailySet.ranked;
    _dailyUnrankedReason = dailySet.unrankedReason;
    await _holdIntro(sw, _dailyIntroMin);
    // The player may have quit (or started another run) while the questions
    // were loading — that request must not revive the abandoned screen.
    if (runGeneration != _runGeneration) return;

    _questions = _shuffleOptions(dailyQuestions);
    _isLoading = false;

    // Check for active boosters
    _checkActiveBoosters();

    if (_questions.isNotEmpty) _startTimer();
    SoundService.instance.play('quiz_start');
    Haptics.tap();
    notifyListeners();
  }

  /// Starts one **set** of a chapter.
  ///
  /// A chapter is served ten questions at a time (see [kQuestionsPerSet]).
  /// Banks grow indefinitely through the admin panel, and a 200-question
  /// sitting is one nobody finishes; ten is a session a student completes and
  /// comes back to.
  ///
  /// Set boundaries are stable because questions are only ever appended —
  /// adding to a chapter creates new sets at the end, it never reshuffles what
  /// somebody has already cleared.
  ///
  /// [practice] replays a set the student has already finished. Nothing is
  /// credited in that mode: no coins, no gems, no stats, no leaderboard, no
  /// history row. Retrying must never be a way to farm rewards, and a student
  /// must never feel that revising costs them something either.
  Future<void> startChapterQuiz(
    String jsonFilePath, {
    String? chapterId,
    String? categoryTitle,
    String? categoryTitleBn,
    String? chapterTitle,
    String? chapterTitleBn,
    int setIndex = 0,
    bool practice = false,
  }) async {
    _resetQuizState();
    final runGeneration = _runGeneration;
    _isDailyQuiz = false;
    _chapterId = chapterId ?? jsonFilePath;
    _categoryTitle = categoryTitle;
    _categoryTitleBn = categoryTitleBn;
    _chapterTitle = chapterTitle;
    _chapterTitleBn = chapterTitleBn;
    _setIndex = setIndex;
    _isPractice = practice;
    _isLoading = true;
    notifyListeners();

    // Pass the chapter id so admin-authored questions are merged in — without
    // it the repository can only see the bundled asset bank.
    final all = await _repository.getChapterQuestions(
      jsonFilePath,
      chapterId: chapterId,
    );
    if (runGeneration != _runGeneration) return;
    _chapterQuestionCount = all.length;

    final start = setStartIndex(setIndex);
    final slice = start >= all.length
        ? const <QuestionModel>[]
        : all.sublist(
            start,
            (start + kQuestionsPerSet).clamp(0, all.length),
          );

    _questions = _shuffleOptions(slice);
    _isLoading = false;

    // Check for active boosters
    _checkActiveBoosters();

    if (_questions.isNotEmpty) _startTimer();
    SoundService.instance.play('quiz_start');
    Haptics.tap();
    notifyListeners();
  }

  /// 0-based index of the set being played.
  int get setIndex => _setIndex;

  /// Human-facing set number.
  int get setNumber => _setIndex + 1;

  /// How many sets the chapter has in total.
  int get setCount => setCountFor(_chapterQuestionCount);

  /// True when nothing in this run counts towards rewards or stats.
  bool get isPractice => _isPractice;

  /// Language the question text is currently rendered in.
  String get displayLanguage => _displayLanguage ?? S.code;

  /// True when the player has overridden the app language for this quiz.
  bool get isLanguageOverridden => _displayLanguage != null;

  /// Languages the current question actually carries, so the picker never
  /// offers a tab that would silently fall back to English.
  List<String> get availableLanguages {
    final question = currentQuestion;
    if (question == null) return const [];
    return kSupportedLanguageCodes
        .where((code) => question.questionText.has(code))
        .toList();
  }

  void setDisplayLanguage(String code) {
    if (_displayLanguage == code) return;
    _displayLanguage = code;
    notifyListeners();
  }

  /// Check if player has active boosters in inventory.
  void _checkActiveBoosters() {
    // Double Points booster - check if owned
    _doublePointsActive = _userProvider.hasItem(ShopItemIds.doublePoints);

    // Extra Life - check if owned
    _extraLifeAvailable = _userProvider.hasItem(ShopItemIds.extraLife);

    if (_doublePointsActive) {
      SoundService.instance.play('boost');
      Haptics.medium();
    }
  }

  /// Keeps [isLoading] true long enough for the 3D intro card to play.
  Future<void> _holdIntro(Stopwatch sw, Duration min) async {
    final left = min - sw.elapsed;
    if (left > Duration.zero) await Future<void>.delayed(left);
  }

  /// Randomises option order once per load.
  ///
  /// Done here rather than in the widget: a shuffle inside build() would
  /// re-roll on every rebuild — every tick of the countdown — and the options
  /// would move while the player is reading them.
  List<QuestionModel> _shuffleOptions(List<QuestionModel> questions) =>
      [for (final question in questions) question.withShuffledOptions(_rng)];

  /// Quits the current run: stops the countdown and disarms pending delayed
  /// advances so a quit quiz can neither play sounds nor grant rewards in
  /// the background. The next [startDailyQuiz]/[startChapterQuiz] resets.
  void quitQuiz() {
    _abandoned = true;
    _runGeneration++;
    _timer?.cancel();
    // The run is over: nothing is loading any more. Without this the provider
    // stayed in its loading state after a quit (the screen had already popped,
    // so nothing noticed — except the next cold read of `isLoading`).
    _isLoading = false;
    notifyListeners();
  }

  void _resetQuizState() {
    _timer?.cancel();
    _questionClock
      ..stop()
      ..reset();
    _transitionPending = false;
    _runGeneration++;
    _abandoned = false;
    // Each quiz starts in the app language; a peek at another language is a
    // per-run decision, not a hidden setting that quietly persists.
    _displayLanguage = null;
    _isPractice = false;
    _isDailyRanked = false;
    _dailyUnrankedReason = null;
    _setIndex = 0;
    _chapterQuestionCount = 0;
    _currentIndex = 0;
    _score = 0;
    _correctCount = 0;
    _wrongCount = 0;
    _selectedOptionIndex = null;
    _isAnswerSubmitted = false;
    _isQuizCompleted = false;

    // Reset per-question lifelines
    _fiftyFiftyUsed = false;
    _freezeUsed = false;
    _skipUsed = false;
    _hintUsed = false;
    _audienceUsed = false;
    _disabledOptionIndices = [];

    // Reset boosters
    _doublePointsActive = false;
    _extraLifeUsed = false;
    _extraLifeAvailable = false;

    // Reset hint & audience
    _currentHint = null;
    _audiencePollResults = null;

    _earnedCoins = 0;
    _earnedGems = 0;
    _dailyRewardSkipped = false;
    _answerRecords.clear();
    _totalTimeSeconds = 0;
    _chapterId = null;
    _categoryTitle = null;
    _categoryTitleBn = null;
    _chapterTitle = null;
    _chapterTitleBn = null;
    _questions = [];
    _secondsRemaining = questionTimeSec;
  }

  /// (Re)starts the per-question countdown.
  ///
  /// [seconds] overrides the starting value (an extra life hands back a few
  /// seconds, not a fresh question), and [restartClock] is false when the
  /// question is continuing — the elapsed clock must keep running then.
  void _startTimer({int? seconds, bool restartClock = true}) {
    _timer?.cancel();
    _secondsRemaining = seconds ?? questionTimeSec;
    if (restartClock) {
      _questionClock
        ..reset()
        ..start();
    } else {
      _questionClock.start(); // no-op when already running
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        _secondsRemaining--;
        // Urgency tick for the final 5 seconds.
        if (_secondsRemaining <= 5) {
          SoundService.instance.play('quiz_tick');
        }
        notifyListeners();
      } else {
        _timer?.cancel();
        _handleTimeout();
      }
    });
  }

  // ---------------------------------------------------------------- Playing --

  void selectOption(int index) {
    if (_isAnswerSubmitted ||
        _transitionPending ||
        _disabledOptionIndices.contains(index)) {
      return;
    }

    _selectedOptionIndex = index;
    _isAnswerSubmitted = true;
    _timer?.cancel();

    final correctIndex = currentQuestion?.correctIndex ?? 0;
    if (index == correctIndex) {
      _correctCount++;
      // Score calculation: fixed 10 points per correct answer.
      // 1 correct = 10, 2 correct = 20, ... 10 correct = 100.
      var points = 10;

      // Apply double points booster
      if (_doublePointsActive) {
        points *= 2;
      }

      _score += points;
      SoundService.instance.play('quiz_correct');
      Haptics.light();
    } else {
      // Wrong answer - check for extra life
      if (_extraLifeAvailable && !_extraLifeUsed) {
        _extraLifeUsed = true;
        _spendItem(ShopItemIds.extraLife);
        _isAnswerSubmitted = false;
        _selectedOptionIndex = null;
        SoundService.instance.play('revive');
        Haptics.heavy();
        // The timer was cancelled a few lines above. Restarting it with the
        // time that was left is what makes the retry a second chance rather
        // than an untimed one.
        _startTimer(
          seconds: _secondsRemaining <= 0 ? 1 : _secondsRemaining,
          restartClock: false,
        );
        notifyListeners();
        return; // Don't count as wrong, let them try again
      }
      _wrongCount++;
      SoundService.instance.play('quiz_wrong');
      Haptics.error();
    }

    final q = currentQuestion;
    if (q != null) {
      _answerRecords.add(
        AnswerRecord(
          question: q,
          selectedIndex: index,
          status: AnswerStatus.answered,
        ),
      );
    }

    notifyListeners();

    // Auto next after 1.8 seconds
    _totalTimeSeconds += _stopQuestionClock();
    _scheduleAdvance(const Duration(milliseconds: 1800));
  }

  void _handleTimeout() {
    if (_abandoned || _isAnswerSubmitted || _transitionPending) return;
    _isAnswerSubmitted = true;

    // Check for extra life on timeout
    if (_extraLifeAvailable && !_extraLifeUsed) {
      _extraLifeUsed = true;
      _spendItem(ShopItemIds.extraLife);
      _isAnswerSubmitted = false;
      SoundService.instance.play('revive');
      Haptics.heavy();
      // `_startTimer()` on its own resets the countdown to the full configured
      // question time, which silently threw away the five seconds the extra
      // life is supposed to give back.
      _startTimer(seconds: kExtraLifeSeconds, restartClock: false);
      notifyListeners();
      return;
    }

    _wrongCount++;
    _totalTimeSeconds += _stopQuestionClock();
    SoundService.instance.play('quiz_timeout');
    Haptics.error();

    final q = currentQuestion;
    if (q != null) {
      _answerRecords.add(
        AnswerRecord(
          question: q,
          selectedIndex: null,
          status: AnswerStatus.timedOut,
        ),
      );
    }

    notifyListeners();

    _scheduleAdvance(const Duration(milliseconds: 1800));
  }

  void nextQuestion() {
    // A delayed advance scheduled before the player quit must not resurrect
    // the run — no sounds, no completion, no rewards.
    if (_abandoned) {
      return;
    }
    // Never finish the same run twice: a second late advance used to walk the
    // completion path again and grant the same rewards a second time.
    if (_isQuizCompleted) {
      return;
    }
    _transitionPending = false;
    if (_currentIndex < _questions.length - 1) {
      _currentIndex++;
      _selectedOptionIndex = null;
      _isAnswerSubmitted = false;
      _disabledOptionIndices = [];

      // Reset per-question lifeline flags
      _fiftyFiftyUsed = false;
      _freezeUsed = false;
      _skipUsed = false;
      _hintUsed = false;
      _audienceUsed = false;

      // Reset hint & audience data
      _currentHint = null;
      _audiencePollResults = null;

      SoundService.instance.play('ui_whoosh');
      _startTimer();
    } else {
      _isQuizCompleted = true;
      _timer?.cancel();

      // Consume double points booster if used (never on a practice run)
      if (_doublePointsActive) {
        _spendItem(ShopItemIds.doublePoints);
      }

      final perfect =
          _questions.isNotEmpty && _correctCount == _questions.length;
      SoundService.instance.play(perfect ? 'quiz_perfect' : 'quiz_complete');
      Haptics.heavy();

      _grantRewards();
      _recordSetProgress();
    }
    notifyListeners();
  }

  /// Stores the result against this chapter set so the sets screen can show
  /// it as cleared, unlock the next one, and offer a replay.
  ///
  /// Runs for practice attempts too: [ChapterSetProgress.merge] keeps the
  /// better score and leaves `completedAt` alone, so a replay never makes a
  /// long-finished set look new.
  void _recordSetProgress() {
    if (_isDailyQuiz || _chapterId == null) return;
    unawaited(HiveService.saveChapterSet(
      chapterId: _chapterId!,
      setIndex: _setIndex,
      score: _score,
      correct: _correctCount,
      total: _questions.length,
    ));
  }

  /// Stops the elapsed clock and returns whole seconds spent on this question.
  int _stopQuestionClock() {
    _questionClock.stop();
    return (_questionClock.elapsedMilliseconds / 1000).round().clamp(0, 3600);
  }

  /// Queues the advance to the next question, tagged with the run it belongs to.
  ///
  /// `_resetQuizState()` clears `_abandoned`, so a callback left over from the
  /// previous run would happily advance the *new* one. The run generation is
  /// the only token that survives a reset.
  void _scheduleAdvance(Duration delay) {
    final generation = _runGeneration;
    _transitionPending = true;
    Future.delayed(delay, () {
      if (generation != _runGeneration) return;
      nextQuestion();
    });
  }

  /// Takes one unit of [itemId] from the inventory.
  ///
  /// Practice runs are free: replaying a finished set changes no economy at
  /// all, and a learner revising a chapter should not have to spend power-ups
  /// to do it.
  bool _spendItem(String itemId) =>
      _isPractice ? true : _userProvider.consumeItem(itemId);

  /// Calculates coins & gems from the remote config, saves the run into the
  /// Hive-backed stats and credits the player (daily rewards once per day).
  ///
  /// Practice runs return before any of that: they earn no coins, gems or XP,
  /// write no stats or history, and consume nothing from the inventory. Set
  /// progress is still merged in [_recordSetProgress], which is how a replay
  /// can show a better score without pretending to be a first completion.
  void _grantRewards() {
    if (_isPractice) {
      _earnedCoins = 0;
      _earnedGems = 0;
      _dailyRewardSkipped = true;
      return;
    }
    final config = _userProvider.config;
    final total = _questions.length;
    final isPerfect = total > 0 && _correctCount == total;

    int coins;
    int gems;

    if (_isDailyQuiz) {
      coins = _correctCount * config.coinsPerCorrectDaily;
      if (isPerfect) coins += config.perfectBonusCoins;
      gems = isPerfect
          ? config.gemsPerfect
          : (_correctCount >= config.highScoreThreshold
              ? config.gemsHighScore
              : 0);
    } else {
      // Chapter quiz: coins & gems granted every time based on performance
      coins = _correctCount * config.coinsPerCorrectPractice;
      if (isPerfect) coins += config.perfectBonusCoins;
      gems = isPerfect
          ? config.gemsPerfect
          : (_correctCount >= config.highScoreThreshold
              ? config.gemsHighScore
              : 0);
    }

    // Apply coin booster if active
    if (_userProvider.hasItem(ShopItemIds.coinBooster)) {
      coins *= 2;
      _userProvider.consumeItem(ShopItemIds.coinBooster);
    }

    // Persist accuracy / streak / per-chapter progress to Hive and mirror it
    // to Firestore (the leaderboard entry is pushed from there too).
    _userProvider.recordQuizResult(
      answered: _answerRecords.length,
      correct: _correctCount,
      timeSeconds: _totalTimeSeconds,
      isDaily: _isDailyQuiz,
      // Only a ranked daily run may touch the day's leaderboard entry (R12).
      ranked: _isDailyRanked,
      score: _score,
      chapterId: _isDailyQuiz ? null : _chapterId,
      categoryTitle: _isDailyQuiz ? null : _categoryTitle,
      categoryTitleBn: _isDailyQuiz ? null : _categoryTitleBn,
      chapterTitle: _isDailyQuiz ? null : _chapterTitle,
      chapterTitleBn: _isDailyQuiz ? null : _chapterTitleBn,
      coinsEarned: coins,
      gemsEarned: gems,
    );

    final granted = _userProvider.grantQuizRewards(
      coins: coins,
      gems: gems,
      isDailyQuiz: _isDailyQuiz,
    );

    // Grant XP
    _userProvider.grantXp(
      score: _score,
      correctCount: _correctCount,
      isDailyQuiz: _isDailyQuiz,
    );

    if (granted) {
      _earnedCoins = coins;
      _earnedGems = gems;
      _dailyRewardSkipped = false;
    } else {
      _earnedCoins = 0;
      _earnedGems = 0;
      _dailyRewardSkipped = true;
    }

    if (granted && (coins > 0 || gems > 0)) {
      SoundService.instance.play('coin');
      Haptics.medium();
    }

    // P0 (R02): the daily credit is also applied server-side (trusted
    // backend, idempotent per day). Fail-soft: no-op when offline or when
    // the functions are not deployed yet.
    if (_isDailyQuiz && _isDailyRanked && granted && !_userProvider.user.isGuest) {
      final now = DateTime.now();
      TrustedOpsService.submitDailyResult(
        // The competition day, not the device's local date — otherwise two
        // players in different timezones would submit to different days (R12).
        date: CompetitionClock.dateKey(now),
        score: _score,
        correct: _correctCount,
        total: _questions.length,
        timeSeconds: _totalTimeSeconds,
      );
    }
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // -------------------------------------------------------------- Lifelines --

  /// Uses the 50-50 lifeline. Consumes one unit from the player's inventory.
  /// Removes 2 wrong options so exactly 2 options remain (1 correct + 1 wrong).
  bool useFiftyFifty() {
    if (_fiftyFiftyUsed || _isAnswerSubmitted || currentQuestion == null) {
      return false;
    }
    if (!_spendItem(ShopItemIds.fiftyFifty)) {
      return false;
    }
    _fiftyFiftyUsed = true;
    final correct = currentQuestion!.correctIndex;
    final wrongOptions = [
      for (var i = 0; i < currentQuestion!.optionTexts.length; i++)
        if (i != correct) i
    ]..shuffle();
    // Remove 2 wrong options on a 4-option question to leave exactly 2 options active.
    final toRemove = wrongOptions.length >= 2 ? 2 : 1;
    _disabledOptionIndices = wrongOptions.take(toRemove).toList();
    SoundService.instance.play('lifeline_5050');
    Haptics.light();
    notifyListeners();
    return true;
  }

  /// Adds extra seconds to the timer. Consumes one unit from the player's
  /// inventory. Can be used once per question.
  bool useFreezeTime() {
    if (_freezeUsed || _isAnswerSubmitted || currentQuestion == null) {
      return false;
    }
    if (!_spendItem(ShopItemIds.freezeTime)) {
      return false;
    }
    _freezeUsed = true;
    _secondsRemaining += 10;
    SoundService.instance.play('lifeline_freeze');
    Haptics.light();
    notifyListeners();
    return true;
  }

  /// Skips the current question using inventory item.
  /// Returns false if can't be used.
  bool useSkipQuestion() {
    if (_skipUsed ||
        _isAnswerSubmitted ||
        _transitionPending ||
        currentQuestion == null) {
      return false;
    }
    if (!_spendItem(ShopItemIds.skipQuestion)) {
      return false;
    }
    _skipUsed = true;
    _timer?.cancel();
    _totalTimeSeconds += _stopQuestionClock();

    final q = currentQuestion;
    if (q != null) {
      _answerRecords.add(
        AnswerRecord(
          question: q,
          selectedIndex: null,
          status: AnswerStatus.skipped,
        ),
      );
    }

    _scheduleAdvance(const Duration(milliseconds: 500));
    SoundService.instance.play('lifeline_skip');
    Haptics.light();
    notifyListeners();
    return true;
  }

  /// Reveals a hint for the current question. Consumes one unit.
  /// Returns false if can't be used.
  bool useHintReveal() {
    if (_hintUsed || _isAnswerSubmitted || currentQuestion == null) {
      return false;
    }
    if (!_spendItem(ShopItemIds.hintReveal)) {
      return false;
    }
    _hintUsed = true;

    // Generate hint from the correct answer
    final correctIndex = currentQuestion!.correctIndex;
    // Follows the displayed language: a Bangla quiz must not reveal a hint
    // built from the English wording.
    final correctAnswer =
        currentQuestion!.optionsIn(displayLanguage)[correctIndex];
    _currentHint = _generateHint(correctAnswer);

    SoundService.instance.play('lifeline_hint');
    Haptics.light();
    notifyListeners();
    return true;
  }

  /// Generates a hint from the correct answer.
  String _generateHint(String answer) {
    if (answer.length <= 3) {
      return 'The answer is short (${answer.length} chars)';
    }

    final words = answer.split(' ');
    if (words.length == 1) {
      // Single word: show first and last letter
      return 'Starts with "${answer[0]}" and ends with "${answer[answer.length - 1]}"';
    } else {
      // Multiple words: show word count and first letter
      return '${words.length} words, starts with "${words[0][0]}"';
    }
  }

  /// Shows audience poll results. Consumes one unit.
  /// Returns false if can't be used.
  bool useAudiencePoll() {
    if (_audienceUsed || _isAnswerSubmitted || currentQuestion == null) {
      return false;
    }
    if (!_userProvider.consumeItem(ShopItemIds.audiencePoll)) {
      return false;
    }
    _audienceUsed = true;

    // Generate realistic audience poll results
    final correctIndex = currentQuestion!.correctIndex;
    _audiencePollResults = _generateAudiencePoll(correctIndex);

    SoundService.instance.play('lifeline_audience');
    Haptics.light();
    notifyListeners();
    return true;
  }

  /// Generates realistic audience poll results.
  Map<int, int> _generateAudiencePoll(int correctIndex) {
    final random = Random();
    final results = <int, int>{};

    // Correct answer gets highest percentage (40-70%)
    results[correctIndex] = 40 + random.nextInt(31);

    // Distribute remaining percentage among other options
    var remaining = 100 - results[correctIndex]!;
    final otherOptions = [0, 1, 2, 3]..remove(correctIndex);

    for (var i = 0; i < otherOptions.length; i++) {
      if (i == otherOptions.length - 1) {
        results[otherOptions[i]] = remaining;
      } else {
        final maxForThis = (remaining * 0.6).toInt();
        final value = random.nextInt(maxForThis + 1);
        results[otherOptions[i]] = value;
        remaining -= value;
      }
    }

    return results;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
