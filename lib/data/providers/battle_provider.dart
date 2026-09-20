import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../l10n/app_strings.dart';
import '../models/battle_room.dart';
import '../models/battle_scoring.dart';
import '../models/question_model.dart';
import '../services/battle_question_generator.dart';
import '../services/battle_room_service.dart';
import '../services/challenge_service.dart';
import '../services/haptic_service.dart';
import '../services/hive_service.dart';
import '../services/sound_service.dart';
import 'user_provider.dart';

enum BattleDifficulty { easy, normal, hard }

enum BattlePhase { setup, searching, found, countdown, question, reveal, finished }

/// Who the player is fighting this match.
class BattleOpponent {
  final String name;
  final String avatar; // asset path or https URL
  final bool isBot;
  final String? uid;

  const BattleOpponent({
    required this.name,
    required this.avatar,
    required this.isBot,
    this.uid,
  });
}

/// Points a single question just paid out, for the reveal summary.
class BattleRoundPoints {
  final int base;         // +10 for correct answer
  final int speedBonus;   // up to +10 — time-scaled (instant answer = full)
  final int firstBonus;   // +3 if locked in before the opponent
  final int streakBonus;  // +2 × streak count (capped)
  final int msTaken;      // how long this side took to answer (0 = unknown)

  const BattleRoundPoints({
    required this.base,
    required this.speedBonus,
    required this.streakBonus,
    this.firstBonus = 0,
    this.msTaken = 0,
  });

  int get total => base + speedBonus + firstBonus + streakBonus;

  // backward-compat alias used in live room write/read
  int get timeBonus => speedBonus;

  static const zero = BattleRoundPoints(base: 0, speedBonus: 0, streakBonus: 0);

  /// Same points but stamped with the time taken — used for the reveal view.
  BattleRoundPoints withMs(int ms) => BattleRoundPoints(
        base: base,
        speedBonus: speedBonus,
        firstBonus: firstBonus,
        streakBonus: streakBonus,
        msTaken: ms,
      );
}

/// Drives a 1-vs-1 battle — live room or bot.
///
/// ## Flow (per `docs/12_BATTLE_1V1_REAL_PLAYER_PLAN.md`)
///
/// ```text
/// setup → searching ── real player found ──→ found(VS intro) → countdown
///              │                                            → question ×5
///              └── bot fallback (guest/offline/timeout) ──→  (same, local bot)
///                                                      │
///                                                      → reveal → finished
/// ```
///
/// * **Live rooms** sync through Firestore (`battle_rooms/{roomId}`): the room
///   is the source of truth for answers/scores. Pacing is anchored to the
///   creator-written `countdown_until` and each question's `reveal_until`, so
///   both clients run the same schedule (drift cannot accumulate).
/// * **Bot matches** reuse the same phase machine locally, with the bot's
///   difficulty-driven accuracy and think-delay feeding the same scoring
///   formula, so the scoreboard is always symmetric.
/// * **Scoring** per correct answer (Kahoot-style, symmetric for both sides):
///   `base (10) + speed bonus (up to 10, scaled by time remaining)
///   + first bonus (3, locked in before the opponent)
///   + streak bonus (2 × streak, capped)`.
///   An equal-score tie is broken by total answer time — the faster brain
///   wins, mirroring the leaderboard's tie-break rule.
class BattleProvider extends ChangeNotifier {
  /// [roomService] / [challengeService] / [questionGenerator] are injectable
  /// so the match lifecycle can be unit-tested with fakes (they default to the
  /// real Firestore-backed implementations).
  BattleProvider(
    this._userProvider, {
    BattleRoomService? roomService,
    ChallengeService? challengeService,
    BattleQuestionGenerator? questionGenerator,
  })  : _roomService = roomService ?? BattleRoomService(),
        _challengeService = challengeService ?? ChallengeService(),
        _questionGenerator = questionGenerator ?? BattleQuestionGenerator();

  final UserProvider _userProvider;
  final BattleRoomService _roomService;
  final BattleQuestionGenerator _questionGenerator;
  final Random _rng = Random();

  /// Counter that makes match ids unique even when two matches are created in
  /// the same microsecond (rematch, rapid re-queue).
  static int _matchCounter = 0;

  // ----------------------------------------------------------- questions --

  List<QuestionModel> _questions = [];
  int _currentIndex = 0;

  // ----------------------------------------------------------- opponent --

  BattleOpponent? _opponent;
  BattleOpponent? _lastOpponent; // persists across reset for revenge match
  final ChallengeService _challengeService;
  String? _revengeChallengeId;
  StreamSubscription<ChallengeData?>? _revengeChallengeSub;
  bool _isBotMatch = true;

  // -------------------------------------------------------------- player --

  int _playerScore = 0;
  int _playerCorrect = 0;
  int _playerStreak = 0;
  int? _playerSelected;
  bool _playerAnswered = false;
  bool _playerTimedOut = false;
  BattleRoundPoints _lastRoundPlayer = BattleRoundPoints.zero;

  // ------------------------------------------------------------ opponent --

  int _opponentScore = 0;
  int _opponentCorrect = 0;
  int _opponentStreak = 0;
  int? _opponentSelected;
  bool _opponentAnswered = false;
  BattleRoundPoints _lastRoundOpponent = BattleRoundPoints.zero;

  // -------------------------------------------------------------- timing --

  BattlePhase _phase = BattlePhase.setup;
  BattleDifficulty _difficulty = BattleDifficulty.normal;

  int _secondsRemaining = 0;
  int _countdownValue = 3;

  int _countdownUntilMs = 0;
  int _questionDeadlineMs = 0;
  int _questionDurationSec = 15;
  int _revealUntilMs = 0;
  int _botAnswerAtMs = 0;

  // Total ms each side has spent answering (all questions, incl. timeouts).
  // Used for the equal-score tie-break: the faster side wins.
  int _playerTotalMs = 0;
  int _botTotalMs = 0;

  int _searchStartMs = 0;
  int _searchDurationMs = 0;
  String _userId = '';
  bool _liveCapable = false;

  Timer? _tickTimer; // 200 ms — drives every phase
  Timer? _pollTimer; // 1.5 s — matchmaking probe

  // ---------------------------------------------------------------- live --

  String? _roomId;
  String _side = 'a';
  BattleRoomData? _room;
  StreamSubscription<BattleRoomData?>? _roomSub;
  int _lastHeartbeatMs = 0;
  bool _forfeitWin = false;

  /// Unique id of the current match inside the deterministic room id. A
  /// rematch reuses the room id, so rewards are guarded per match (R11).
  String? _matchId;

  /// True once a room document has actually been observed in this match.
  /// Before that, a missing document is a creation race, not a departure.
  bool _sawRoom = false;
  bool _attachedWritten = false;
  int _roomMissingSinceMs = 0;

  /// Set when this match came from a challenge/rematch, i.e. the opponent is
  /// known and a random bot fallback must never be substituted (R10).
  bool _opponentIsKnown = false;

  /// Hard matchmaking failure (missing index or denied query) — shown to the
  /// player instead of being reported as an empty queue (R17).
  String? _matchmakingError;

  /// Why the last live match could not be started, for the setup screen.
  String? _startError;

  // ------------------------------------------------------------- results --

  int _earnedCoins = 0;
  int _earnedGems = 0;
  bool _emptyBank = false;

  // -------------------------------------------------------------- getters --

  BattlePhase get phase => _phase;
  BattleDifficulty get difficulty => _difficulty;
  BattleOpponent? get opponent => _opponent;
  BattleOpponent? get lastOpponent => _lastOpponent;
  bool get hasRematchTarget => _lastOpponent != null;
  String? get revengeChallengeId => _revengeChallengeId;
  bool get isLive => _opponent?.isBot == false;

