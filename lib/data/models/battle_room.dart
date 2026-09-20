import 'question_model.dart';

/// Phase of a live 1v1 room, mirrored in Firestore under `state.phase`.
enum BattleRoomPhase {
  /// Room created, questions being written by the creator.
  lobby,

  /// Deliberate pause before question 0 (players' clients run it locally).
  countdown,

  /// A question is live; both players answer.
  question,

  /// Both answers are in; the reveal window is running locally.
  reveal,

  /// Match over; `winner` is set.
  finished,
}

/// Lifecycle of the room document itself (`status` field).
///
/// The room only exists once the creator has written it, so "no document" is
/// not the same as "match over": it can also mean the room has not been
/// created yet. [hasStarted] is what the clients use to decide whether a
/// missing document is a real disappearance (forfeit) or a race (wait).
enum BattleRoomStatus {
  /// Negotiated but not written yet — the document may not exist at all.
  waiting,

  /// Creator wrote the room (questions + countdown); the opponent may still
  /// be attaching.
  created,

  /// Both players attached to the room.
  ready,

  /// Questions are being played.
  active,

  /// Match over; `winner` is set.
  finished,

  /// One side left mid-match.
  abandoned;

  static BattleRoomStatus parse(Object? raw) {
    final value = raw?.toString() ?? '';
    for (final status in BattleRoomStatus.values) {
      if (status.name == value) return status;
    }
    // Legacy rooms only wrote `status: 'active' | 'finished'`; unknown values
    // are treated as an active room so an old document stays playable.
    return value.isEmpty ? BattleRoomStatus.created : BattleRoomStatus.active;
  }

  /// Both players are in the room (playable, countdown may still be running).
  bool get isPlayable => this == ready || this == active;

  /// The room was really being played — a document disappearing after this
  /// point means the opponent left, not that creation lost the race.
  bool get hasStarted =>
      this == active || this == finished || this == abandoned;
}

/// One answer a player locked in for a single question.
class BattleAnswer {
  final int selected; // -1 when timed out
  final bool correct;
  final int points;
  final int timeBonus; // time-scaled speed bonus actually paid
  final int firstBonus; // paid when locked in before the opponent
  final int streakBonus;
  final int msTaken; // ms spent on this question (0 = unknown / legacy)
  final bool timedOut;

  const BattleAnswer({
    required this.selected,
    required this.correct,
    required this.points,
    required this.timeBonus,
    required this.streakBonus,
    required this.timedOut,
    this.firstBonus = 0,
    this.msTaken = 0,
  });

  Map<String, dynamic> toJson() => {
        'selected': selected,
        'correct': correct,
        'points': points,
        'time_bonus': timeBonus,
        'first_bonus': firstBonus,
        'streak_bonus': streakBonus,
        'ms_taken': msTaken,
        'timed_out': timedOut,
      };

  factory BattleAnswer.fromJson(Map<String, dynamic> json) => BattleAnswer(
        selected: (json['selected'] as num?)?.toInt() ?? -1,
        correct: json['correct'] as bool? ?? false,
        points: (json['points'] as num?)?.toInt() ?? 0,
        timeBonus: (json['time_bonus'] as num?)?.toInt() ?? 0,
        firstBonus: (json['first_bonus'] as num?)?.toInt() ?? 0,
        streakBonus: (json['streak_bonus'] as num?)?.toInt() ?? 0,
        msTaken: (json['ms_taken'] as num?)?.toInt() ?? 0,
        timedOut: json['timed_out'] as bool? ?? false,
      );
}

/// One side of a live room — corresponds to `players.a` / `players.b`.
class BattleRoomPlayer {
  final String uid;
  final String name;
  final String avatar; // asset path or https URL
  final int score;
  final int correct;
  final int streak;
  final int readyForNext;
  final int lastSeenMs;
  final Map<int, BattleAnswer> answers;

  /// Written once when this client first observed the room. Both flags set
  /// means both clients are attached — the room status moves to `ready`.
  final bool attached;

  const BattleRoomPlayer({
    required this.uid,
    required this.name,
    required this.avatar,
    this.score = 0,
    this.correct = 0,
    this.streak = 0,
    this.readyForNext = 0,
    this.lastSeenMs = 0,
    this.answers = const {},
    this.attached = false,
  });