  /// Unique session id of the current live match (null for bot matches).
  String? get matchSessionId => _matchId;

  bool get hasMatchSession => (_matchId ?? '').isNotEmpty;

  /// Non-null when matchmaking itself is broken (index/permission) — the UI
  /// shows this instead of pretending nobody is online.
  String? get matchmakingError => _matchmakingError;

  /// Non-null when a live match could not be started at all.
  String? get startError => _startError;

  void clearStartError() {
    if (_startError == null && _matchmakingError == null) return;
    _startError = null;
    _matchmakingError = null;
    notifyListeners();
  }
  bool get isBotMatch => _isBotMatch;
  bool get isForfeit => _forfeitWin;
  bool get hasNoQuestions => _emptyBank;

  int get countdownValue => _countdownValue;
  int get secondsRemaining => _secondsRemaining;
  int get questionTimeSec => _questionDurationSec;

  int get currentIndex => _currentIndex;
  int get totalQuestions => _questions.length;
  List<QuestionModel> get questions => List.unmodifiable(_questions);

  QuestionModel? get currentQuestion =>
      _questions.isNotEmpty && _currentIndex < _questions.length
          ? _questions[_currentIndex]
          : null;

  String get opponentName => _opponent?.name ?? 'Opponent';
  String get opponentAvatar => _opponent?.avatar ?? '';
  int get opponentScore => isLive ? (_room?.opponentOf(_side)?.score ?? _opponentScore) : _opponentScore;
  int get opponentCorrect => isLive ? (_room?.opponentOf(_side)?.correct ?? _opponentCorrect) : _opponentCorrect;
  int get opponentStreak => isLive ? (_room?.opponentOf(_side)?.streak ?? _opponentStreak) : _opponentStreak;

  int get playerScore => _playerScore;
  int get playerCorrect => _playerCorrect;
  int get playerStreak => _playerStreak;

  int? get playerSelected => _playerSelected;
  bool get playerAnswered => _playerAnswered;
  bool get playerTimedOut => _playerTimedOut;

  int? get opponentSelected {
    if (isLive) {
      return _room?.opponentOf(_side)?.answerFor(_currentIndex)?.selected;
    }
    return _opponentSelected;
  }

  bool get opponentAnswered {
    if (isLive) {
      return _room?.opponentOf(_side)?.answerFor(_currentIndex) != null;
    }
    return _opponentAnswered;
  }

  bool get opponentTimedOut {
    // Bot matches never time out: the bot always answers inside its delay,
    // which is shorter than any question window.
    if (isLive) {
      return _room?.opponentOf(_side)?.answerFor(_currentIndex)?.timedOut ?? false;
    }
    return false;
  }

  BattleRoundPoints get lastRoundPlayer => _lastRoundPlayer;
  int get lastRoundPlayerPts => _lastRoundPlayer.total;
  BattleRoundPoints get lastRoundOpponent => _lastRoundOpponent;
  int get lastRoundOpponentPts => _lastRoundOpponent.total;

  /// Total ms this player has spent answering across the whole match.
  int get playerTotalMs => _playerTotalMs;

  /// Total ms the opponent has spent answering (live: summed from the room's
  /// answer records; bot: the bot's accumulated think time).
  int get opponentTotalMs {
    if (isLive) {
      final opponent = _room?.opponentOf(_side);
      if (opponent == null) return 0;
      var sum = 0;
      for (final answer in opponent.answers.values) {
        sum += answer.msTaken;
      }
      return sum;
    }
    return _botTotalMs;
  }

  /// Breaks an equal-score tie: the side that answered faster overall wins
  /// (mirrors the leaderboard's "equal scores ranked by fastest time").
  /// Returns null when there is no tie to break or no reliable timing data
  /// (legacy rooms / forfeits) — then it stays a true draw.
  String? _tieBreakSide() {
    if (playerScore != opponentScore) return null;
    final myMs = _playerTotalMs;
    final oppMs = opponentTotalMs;
    if (myMs <= 0 || oppMs <= 0) return null;
    if (myMs == oppMs) return null;
    return myMs < oppMs ? _side : (_side == 'a' ? 'b' : 'a');
  }

  bool get isPlayerWin =>
      playerScore > opponentScore || _tieBreakSide() == _side;

  bool get isDraw => playerScore == opponentScore && _tieBreakSide() == null;

  /// Seconds left in the matchmaking window (for the searching view).
  int get searchSecondsRemaining {
    final remaining = _searchDurationMs -
        (DateTime.now().millisecondsSinceEpoch - _searchStartMs);
    return remaining <= 0 ? 0 : (remaining / 1000).ceil();
  }

  int get earnedCoins => _earnedCoins;
  int get earnedGems => _earnedGems;

  String get revealMessage {
    if (_forfeitWin) return '🏆 $opponentName forfeited — you win!';
    if (playerTimedOut) return '⏰ You ran out of time!';
    if (opponentTimedOut) return '⌛ $opponentName ran out of time!';
    if (isPlayerCorrect && isOpponentCorrect) {
      // Who was faster? That decides who "took" the round on points.
      final mine = _lastRoundPlayer.total;
      final theirs = _lastRoundOpponent.total;
      if (mine > theirs) return '🔥 You took this round!';
      if (theirs > mine) return '💥 $opponentName took this round!';
      return '⚡ Both got it right!';
    }
    if (isPlayerCorrect) return '🔥 You took this round!';
    if (isOpponentCorrect) return '🤖 $opponentName took this round!';
    return '😅 Nobody got it!';
  }

  bool get isPlayerCorrect =>
      _playerSelected != null && _playerSelected == currentQuestion?.correctIndex;

  bool get isOpponentCorrect =>
      opponentSelected != null && opponentSelected == currentQuestion?.correctIndex;

  /// Language of the questions, independent of the app language.
  String? _displayLanguage;
  String get displayLanguage => _displayLanguage ?? S.code;

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

  int get battleQuestionCount => _userProvider.config.battleQuestionCount;
  int get battleBasePoints => _userProvider.config.battleBasePoints;
  int get battleSpeedBonus => _userProvider.config.battleSpeedBonus;
  int get battleFirstBonus => _userProvider.config.battleFirstBonus;
  int get battleStreakBonus => _userProvider.config.battleStreakBonus;
  int get battleMaxStreakBonus => _userProvider.config.battleMaxStreakBonus;

  /// Total matchmaking window in whole seconds (for the searching progress bar).
  int get searchSecondsTotal => (_searchDurationMs / 1000).ceil();

  // ------------------------------------------------------------ controls --