  BattleAnswer? answerFor(int questionIndex) => answers[questionIndex];

  bool get timedOutLast => answers.isEmpty
      ? false
      : answers.values.last.timedOut;

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'name': name,
        'avatar': avatar,
        'score': score,
        'correct': correct,
        'streak': streak,
        'ready_for_next': readyForNext,
        'last_seen': lastSeenMs,
        'attached': attached,
        // A real nested map — never a dotted field path. `answers.0` as a key
        // in a merge write creates a literal "answers.0" field, which the
        // reader below can never find (R11).
        'answers': answers.map(
          (index, entry) => MapEntry('$index', entry.toJson()),
        ),
      };

  factory BattleRoomPlayer.fromJson(Map<String, dynamic> json) {
    final rawAnswers = json['answers'] as Map<String, dynamic>? ?? const {};
    return BattleRoomPlayer(
      uid: json['uid']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Player',
      avatar: json['avatar']?.toString() ?? '',
      score: (json['score'] as num?)?.toInt() ?? 0,
      correct: (json['correct'] as num?)?.toInt() ?? 0,
      streak: (json['streak'] as num?)?.toInt() ?? 0,
      readyForNext: (json['ready_for_next'] as num?)?.toInt() ?? 0,
      lastSeenMs: (json['last_seen'] as num?)?.toInt() ?? 0,
      attached: json['attached'] as bool? ?? false,
      answers: rawAnswers.map(
        (key, value) => MapEntry(
          int.tryParse(key) ?? 0,
          BattleAnswer.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      ),
    );
  }
}

/// The whole room document (`battle_rooms/{roomId}`).
class BattleRoomData {
  final String roomId;

  /// Unique id of *this match* inside the deterministic [roomId].
  ///
  /// The room id is derived from the two uids, so a rematch reuses it. Rewards
  /// are guarded per match, not per room (R11).
  final String matchId;
  final String difficulty;
  final String status; // waiting | created | ready | active | finished | abandoned
  final List<QuestionModel> questions;
  final BattleRoomPhase phase;
  final int questionIndex;
  final int countdownUntilMs;
  final int questionUntilMs;
  final int revealUntilMs;
  final int nextQuestion;
  final int createdAtMs;
  final BattleRoomPlayer? playerA;
  final BattleRoomPlayer? playerB;
  final String? winner; // 'a' | 'b' | 'draw' | null
  final bool abandoned;
  final String? abandonedBy; // 'a' | 'b' — who left

  const BattleRoomData({
    required this.roomId,
    this.matchId = '',
    required this.difficulty,
    required this.status,
    this.questions = const [],
    this.phase = BattleRoomPhase.lobby,
    this.questionIndex = 0,
    this.countdownUntilMs = 0,
    this.questionUntilMs = 0,
    this.revealUntilMs = 0,
    this.nextQuestion = 0,
    this.createdAtMs = 0,
    this.playerA,
    this.playerB,
    this.winner,
    this.abandoned = false,
    this.abandonedBy,
  });

  bool get isFinished => phase == BattleRoomPhase.finished;
  bool get isAbandoned => abandoned;

  /// Parsed [status]. Legacy rooms without a status are treated as active.
  BattleRoomStatus get roomStatus => BattleRoomStatus.parse(status);

  /// Both clients have attached to the room.
  bool get bothAttached =>
      (playerA?.attached ?? false) && (playerB?.attached ?? false);

  /// True when the room is known to have been played — used to tell a race
  /// (room not written yet) apart from a real disappearance (R11).
  bool get hasStarted => roomStatus.hasStarted;

  /// Read-only mapping: 'a'/'b' -> player.
  BattleRoomPlayer? playerOf(String side) =>
      side == 'a' ? playerA : side == 'b' ? playerB : null;

  BattleRoomPlayer? opponentOf(String side) =>
      side == 'a' ? playerB : side == 'b' ? playerA : null;

  bool hasBothAnswered(int index) =>
      (playerA?.answerFor(index) != null) &&
      (playerB?.answerFor(index) != null);

  bool bothReadyFor(int nextIndex) =>
      (playerA?.readyForNext ?? 0) >= nextIndex &&
      (playerB?.readyForNext ?? 0) >= nextIndex;

  bool get hasQuestions => questions.isNotEmpty;

  factory BattleRoomData.fromJson(
    String roomId,
    Map<String, dynamic> json,
  ) {
    final state = json['state'] as Map<String, dynamic>? ?? const {};
    final players = json['players'] as Map<String, dynamic>? ?? const {};
    final rawQuestions = json['questions'] as List? ?? const [];

    return BattleRoomData(
      roomId: roomId,
      matchId: json['match_id']?.toString() ?? '',
      difficulty: json['difficulty']?.toString() ?? 'normal',
      status: json['status']?.toString() ?? 'active',
      questions: rawQuestions
          .whereType<Map>()
          .map((q) => QuestionModel.fromJson(Map<String, dynamic>.from(q)))
          .toList(),
      phase: BattleRoomPhase.values.firstWhere(
        (p) => p.name == state['phase'],
        orElse: () => BattleRoomPhase.lobby,
      ),
      questionIndex: (state['q_index'] as num?)?.toInt() ?? 0,
      countdownUntilMs: (state['countdown_until'] as num?)?.toInt() ?? 0,
      questionUntilMs: (state['question_until'] as num?)?.toInt() ?? 0,
      revealUntilMs: (state['reveal_until'] as num?)?.toInt() ?? 0,
      nextQuestion: (state['next_q'] as num?)?.toInt() ?? 0,
      createdAtMs: (json['created_at'] as num?)?.toInt() ?? 0,
      playerA: players['a'] is Map
          ? BattleRoomPlayer.fromJson(
              Map<String, dynamic>.from(players['a'] as Map),
            )
          : null,
      playerB: players['b'] is Map
          ? BattleRoomPlayer.fromJson(
              Map<String, dynamic>.from(players['b'] as Map),
            )
          : null,
      winner: json['winner']?.toString(),
      abandoned: json['abandoned'] as bool? ?? false,
      abandonedBy: json['abandoned_by']?.toString(),
    );
  }
}

/// A record on the `battle_queue/{uid}` collection.
class BattleQueueEntry {
  final String uid;
  final String name;
  final String avatar;
  final String difficulty;
  final int createdAtMs;

  const BattleQueueEntry({
    required this.uid,
    required this.name,
    required this.avatar,
    required this.difficulty,
    required this.createdAtMs,
  });

  factory BattleQueueEntry.fromId(String id, Map<String, dynamic> json) =>
      BattleQueueEntry(
        uid: id,
        name: json['name']?.toString() ?? 'Player',
        avatar: json['avatar']?.toString() ?? '',
        difficulty: json['difficulty']?.toString() ?? 'normal',
        createdAtMs: (json['created_at'] as num?)?.toInt() ?? 0,
      );
}

/// Field patch that records one answer for [side] — the only writer the live
/// match needs for answers.
///
/// Kept as a nested map (`answers` → `"<index>"` → answer) instead of the
/// literal `'answers.$index'` field path the old code wrote: a dotted key in a
/// merge write lands as a field *named* `answers.0`, which no reader of the
/// nested map can see (R11).
Map<String, dynamic> roomAnswersPatch({
  required String side,
  required int questionIndex,
  required BattleAnswer answer,
}) =>
    {
      'players': {
        side: {
          'answers': {'$questionIndex': answer.toJson()},
        },
      },
    };

/// Deep merge used by `SetOptions(merge: true)` — mirrored here so the exact
/// client/server merge semantics can be exercised in a unit test without a
/// Firestore instance.
Map<String, dynamic> mergeRoomFields(
  Map<String, dynamic> base,
  Map<String, dynamic> patch,
) {
  for (final entry in patch.entries) {
    final incoming = entry.value;
    final existing = base[entry.key];
    if (incoming is Map && existing is Map) {
      base[entry.key] = mergeRoomFields(
        Map<String, dynamic>.from(existing),
        Map<String, dynamic>.from(incoming),
      );
    } else if (incoming is Map) {
      base[entry.key] = mergeRoomFields(
        <String, dynamic>{},
        Map<String, dynamic>.from(incoming),
      );
    } else {
      base[entry.key] = incoming;
    }
  }
  return base;
}