  Future<void> startBattle(BattleDifficulty difficulty) async {
    _disposeTimers();
    _cancelPendingRevengeChallenge();
    await _roomSub?.cancel();
    _roomSub = null;

    final user = _userProvider.user;
    _userId = user.userId;
    _liveCapable = !user.isGuest && !_userId.startsWith('local_');

    _difficulty = difficulty;
    _phase = BattlePhase.searching;
    _forfeitWin = false;
    SoundService.instance.loop('battle_search');
    _emptyBank = false;
    _opponent = null;
    _isBotMatch = true;
    // Save opponent info for revenge match before clearing
    _lastOpponent = _opponent;
    _room = null;
    _roomId = null;
    _matchId = null;
    _sawRoom = false;
    _attachedWritten = false;
    _roomMissingSinceMs = 0;
    _opponentIsKnown = false;
    _matchmakingError = null;
    _startError = null;

    _questions = [];
    _currentIndex = 0;

    _playerScore = 0;
    _playerCorrect = 0;
    _playerStreak = 0;
    _playerSelected = null;
    _playerAnswered = false;
    _playerTimedOut = false;
    _lastRoundPlayer = BattleRoundPoints.zero;
    _playerTotalMs = 0;

    _opponentScore = 0;
    _opponentCorrect = 0;
    _opponentStreak = 0;
    _opponentSelected = null;
    _opponentAnswered = false;
    _lastRoundOpponent = BattleRoundPoints.zero;
    _botTotalMs = 0;

    _earnedCoins = 0;
    _earnedGems = 0;

    _searchStartMs = DateTime.now().millisecondsSinceEpoch;
    _searchDurationMs = _liveCapable ? _searchSeconds * 1000 : 3000;

    if (_liveCapable) {
      await _roomService.joinQueue(
        uid: user.userId,
        name: user.username.isEmpty ? user.fullName : user.username,
        avatar: user.effectiveAvatar,
        difficulty: _difficulty.name,
      );
    }

    notifyListeners();
    _tickTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _tick(),
    );
    if (_liveCapable) {
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => _pollMatchmaking(),
      );
    }
  }

  Future<void> rematch() => startBattle(_difficulty);

  /// Start a revenge match against the same opponent from the last battle.
  /// - Bot match: instantly starts with same difficulty
  /// - Real player: sends a challenge and waits for acceptance
  /// Returns true if match started (bot) or challenge sent (live).
  Future<bool> rematchSameOpponent() async {
    final target = _lastOpponent;
    if (target == null) return false;

    // Store opponent before reset so we can use it after
    final savedOpponent = target;

    // Reset the battle state
    resetBattle();

    if (savedOpponent.isBot) {
      // Bot match: just start a new battle with same difficulty
      await startBattle(_difficulty);
      return true;
    }

    // Real player: send a challenge
    final uid = savedOpponent.uid;
    if (uid == null || uid.isEmpty) {
      // No uid available — fall back to random match
      await startBattle(_difficulty);
      return true;
    }

    final user = _userProvider.user;
    final challengeId = await _challengeService.sendChallenge(
      fromUid: user.userId,
      fromName: user.username.isEmpty ? user.fullName : user.username,
      fromAvatar: user.effectiveAvatar,
      fromAvatarUrl: user.avatarUrl,
      fromLevel: user.level,
      targetUid: uid,
      targetName: savedOpponent.name,
      targetAvatar: savedOpponent.avatar,
      difficulty: _difficulty.name,
    );

    if (challengeId != null) {
      _revengeChallengeId = challengeId;
      _phase = BattlePhase.searching; // show waiting state
      notifyListeners();
      
      // Watch for challenge acceptance
      _watchRevengeChallenge(challengeId, savedOpponent);
      return true;
    }
    return false;
  }
  
  /// Watch a revenge challenge and start the battle when accepted.
  void _watchRevengeChallenge(String challengeId, BattleOpponent opponent) {
    _stopRevengeChallengeWatcher();
    _revengeChallengeSub =
        _challengeService.watchChallengeStatus(challengeId).listen((challenge) {
      // A listener can deliver one final event while it is being cancelled.
      // Ignore anything that no longer belongs to the active challenge.
      if (_revengeChallengeId != challengeId || challenge == null) return;

      if (challenge.isAccepted) {
        // Challenge accepted! Start the battle with this opponent.
        _revengeChallengeId = null;
        _stopRevengeChallengeWatcher();
        unawaited(startBattleWithOpponent(
          opponentUid: opponent.uid!,
          opponentName: opponent.name,
          opponentAvatar: opponent.avatar,
          difficulty: _difficulty,
          challengeId: challengeId,
        ));
      } else if (challenge.isRejected ||
          challenge.isExpired ||
          challenge.isCancelled) {
        // Challenge was rejected/expired/cancelled — go back to setup.
        _revengeChallengeId = null;
        _stopRevengeChallengeWatcher();
        _phase = BattlePhase.setup;
        notifyListeners();
      }
    });
  }
  
  /// Starts a live match against a *known* opponent — the shared entry point
  /// for "challenge accepted" and "revenge match" (R10).
  ///
  /// Unlike [startBattle] this never queues for a random player and never
  /// substitutes a bot: the caller already knows who the opponent is. It
  /// creates (or joins) the deterministic room for the pair, publishes the
  /// questions when this client owns the room, and starts the VS intro.
  ///
  /// Returns true when the match was established. On any failure the caller
  /// gets `false`, the room/queue writes are undone as far as possible and
  /// [startError] explains why — the caller then restores its presence state.
  Future<bool> startBattleWithOpponent({
    required String opponentUid,
    required String opponentName,
    required String opponentAvatar,
    BattleDifficulty? difficulty,
    String? challengeId,
  }) async {
    if (opponentUid.isEmpty) return false;
    if (opponentUid == _userProvider.user.userId) return false;

    _disposeTimers();
    await _roomSub?.cancel();
    _roomSub = null;
    _stopRevengeChallengeWatcher();

    _room = null;
    _sawRoom = false;
    _attachedWritten = false;
    _roomMissingSinceMs = 0;
    _startError = null;
    _matchmakingError = null;
    _forfeitWin = false;
    _emptyBank = false;

    final user = _userProvider.user;
    _userId = user.userId;
    _liveCapable = !user.isGuest && !_userId.startsWith('local_');
    if (!_liveCapable) {
      // Guests are not allowed into the live 1v1 pipeline (server rules and
      // the leaderboard both need a real account).
      _startError = S.battleGuestRestricted;
      notifyListeners();
      return false;
    }

    _difficulty = difficulty ?? _difficulty;
    _opponentIsKnown = true;
    _isBotMatch = false;
    _opponent = BattleOpponent(
      name: opponentName,
      avatar: opponentAvatar,
      isBot: false,
      uid: opponentUid,
    );
    _lastOpponent = _opponent;

    _roomId = BattleRoomService.roomIdFor(_userId, opponentUid);
    _side = _userId.compareTo(opponentUid) < 0 ? 'a' : 'b';
    _matchId = _newMatchId();

    // Fresh scoreboard for the new session (a rematch reuses the room id, so
    // every per-match value has to be reset here).
    _resetScoreboardForNewMatch();
    _searchStartMs = DateTime.now().millisecondsSinceEpoch;
    _searchDurationMs = 0;

    _phase = BattlePhase.found;
    SoundService.instance.stop('battle_search');
    SoundService.instance.play('battle_found');
    SoundService.instance.play('battle_vs');
    Haptics.medium();
    notifyListeners();

    _ensureTickTimer();
    _roomSub = _roomService.watchRoom(_roomId!).listen(_onRoomUpdate);

    if (_side != 'a') {
      // The lexicographically smaller uid owns the room; this client just
      // waits for it to appear and reads the questions from it.
      return true;
    }

    // Creator: generate the shared question set, then publish the room in one
    // atomic claim.
    final questions = await _questionGenerator
        .generateBattleQuestions(count: battleQuestionCount);
    if (questions.isEmpty) {
      await _abortLiveStart(S.battleNoQuestions);
      return false;
    }
    // The player may have quit (or a newer match may have started) while the
    // questions were being generated.
    if (_roomId == null || _phase != BattlePhase.found) return false;

    _questions = questions;
    _countdownUntilMs = DateTime.now().millisecondsSinceEpoch + 8000;

    final outcome = await _roomService.claimOpponent(
      myUid: _userId,
      opponentUid: opponentUid,
      difficulty: _difficulty.name,
      matchId: _matchId!,
      me: BattleRoomPlayerInfo(
        uid: _userId,
        name: user.username.isEmpty ? user.fullName : user.username,
        avatar: user.effectiveAvatar,
      ),
      opponent: BattleRoomPlayerInfo(
        uid: opponentUid,
        name: opponentName,
        avatar: opponentAvatar,
      ),
      questions: questions,
      countdownUntilMs: _countdownUntilMs,
    );

    switch (outcome.status) {
      case QueueClaimStatus.created:
        break;
      case QueueClaimStatus.alreadyExists:
        // The opponent got there first — adopt its match id and questions so
        // both clients settle the same session.
        if (outcome.matchId.isNotEmpty) _matchId = outcome.matchId;
        final room = await _roomService.readRoom(outcome.roomId);
        if (room != null) {
          _room = room;
          _sawRoom = true;
          if (room.hasQuestions) _questions = room.questions;
          if (room.countdownUntilMs > 0) {
            _countdownUntilMs = room.countdownUntilMs;
          }
        }
        break;
      case QueueClaimStatus.opponentGone:
        await _abortLiveStart(S.battleOpponentLeft);
        return false;
      case QueueClaimStatus.failed:
        await _abortLiveStart(S.battleStartFailed);
        return false;
    }

    await _writeMyPlayer({'last_seen': DateTime.now().millisecondsSinceEpoch});
    _writeAttachedOnce();
    notifyListeners();
    return true;
  }

  /// Cancels a match that could not be established: no room, no queue entry,
  /// no watcher, back to the setup screen with a reason.
  Future<void> _abortLiveStart(String message) async {
    if (_roomId != null && _side == 'a' && _sawRoom) {
      // We created a room the opponent may never have seen — mark it dead so a
      // stale document can't be picked up as a live match later.
      await _roomService.abandonRoom(_roomId!, _side);
    }
    await _roomSub?.cancel();
    _roomSub = null;
    if (_liveCapable) await _roomService.leaveQueue(_userId);
    _disposeTimers();
    _room = null;
    _roomId = null;
    _matchId = null;
    _sawRoom = false;
    _attachedWritten = false;
    _opponent = null;
    _isBotMatch = true;
    _opponentIsKnown = false;
    _questions = [];
    _currentIndex = 0;
    _startError = message;
    _phase = BattlePhase.setup;
    SoundService.instance.stop('battle_search');
    notifyListeners();
  }

  /// Unique id for one match. The room id is derived from the two uids (so a
  /// rematch reuses it) — this id is what tells two consecutive matches apart
  /// for scoring, receipts and the local reward guard.
  static String _newMatchId() =>
      'm_${DateTime.now().microsecondsSinceEpoch}_${++_matchCounter}';

  /// The composite key the local reward guard remembers: one award per match,
  /// never per room (R11).
  String get _processedMatchKey {
    final room = _roomId;
    final match = _matchId;
    if (room == null) return '';
    return match == null || match.isEmpty ? room : '$room#$match';
  }

  void _resetScoreboardForNewMatch() {
    _currentIndex = 0;
    _questions = [];
    _playerScore = 0;
    _playerCorrect = 0;
    _playerStreak = 0;
    _playerSelected = null;
    _playerAnswered = false;
    _playerTimedOut = false;
    _lastRoundPlayer = BattleRoundPoints.zero;
    _playerTotalMs = 0;
    _opponentScore = 0;
    _opponentCorrect = 0;
    _opponentStreak = 0;
    _opponentSelected = null;
    _opponentAnswered = false;
    _lastRoundOpponent = BattleRoundPoints.zero;
    _botTotalMs = 0;
    _earnedCoins = 0;
    _earnedGems = 0;
    _revealUntilMs = 0;
  }

  void _ensureTickTimer() {
    if (_tickTimer?.isActive ?? false) return;
    _tickTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _tick(),
    );
  }

  /// Cancel a pending revenge challenge.
  Future<void> cancelRevengeChallenge() async {
    final challengeId = _revengeChallengeId;
    if (challengeId == null) return;

    _revengeChallengeId = null;
    _stopRevengeChallengeWatcher();
    await _challengeService.cancelChallenge(challengeId);
    _phase = BattlePhase.setup;
    notifyListeners();
  }

  void _stopRevengeChallengeWatcher() {
    final subscription = _revengeChallengeSub;
    _revengeChallengeSub = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  void _cancelPendingRevengeChallenge() {
    final challengeId = _revengeChallengeId;
    _revengeChallengeId = null;
    _stopRevengeChallengeWatcher();
    if (challengeId != null) {
      unawaited(_challengeService.cancelChallenge(challengeId));
    }
  }

  void _stopRoomWatcher() {
    final subscription = _roomSub;
    _roomSub = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  /// Player intentionally left mid-match → opponent wins instantly.
  /// Writes 'abandoned: true' + 'phase: finished' to Firestore so the
  /// opponent's client sees the room update and transitions to _ResultView
  /// with isForfeit = true within one stream tick (~1 s).
  void forfeitAndLeave() {
    _disposeTimers();
    if (isLive && _roomId != null) {
      final roomId = _roomId!;
      _roomService.finishRoom(roomId, _side == 'a' ? 'b' : 'a',
          matchId: _matchId);
      // Top-level abandoned flag: the opponent's client reads the document
      // fields, not the nested state map.
      _roomService.abandonRoom(roomId, _side);
      _roomService.leaveQueue(_userId);
    }
    // Do not keep receiving live-room updates after the screen that owned the
    // match has been popped; a late update must not revive its result state.
    _stopRoomWatcher();
    SoundService.instance.stop('battle_search');
    SoundService.instance.play('ui_back');
    _phase = BattlePhase.setup;
    notifyListeners();
  }

  void cancelSearch() {
    if (_phase != BattlePhase.searching) return;
    if (_liveCapable) _roomService.leaveQueue(_userId);
    _cancelPendingRevengeChallenge();
    _disposeTimers();
    SoundService.instance.stop('battle_search');
    SoundService.instance.play('ui_back');
    _phase = BattlePhase.setup;
    notifyListeners();
  }

  /// Quit the current match from ANY phase — properly cleans up everything.
  /// - Searching: cancels matchmaking
  /// - Bot match (question/reveal/countdown/found): stops timers, resets to setup
  /// - Live match: forfeits and notifies opponent
  void quitMatch() {
    if (_phase == BattlePhase.setup || _phase == BattlePhase.finished) {
      // Already done — nothing to quit
      return;
    }

    if (_phase == BattlePhase.searching) {
      cancelSearch();
      return;
    }

    // Live match — forfeit properly
    if (isLive) {
      forfeitAndLeave();
      return;
    }

    // Bot match in progress — stop everything and reset
    _disposeTimers();
    SoundService.instance.stop('battle_search');
    SoundService.instance.play('ui_back');
    _phase = BattlePhase.setup;
    _opponent = null;
    _questions = [];
    _currentIndex = 0;
    _playerScore = 0;
    _playerCorrect = 0;
    _playerStreak = 0;
    _playerSelected = null;
    _playerAnswered = false;
    _playerTimedOut = false;
    _opponentScore = 0;
    _opponentCorrect = 0;
    _opponentStreak = 0;
    _opponentSelected = null;
    _opponentAnswered = false;
    _lastRoundPlayer = BattleRoundPoints.zero;
    _lastRoundOpponent = BattleRoundPoints.zero;
    notifyListeners();
  }

  int get _searchSeconds =>
      min(_userProvider.config.battleSearchSeconds, 10);

  // -------------------------------------------------------- matchmaking --

  Future<void> _pollMatchmaking() async {
    if (_phase != BattlePhase.searching || !_liveCapable) return;

    final result = await _roomService.findOpponent(
      myUid: _userId,
      difficulty: _difficulty.name,
    );
    if (_phase != BattlePhase.searching) return;

    // A denied query or a missing composite index must never be reported as
    // "nobody is online": stop the search and say what actually happened
    // instead of quietly serving a bot match (R17).
    if (result.isConfigurationError) {
      _pollTimer?.cancel();
      _matchmakingError = S.battleMatchmakingBroken;
      await _abandonLiveSearch();
      notifyListeners();
      return;
    }
    if (!result.hasOpponent) return; // empty or a transient failure — keep polling

    final found = result.entry!;
    _roomId = BattleRoomService.roomIdFor(_userId, found.uid);
    _side = _userId.compareTo(found.uid) < 0 ? 'a' : 'b';
    _matchId = _newMatchId();
    _sawRoom = false;
    _attachedWritten = false;
    _opponentIsKnown = false;

    _opponent = BattleOpponent(
      name: found.name,
      avatar: found.avatar,
      isBot: false,
      uid: found.uid,
    );
    _phase = BattlePhase.found;
    _pollTimer?.cancel();
    SoundService.instance.stop('battle_search');
    SoundService.instance.play('battle_found');
    SoundService.instance.play('battle_vs');
    Haptics.medium();
    notifyListeners();

    _roomSub = _roomService.watchRoom(_roomId!).listen(_onRoomUpdate);

    if (_side != 'a') {
      // The creator publishes the room; this client waits for it.
      return;
    }

    // Creator: generate the shared question set, then claim the opponent and
    // publish the room atomically.
    final questions = await _questionGenerator
        .generateBattleQuestions(count: battleQuestionCount);
    if (questions.isEmpty || _phase != BattlePhase.found) {
      await _abandonLiveMatch();
      return;
    }
    _questions = questions;
    _countdownUntilMs = DateTime.now().millisecondsSinceEpoch + 8000;

    final outcome = await _roomService.claimOpponent(
      myUid: _userId,
      opponentUid: found.uid,
      difficulty: _difficulty.name,
      matchId: _matchId!,
      me: BattleRoomPlayerInfo(
        uid: _userId,
        name: _userProvider.user.username.isEmpty
            ? _userProvider.user.fullName
            : _userProvider.user.username,
        avatar: _userProvider.user.effectiveAvatar,
      ),
      opponent: BattleRoomPlayerInfo(
        uid: found.uid,
        name: found.name,
        avatar: found.avatar,
      ),
      questions: questions,
      countdownUntilMs: _countdownUntilMs,
    );
    if (_phase != BattlePhase.found) return;

    switch (outcome.status) {
      case QueueClaimStatus.created:
        break;
      case QueueClaimStatus.alreadyExists:
        if (outcome.matchId.isNotEmpty) _matchId = outcome.matchId;
        final room = await _roomService.readRoom(outcome.roomId);
        if (room != null) {
          _room = room;
          _sawRoom = true;
          if (room.hasQuestions) _questions = room.questions;
          if (room.countdownUntilMs > 0) {
            _countdownUntilMs = room.countdownUntilMs;
          }
        }
        break;
      case QueueClaimStatus.opponentGone:
      case QueueClaimStatus.failed:
        await _abandonLiveMatch();
        return;
    }

    await _writeMyPlayer({'last_seen': DateTime.now().millisecondsSinceEpoch});
    _writeAttachedOnce();
    notifyListeners();
  }

  /// The search could not continue (configuration failure) — unwind the queue,
  /// keep the reason in [matchmakingError] and return to setup.
  Future<void> _abandonLiveSearch() async {
    await _roomSub?.cancel();
    _roomSub = null;
    if (_liveCapable) await _roomService.leaveQueue(_userId);
    _phase = BattlePhase.setup;
    _opponent = null;
    _isBotMatch = true;
    _roomId = null;
    _matchId = null;
    _sawRoom = false;
    SoundService.instance.stop('battle_search');
    _disposeTimers();
  }

  Future<void> _abandonLiveMatch() async {
    _pollTimer?.cancel();
    await _roomSub?.cancel();
    _roomSub = null;
    if (_liveCapable) await _roomService.leaveQueue(_userId);
    // Top-level abandoned flag + status: the opponent's client reads those,
    // not the nested state map.
    if (_roomId != null) {
      await _roomService.abandonRoom(_roomId!, _side);
    }
    _phase = BattlePhase.setup;
    _room = null;
    _roomId = null;
    _matchId = null;
    _sawRoom = false;
    _opponent = null;
    _isBotMatch = true;
    _questions = [];
    notifyListeners();
  }

  void _onRoomUpdate(BattleRoomData? room) {
    if (_phase == BattlePhase.setup) return;
    if (room == null) {
      if (_phase == BattlePhase.finished) return;
      // No document yet means one of two very different things (R11):
      //   * we have never seen the room → creation is still in flight (the
      //     opponent's client may not even have written it). That is a race,
      //     not a departure: wait for the grace timer instead of declaring a
      //     free forfeit win.
      //   * we had the room and it is gone → a real disappearance, and only
      //     then is a forfeit the right answer.
      if (!_sawRoom || !(isLive)) return;
      final started = (_room?.hasStarted ?? false) ||
          _phase == BattlePhase.question ||
          _phase == BattlePhase.reveal;
      if (started) {
        _forfeitWin = true;
        _finishBattle();
      } else {
        unawaited(_abandonLiveMatch());
      }
      return;
    }
    if (!_sawRoom) {
      _sawRoom = true;
      // The room carries the match id the creator minted — adopt it so both
      // clients guard rewards for the same session.
      if (_matchId == null || _matchId!.isEmpty) {
        _matchId = room.matchId.isEmpty ? _matchId : room.matchId;
      }
      _writeAttachedOnce();
    }
    _roomMissingSinceMs = 0;
    if (room.matchId.isNotEmpty && room.matchId != _matchId) {
      _matchId = room.matchId;
    }
    _room = room;

    if (_questions.isEmpty && room.hasQuestions) {
      _questions = room.questions;
    }

    // Opponent abandoned mid-match → instant forfeit win for us.
    if (room.isAbandoned && room.abandonedBy != null && room.abandonedBy != _side) {
      if (_phase != BattlePhase.finished) {
        _forfeitWin = true;
        _finishBattle();
      }
      return;
    }

    if (room.isFinished) {
      if (_phase != BattlePhase.finished) _finishBattle();
      return;
    }

    // Creator's schedule arrives with the room.
    if (room.countdownUntilMs > 0) {
      _countdownUntilMs = room.countdownUntilMs;
    }

    // Both answered → local reveal (the first client to see it writes the
    // shared reveal_until so both clients advance on the same clock).
    if (_phase == BattlePhase.question &&
        room.hasBothAnswered(_currentIndex) &&
        _revealUntilMs == 0) {
      _beginReveal(DateTime.now().millisecondsSinceEpoch);
    }

    // Re-anchor the reveal clock to the room value: both clients then leave
    // the reveal window and start the next question at the same instant.
    if (_phase == BattlePhase.reveal && room.revealUntilMs > 0) {
      _revealUntilMs = room.revealUntilMs;
    }

    // Both ready → advance to the next question.
    if (_phase == BattlePhase.reveal &&
        room.bothReadyFor(_currentIndex + 1) &&
        DateTime.now().millisecondsSinceEpoch >= _revealUntilMs) {
      _goToNextQuestionLive();
    }

    notifyListeners();
  }

  // ---------------------------------------------------------------- tick --

  void _tick() {
    if (_phase == BattlePhase.setup || _phase == BattlePhase.finished) return;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Heartbeat while live (every phase, not only questions — otherwise a
    // fresh match could look "stale" the moment question 0 starts).
    if (isLive && now - _lastHeartbeatMs > 5000) {
      _lastHeartbeatMs = now;
      _writeMyPlayer({'last_seen': now});
    }

    switch (_phase) {
      case BattlePhase.searching:
        if (now - _searchStartMs >= _searchDurationMs) {
          _pollTimer?.cancel();
          _beginBotMatch();
        } else {
          notifyListeners();
        }
      case BattlePhase.found:
        _tickFound(now);
      case BattlePhase.countdown:
        _tickCountdown(now);
      case BattlePhase.question:
        _tickQuestion(now);
      case BattlePhase.reveal:
        _tickReveal(now);
      case BattlePhase.setup:
      case BattlePhase.finished:
        break;
    }
  }

  void _tickFound(int now) {
    // Waiting for the creator's room document (questions + countdown). Nothing
    // can be shown until it arrives — but never wait forever: a challenge
    // opponent has to be reported as gone, and a random queue match may still
    // fall back to the bot (R10/R11).
    if (isLive && (_room == null || !_room!.hasQuestions)) {
      if (_roomMissingSinceMs == 0) _roomMissingSinceMs = now;
      if (now - _roomMissingSinceMs > 15000) {
        if (_opponentIsKnown) {
          unawaited(_abortLiveStart(S.battleOpponentLeft));
        } else {
          unawaited(_beginBotMatch());
        }
      }
      return;
    }
    // VS intro plays until 2.8 s before countdown starts.
    if (_countdownUntilMs <= 0) return;
    if (now >= _countdownUntilMs - 2800) {
      _phase = BattlePhase.countdown;
      SoundService.instance.play('battle_count');
      notifyListeners();
    }
  }

  void _tickCountdown(int now) {
    if (isLive && _room == null) {
      final waited = now - _searchStartMs;
      if (_opponentIsKnown) {
        // A challenge/rematch opponent is not interchangeable with a bot: if
        // the room never appears, fail the start honestly (R10).
        if (waited > 15000) {
          unawaited(_abortLiveStart(S.battleOpponentLeft));
        }
        return;
      }
      // Room never appeared — don't hang the player, run the bot instead.
      if (waited > 12000) _beginBotMatch();
      return;
    }
    final remainingMs = _countdownUntilMs - now;
    final seconds = remainingMs <= 0 ? 0 : (remainingMs / 1000).ceil();
    if (seconds <= 3 && seconds != _countdownValue) {
      _countdownValue = seconds.clamp(1, 3);
      SoundService.instance.play('battle_count');
      Haptics.tap();
      notifyListeners();
    }
    if (remainingMs <= 0) {
      _startQuestion(now);
    }
  }

  // --------------------------------------------------------- bot fallback --

  Future<void> _beginBotMatch() async {
    _pollTimer?.cancel();
    await _roomSub?.cancel();
    _roomSub = null;
    _room = null;
    _roomId = null;

    if (isLive) {
      _roomService.leaveQueue(_userId);
    }
    _opponent = BattleOpponent(
      name: _botName,
      avatar: _botAvatar,
      isBot: true,
    );
    _isBotMatch = true;

    _questions = await BattleQuestionGenerator()
        .generateBattleQuestions(count: battleQuestionCount);
    if (_questions.isEmpty) {
      _emptyBank = true;
      _phase = BattlePhase.setup;
      notifyListeners();
      return;
    }

    _countdownUntilMs = DateTime.now().millisecondsSinceEpoch + 5600;
    _phase = BattlePhase.found;
    SoundService.instance.stop('battle_search');
    SoundService.instance.play('battle_found');
    SoundService.instance.play('battle_vs');
    Haptics.medium();
    notifyListeners();
  }

  // Random bot avatars and names for variety
  static const List<String> _botAvatars = [
    'assets/images/avatars/male_avatar_1.png',
    'assets/images/avatars/male_avatar_2.png',
    'assets/images/avatars/male_avatar_3.png',
    'assets/images/avatars/male_avatar_4.png',
    'assets/images/avatars/female_avatar_1.png',
    'assets/images/avatars/female_avatar_2.png',
    'assets/images/avatars/female_avatar_3.png',
    'assets/images/avatars/female_avatar_4.png',
    'assets/images/avatars/golden_knight_avatar.png',
    'assets/images/avatars/vip_avatar.png',
  ];

  static const List<String> _botNames = [
    'QuizMaster', 'BrainStorm', 'QuickWit', 'SharpMind',
    'SwiftThinker', 'CleverFox', 'MindBlitz', 'RapidFire',
    'KnowledgeKing', 'WisdomWarrior', 'PuzzlePro', 'TriviaAce',
    'BrainWave', 'ThinkFast', 'QuizNinja', 'SmartCookie',
  ];

  String get _botAvatar => _botAvatars[_rng.nextInt(_botAvatars.length)];
  String get _botName => _botNames[_rng.nextInt(_botNames.length)];

  // ----------------------------------------------------------- questions --

  void _startQuestion(int now) {
    final question = currentQuestion;
    if (question == null) {
      _finishBattle();
      return;
    }

    _questionDurationSec = question.timeLimitSec > 0
        ? question.timeLimitSec
        : _userProvider.config.secondsPerQuestion;
    _questionDeadlineMs = now + _questionDurationSec * 1000;
    _secondsRemaining = _questionDurationSec;

    _playerSelected = null;
    _playerAnswered = false;
    _playerTimedOut = false;
    _revealUntilMs = 0;

    _opponentSelected = null;
    _opponentAnswered = false;

    _phase = BattlePhase.question;
    if (isLive && _roomId != null) {
      // First real question of the match — the room is now provably started
      // (a disappearing document from here on is a forfeit, not a race).
      unawaited(_roomService.markActive(_roomId!));
    }
    SoundService.instance.play('battle_go');
    Haptics.tap();
    notifyListeners();

    if (!isLive) {
      _scheduleBotAnswer(now);
    }
  }

  void _scheduleBotAnswer(int questionStartMs) {
    final (minT, maxT) = _botDelayRange;
    final delay = minT + _rng.nextDouble() * (maxT - minT);
    _botAnswerAtMs = questionStartMs + (delay * 1000).round();
  }

  void _tickQuestion(int now) {
    // Forfeit watch for live matches.
    if (isLive) {
      final opponentPlayer = _room?.opponentOf(_side);
      if (opponentPlayer != null &&
          now - opponentPlayer.lastSeenMs > 20000 &&
          !opponentAnswered) {
        _forfeitWin = true;
        _roomService.finishRoom(_roomId!, _side);
        _finishBattle();
        return;
      }
    }

    // Bot locks in its answer at its "think" deadline.
    if (!isLive && !_opponentAnswered && now >= _botAnswerAtMs) {
      _applyBotAnswer(now);
    }

    final remainingMs = _questionDeadlineMs - now;
    _secondsRemaining = remainingMs <= 0 ? 0 : (remainingMs / 1000).ceil();
    if (remainingMs <= 0) {
      if (!_playerAnswered) {
        _handlePlayerTimeout();
      } else if (!opponentAnswered) {
        // The opponent's own client times them out; give a grace period
        // before declaring a forfeit.
        if (now - _questionDeadlineMs > 8000) {
          _forfeitWin = true;
          if (isLive) _roomService.finishRoom(_roomId!, _side);
          _finishBattle();
          return;
        }
      }
    }

    // Live: both answered → reveal.
    if (isLive && _playerAnswered && opponentAnswered && _revealUntilMs == 0) {
      _beginReveal(now);
    }

    notifyListeners();
  }

  void _applyBotAnswer(int now) {
    final question = currentQuestion;
    if (question == null) return;

    if (_rng.nextDouble() < _botAccuracy) {
      _opponentSelected = question.correctIndex;
    } else {
      final wrong = [
        for (var i = 0; i < question.options.length; i++) i
      ]..remove(question.correctIndex);
      _opponentSelected = wrong.isEmpty
          ? question.correctIndex
          : wrong[_rng.nextInt(wrong.length)];
    }
    _opponentAnswered = true;

    // The bot's think time feeds the same time-scaled speed formula, so the
    // scoreboard stays symmetric between bot and live matches.
    final durationMs = _questionDurationSec * 1000;
    final remainingMs = (_questionDeadlineMs - now).clamp(0, durationMs);
    final msTaken = durationMs - remainingMs;
    _botTotalMs += msTaken;

    // Bot answered first only if player hasn't answered yet
    final botAnsweredFirst = !_playerAnswered;
    if (_opponentSelected == question.correctIndex) {
      _lastRoundOpponent = _computePoints(
        correct: true,
        answeredFirst: botAnsweredFirst,
        streak: _opponentStreak,
        remainingMs: remainingMs,
      ).withMs(msTaken);
      _opponentStreak += 1;
      _opponentCorrect += 1;
      _opponentScore += _lastRoundOpponent.total;
    } else {
      _lastRoundOpponent = BattleRoundPoints.zero.withMs(msTaken);
      _opponentStreak = 0;
    }
    notifyListeners();
    // If player already answered, trigger reveal immediately.
    _maybeReveal(now);
  }

  // ------------------------------------------------------------ answers --

  void answerQuestion(int index) {
    if (_phase != BattlePhase.question || _playerAnswered) return;
    _playerSelected = index;
    _playerAnswered = true;
    _playerTimedOut = false;

    final now = DateTime.now().millisecondsSinceEpoch;
    final question = currentQuestion;
    final right = question != null && index == question.correctIndex;

    final durationMs = _questionDurationSec * 1000;
    final remainingMs = (_questionDeadlineMs - now).clamp(0, durationMs);
    final msTaken = durationMs - remainingMs;
    _playerTotalMs += msTaken;

    // Player answered first if opponent hasn't answered yet
    final playerAnsweredFirst = !opponentAnswered;
    if (right) {
      _lastRoundPlayer = _computePoints(
        correct: true,
        answeredFirst: playerAnsweredFirst,
        streak: _playerStreak,
        remainingMs: remainingMs,
      ).withMs(msTaken);
      _playerStreak += 1;
      _playerCorrect += 1;
      _playerScore += _lastRoundPlayer.total;
      SoundService.instance.play('quiz_correct');
      Haptics.light();
    } else {
      _lastRoundPlayer = BattleRoundPoints.zero.withMs(msTaken);
      _playerStreak = 0;
      SoundService.instance.play('quiz_wrong');
      Haptics.error();
    }

    // Bot match: once the player has locked in, the bot resolves within a
    // heartbeat instead of finishing its full "think" delay — the player
    // should never stare at "thinking…" for six seconds after answering.
    _compressBotAnswer(now);

    if (isLive) {
      _writeMyAnswer(selected: index, right: right, msTaken: msTaken);
    }
    notifyListeners();
    _maybeReveal(now);
  }

  void _handlePlayerTimeout() {
    if (_phase != BattlePhase.question || _playerAnswered) return;
    _playerAnswered = true;
    _playerTimedOut = true;
    _playerSelected = null;

    final durationMs = _questionDurationSec * 1000;
    _lastRoundPlayer = BattleRoundPoints.zero.withMs(durationMs);
    _playerTotalMs += durationMs;
    SoundService.instance.play('quiz_timeout');
    Haptics.error();

    final now = DateTime.now().millisecondsSinceEpoch;
    _compressBotAnswer(now);

    if (isLive) {
      _writeMyAnswer(selected: -1, right: false, msTaken: durationMs);
    }
    notifyListeners();
    _maybeReveal(now);
  }

  /// Bot matches only: pull the bot's pending answer closer so the round
  /// resolves quickly once the player is done waiting.
  void _compressBotAnswer(int now) {
    if (isLive || _opponentAnswered) return;
    final maxWaitMs = 600 + _rng.nextInt(1200); // 0.6–1.8 s
    var compressedAt = now + maxWaitMs;
    // Never let the compressed answer drift past the question window.
    if (compressedAt > _questionDeadlineMs) compressedAt = _questionDeadlineMs;
    if (compressedAt < _botAnswerAtMs) {
      _botAnswerAtMs = compressedAt;
    }
  }

  void _maybeReveal(int now) {
    if (_phase != BattlePhase.question) return;
    if (!_playerAnswered || !opponentAnswered) return;
    if (_revealUntilMs != 0) return;
    _beginReveal(now);
  }

  /// Transitions question → reveal and publishes the shared reveal clock.
  void _beginReveal(int now) {
    if (_phase != BattlePhase.question) return;

    // Opponent's round points: bot mode computed them when the bot answered;
    // live mode reads them from the room's answer record.
    if (isLive) {
      final answer = _room?.opponentOf(_side)?.answerFor(_currentIndex);
      if (answer != null) {
        _lastRoundOpponent = BattleRoundPoints(
          base: answer.points -
              answer.timeBonus -
              answer.firstBonus -
              answer.streakBonus,
          speedBonus: answer.timeBonus,
          firstBonus: answer.firstBonus,
          streakBonus: answer.streakBonus,
          msTaken: answer.msTaken,
        );
      }
    }

    _phase = BattlePhase.reveal;
    _revealUntilMs = now + 3200;
    notifyListeners();

    if (isLive) {
      _roomService.advanceState(_roomId!, {'reveal_until': _revealUntilMs});
    }
  }

  void _tickReveal(int now) {
    if (now < _revealUntilMs) return;
    // Guard: mark as advancing so repeated ticks don't call this twice.
    _revealUntilMs = now + 999999;
    if (isLive) {
      _goToNextQuestionLive();
    } else {
      _goToNextQuestion();
    }
  }

  /// Scoring: base=10, speed=up to +10 (with 20% reading grace),
  /// first=+2 before the opponent, streak=+2×streak (capped at 6).
  BattleRoundPoints _computePoints({
    required bool correct,
    required bool answeredFirst, // true = this side answered before the other
    required int streak,
    required int remainingMs, // ms left on the clock when this side answered
  }) {
    final cfg = _userProvider.config;
    final parts = BattleScoring.compute(
      correct: correct,
      remainingMs: remainingMs,
      questionDurationMs: _questionDurationSec * 1000,
      answeredBeforeOpponent: answeredFirst,
      streak: streak,
      basePoints: cfg.battleBasePoints,
      maxSpeedBonus: cfg.battleSpeedBonus,
      firstBonus: cfg.battleFirstBonus,
      streakBonusPerStreak: cfg.battleStreakBonus,
      maxStreakBonus: cfg.battleMaxStreakBonus,
      readingGraceMs: _readingGraceMs,
    );
    return BattleRoundPoints(
      base: parts.base,
      speedBonus: parts.speedBonus,
      firstBonus: parts.firstBonus,
      streakBonus: parts.streakBonus,
    );
  }

  // ------------------------------------------------------------- advance --

  void _goToNextQuestion() {
    if (_phase == BattlePhase.finished) return;
    if (_currentIndex < _questions.length - 1) {
      _currentIndex++;
      _startQuestion(DateTime.now().millisecondsSinceEpoch);
    } else {
      _finishBattle();
    }
  }

  void _goToNextQuestionLive() {
    _writeMyPlayer({'ready_for_next': _currentIndex + 1});
    final room = _room;
    if (room != null && room.bothReadyFor(_currentIndex + 1)) {
      final nextStart = _revealUntilMs + 300;
      if (_currentIndex < _questions.length - 1) {
        _currentIndex++;
        _startQuestion(
          nextStart > DateTime.now().millisecondsSinceEpoch
              ? nextStart
              : DateTime.now().millisecondsSinceEpoch,
        );
      } else {
        _finishBattle();
      }
    }
  }

  // -------------------------------------------------------------- finish --

  void _finishBattle() {
    _disposeTimers();
    _phase = BattlePhase.finished;
    SoundService.instance.stop('battle_search');
    if (isPlayerWin || isForfeit) {
      SoundService.instance.play('battle_win');
      Haptics.heavy();
    } else if (isDraw) {
      SoundService.instance.play('battle_lose');
      Haptics.medium();
    } else {
      SoundService.instance.play('battle_lose');
      Haptics.error();
    }

    if (isLive) {
      // A forfeit always means the remaining player wins, regardless of the
      // score at the moment the opponent left.
      final winner = (isPlayerWin || _forfeitWin)
          ? _side
          : isDraw
              ? 'draw'
              : (_side == 'a' ? 'b' : 'a');
      unawaited(_roomService.finishRoom(_roomId!, winner, matchId: _matchId));

      // Single-award guard: one award per *match*, not per room. The room id
      // is deterministic for a pair, so a rematch reuses it — keying on the
      // room alone silently suppressed every rematch reward (R11).
      final guardKey = _processedMatchKey;
      if (guardKey.isNotEmpty) {
        if (HiveService.isBattleRoomProcessed(guardKey)) {
          notifyListeners();
          return;
        }
        await HiveService.markBattleRoomProcessed(guardKey);
      }
    }

    // Performance-scaled rewards: correct answers always pay something, so
    // students walk away with progress even after a loss — the hook that
    // makes them queue up for "one more battle".
    if (isPlayerWin || isForfeit) {
      _earnedCoins = 40 + 2 * _playerCorrect;
      _earnedGems = 2;
    } else if (isDraw) {
      _earnedCoins = 15 + _playerCorrect;
      _earnedGems = 0;
    } else {
      _earnedCoins = 5 + _playerCorrect;
      _earnedGems = 0;
    }

    _userProvider.grantQuizRewards(
      coins: _earnedCoins,
      gems: _earnedGems,
      isDailyQuiz: false,
    );

    _userProvider.recordBattleResult(won: isPlayerWin);
    _userProvider.recordQuizResult(
      answered: _questions.length,
      correct: _playerCorrect,
      timeSeconds: (_questions.length * _questionDurationSec).toDouble(),
      isDaily: false,
    );

    if (_liveCapable) _roomService.leaveQueue(_userId);
    notifyListeners();
  }

  // -------------------------------------------------------- live writers --

  void _writeMyAnswer({
    required int selected,
    required bool right,
    required int msTaken,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final answer = BattleAnswer(
      selected: selected,
      correct: right,
      points: _lastRoundPlayer.total,
      timeBonus: _lastRoundPlayer.timeBonus,
      firstBonus: _lastRoundPlayer.firstBonus,
      streakBonus: _lastRoundPlayer.streakBonus,
      msTaken: msTaken,
      timedOut: selected < 0,
    );
    // The answer goes in as a nested map (`answers` → "<index>"), never as the
    // dotted `answers.0` field path that a merge write would turn into a
    // literal, unreadable field name (R11).
    final roomId = _roomId;
    if (roomId == null) return;
    unawaited(_roomService.writeMyAnswer(
      roomId: roomId,
      side: _side,
      questionIndex: _currentIndex,
      answer: answer,
      extraFields: {
        'last_seen': now,
        'score': _playerScore,
        'correct': _playerCorrect,
        'streak': _playerStreak,
      },
    ));
  }

  Future<void> _writeMyPlayer(Map<String, dynamic> fields) async {
    if (_roomId == null) return;
    await _roomService.updateMyPlayer(_roomId!, _side, fields);
  }

  /// Marks this client attached exactly once per match. Both flags set means
  /// the creator can move the room to `ready` (R11).
  void _writeAttachedOnce() {
    if (_attachedWritten || _roomId == null) return;
    _attachedWritten = true;
    unawaited(_roomService.attachPlayer(_roomId!, _side));
  }

  // ---------------------------------------------------------------- bot --

  double get _botAccuracy {
    switch (_difficulty) {
      case BattleDifficulty.easy:
        return 0.45;
      case BattleDifficulty.normal:
        return 0.62;
      case BattleDifficulty.hard:
        return 0.78;
    }
  }

  /// Bot delay ranges — human-like reading+thinking time.
  /// The bot now "reads" the question like a student would, preventing
  /// the old 26-point blowout when both got 4/5 correct.
  (double, double) get _botDelayRange {
    switch (_difficulty) {
      case BattleDifficulty.easy:
        return (5.0, 10.0);  // Was 4-8
      case BattleDifficulty.normal:
        return (4.0, 8.5);   // Was 2.5-6
      case BattleDifficulty.hard:
        return (3.0, 6.5);   // Was 1.5-4
    }
  }

  /// Reading grace: the first 20% of the question window pays the full speed
  /// bonus — nobody can read a question faster than that, so sub-grace answers
  /// (human or bot) are all treated as "instant".
  int get _readingGraceMs => (_questionDurationSec * 1000 * 0.20).round();

  // ----------------------------------------------------------------- misc --

  void _disposeTimers() {
    _tickTimer?.cancel();
    _tickTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    _disposeTimers();
    _stopRoomWatcher();
    _cancelPendingRevengeChallenge();
    if (_liveCapable) {
      _roomService.leaveQueue(_userId);
    }
    super.dispose();
  }


  /// Reset battle state — call when navigating away or starting fresh.
  /// Clears all scores, phase, questions, and timers.
  void resetBattle() {
    _disposeTimers();
    _stopRoomWatcher();
    _cancelPendingRevengeChallenge();

    _phase = BattlePhase.setup;
    _forfeitWin = false;
    _emptyBank = false;
    _opponent = null;
    _isBotMatch = true;
    _room = null;
    _roomId = null;
    _matchId = null;
    _sawRoom = false;
    _attachedWritten = false;
    _roomMissingSinceMs = 0;
    _opponentIsKnown = false;
    _matchmakingError = null;
    _startError = null;
    _side = 'a';

    _questions = [];
    _currentIndex = 0;

    _playerScore = 0;
    _playerCorrect = 0;
    _playerStreak = 0;
    _playerSelected = null;
    _playerAnswered = false;
    _playerTimedOut = false;
    _lastRoundPlayer = BattleRoundPoints.zero;
    _playerTotalMs = 0;

    _opponentScore = 0;
    _opponentCorrect = 0;
    _opponentStreak = 0;
    _opponentSelected = null;
    _opponentAnswered = false;
    _lastRoundOpponent = BattleRoundPoints.zero;
    _botTotalMs = 0;

    _earnedCoins = 0;
    _earnedGems = 0;

    _searchStartMs = 0;
    _searchDurationMs = 0;

    notifyListeners();
  }
}
