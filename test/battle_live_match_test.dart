import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:quizbaaz/data/models/app_config.dart';
import 'package:quizbaaz/data/models/battle_room.dart';
import 'package:quizbaaz/data/models/localized_text.dart';
import 'package:quizbaaz/data/models/question_model.dart';
import 'package:quizbaaz/data/models/user_model.dart';
import 'package:quizbaaz/data/providers/battle_provider.dart';
import 'package:quizbaaz/data/providers/user_provider.dart';
import 'package:quizbaaz/data/services/battle_question_generator.dart';
import 'package:quizbaaz/data/services/battle_room_service.dart';
import 'package:quizbaaz/data/services/hive_service.dart';

/// In-memory stand-in for the Firestore-backed room service: records every
/// call and lets the test drive the room stream by hand.
class _FakeRoomService extends BattleRoomService {
  final List<String> calls = [];
  final List<String> queued = [];
  final List<String> leftQueue = [];
  final List<String> abandoned = [];
  final List<String> finished = [];
  final List<Map<String, Object?>> claims = [];
  final List<Map<String, dynamic>> answerWrites = [];
  final List<Map<String, dynamic>> playerWrites = [];

  /// Room snapshot the test wants the provider to see.
  final StreamController<BattleRoomData?> roomStream =
      StreamController<BattleRoomData?>.broadcast();

  QueueClaimOutcome Function(String roomId)? claimResult;

  @override
  Future<void> joinQueue({
    required String uid,
    required String name,
    required String avatar,
    required String difficulty,
  }) async {
    calls.add('joinQueue');
    queued.add(uid);
  }

  @override
  Future<void> leaveQueue(String uid) async {
    calls.add('leaveQueue');
    leftQueue.add(uid);
  }

  @override
  Future<QueueSearchResult> findOpponent({
    required String myUid,
    required String difficulty,
  }) async {
    calls.add('findOpponent');
    return QueueSearchResult.empty();
  }

  @override
  Future<QueueClaimOutcome> claimOpponent({
    required String myUid,
    required String opponentUid,
    required String difficulty,
    required String matchId,
    required BattleRoomPlayerInfo me,
    required BattleRoomPlayerInfo opponent,
    required List<QuestionModel> questions,
    required int countdownUntilMs,
  }) async {
    calls.add('claimOpponent');
    final roomId = BattleRoomService.roomIdFor(myUid, opponentUid);
    claims.add({
      'roomId': roomId,
      'myUid': myUid,
      'opponentUid': opponentUid,
      'matchId': matchId,
      'difficulty': difficulty,
      'questions': questions.length,
      'me': me.uid,
      'opponent': opponent.uid,
    });
    final builder = claimResult;
    if (builder != null) return builder(roomId);
    return QueueClaimOutcome.created(roomId: roomId, matchId: matchId);
  }

  @override
  Stream<BattleRoomData?> watchRoom(String roomId) {
    calls.add('watchRoom');
    return roomStream.stream;
  }

  @override
  Future<BattleRoomData?> readRoom(String roomId) async => null;

  @override
  Future<bool> updateMyPlayer(
    String roomId,
    String side,
    Map<String, dynamic> fields,
  ) async {
    playerWrites.add({'roomId': roomId, 'side': side, 'fields': fields});
    return true;
  }

  @override
  Future<bool> writeMyAnswer({
    required String roomId,
    required String side,
    required int questionIndex,
    required BattleAnswer answer,
    Map<String, dynamic> extraFields = const {},
  }) async {
    answerWrites.add({
      'roomId': roomId,
      'side': side,
      'index': questionIndex,
      'answer': answer.toJson(),
    });
    return true;
  }

  @override
  Future<bool> attachPlayer(String roomId, String side) async {
    calls.add('attachPlayer');
    return true;
  }

  @override
  Future<void> markActive(String roomId) async => calls.add('markActive');

  @override
  Future<void> markReady(String roomId) async => calls.add('markReady');

  @override
  Future<void> abandonRoom(String roomId, String side) async {
    calls.add('abandonRoom');
    abandoned.add(roomId);
  }

  @override
  Future<void> finishRoom(
    String roomId,
    String winner, {
    String? matchId,
  }) async {
    calls.add('finishRoom');
    finished.add('$roomId|$winner|${matchId ?? ''}');
  }

  @override
  Future<void> advanceState(
    String roomId,
    Map<String, dynamic> state,
  ) async {
    calls.add('advanceState');
  }
}

/// The battle provider only needs the profile, the tunables and the reward
/// hooks from the user provider — the real one would want Hive + Firebase.
class _FakeUserProvider extends UserProvider {
  _FakeUserProvider(this._fakeUser);

  final UserModel _fakeUser;
  final List<String> rewards = [];
  final List<bool> battleResults = [];

  @override
  UserModel get user => _fakeUser;

  @override
  AppConfig get config => const AppConfig();

  @override
  bool grantQuizRewards({
    required int coins,
    required int gems,
    required bool isDailyQuiz,
  }) {
    rewards.add('coins:$coins gems:$gems daily:$isDailyQuiz');
    return true;
  }

  @override
  Future<void> recordBattleResult({required bool won}) async {
    battleResults.add(won);
  }

  @override
  Future<void> recordQuizResult({
    required int answered,
    required int correct,
    required double timeSeconds,
    required bool isDaily,
    bool ranked = true,
    int? score,
    String? chapterId,
    String? categoryTitle,
    String? categoryTitleBn,
    String? chapterTitle,
    String? chapterTitleBn,
    int? coinsEarned,
    int? gemsEarned,
  }) async {}
}

class _FakeQuestionGenerator extends BattleQuestionGenerator {
  _FakeQuestionGenerator(this.questions);

  final List<QuestionModel> questions;
  int calls = 0;

  @override
  Future<List<QuestionModel>> generateBattleQuestions({int? count}) async {
    calls++;
    return questions;
  }
}

QuestionModel _question(String id) => QuestionModel(
      id: id,
      questionText: LocalizedText({'en': 'Question $id'}),
      optionTexts: const [
        LocalizedText({'en': 'A'}),
        LocalizedText({'en': 'B'}),
      ],
      correctIndex: 0,
    );

const _myUid = 'uid_aaa'; // lexicographically smaller → room creator
const _opponentUid = 'uid_zzz';

Map<String, dynamic> _roomJson({
  String status = 'created',
  String matchId = 'm_room_1',
  bool withQuestions = true,
  bool abandoned = false,
}) =>
    {
      'match_id': matchId,
      'difficulty': 'normal',
      'status': status,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'abandoned': abandoned,
      'questions': [
        if (withQuestions) _question('q1').toJson(),
        if (withQuestions) _question('q2').toJson(),
      ],
      'state': {
        'phase': 'countdown',
        'q_index': 0,
        'countdown_until': DateTime.now().millisecondsSinceEpoch + 8000,
      },
      'players': {
        'a': const BattleRoomPlayer(
          uid: _myUid,
          name: 'Alpha',
          avatar: 'a.png',
          attached: true,
        ).toJson(),
        'b': const BattleRoomPlayer(
          uid: _opponentUid,
          name: 'Zeta',
          avatar: 'z.png',
          attached: true,
        ).toJson(),
      },
      'winner': null,
    };

void main() {
  late Directory tempDir;
  late _FakeRoomService rooms;
  late _FakeQuestionGenerator questions;
  late _FakeUserProvider users;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('qb_battle_test');
    Hive.init(tempDir.path);
    await HiveService.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    // Also resets the battle reward guard (it lives in the stats box).
    await HiveService.clearAll();
    users = _FakeUserProvider(
      UserModel(
        userId: _myUid,
        username: 'alpha',
        fullName: 'Alpha',
        avatarPath: 'assets/images/avatars/quizbaaz_avatar_boy.png',
        isGuest: false,
      ),
    );
    rooms = _FakeRoomService();
    questions = _FakeQuestionGenerator([_question('q1'), _question('q2')]);
  });

  tearDown(() async {
    await rooms.roomStream.close();
  });

  BattleProvider newProvider() {
    final provider = BattleProvider(
      users,
      roomService: rooms,
      questionGenerator: questions,
    );
    addTearDown(provider.dispose);
    return provider;
  }

  group('R10 — a challenge accept starts the intended battle', () {
    test('the room is created for the accepted opponent, never a bot', () async {
      final provider = newProvider();

      final started = await provider.startBattleWithOpponent(
        opponentUid: _opponentUid,
        opponentName: 'Zeta',
        opponentAvatar: 'z.png',
        difficulty: BattleDifficulty.hard,
      );

      expect(started, isTrue);
      expect(rooms.claims, hasLength(1));
      expect(rooms.claims.single['opponentUid'], _opponentUid);
      expect(rooms.claims.single['me'], _myUid);
      expect(
        rooms.claims.single['roomId'],
        BattleRoomService.roomIdFor(_myUid, _opponentUid),
      );
      expect(rooms.claims.single['difficulty'], 'hard');
      expect(rooms.claims.single['questions'], 2);
      expect(rooms.claims.single['matchId'], isNotEmpty);

      expect(provider.isBotMatch, isFalse);
      expect(provider.opponent?.uid, _opponentUid);
      expect(provider.opponent?.isBot, isFalse);
      expect(provider.phase, BattlePhase.found);
      expect(provider.hasMatchSession, isTrue);
      expect(provider.questions, hasLength(2));
      expect(provider.startError, isNull);

      // The random-matchmaking path (queue) is never touched: no random or
      // bot opponent can be substituted for the challenged player.
      expect(rooms.queued, isEmpty);
      expect(rooms.calls, isNot(contains('findOpponent')));
      expect(rooms.calls, contains('watchRoom'));
    });

    test('a failed start rolls back and explains itself', () async {
      rooms.claimResult = (roomId) => QueueClaimOutcome.opponentGone(
            roomId: roomId,
          );
      final provider = newProvider();

      final started = await provider.startBattleWithOpponent(
        opponentUid: _opponentUid,
        opponentName: 'Zeta',
        opponentAvatar: 'z.png',
      );

      expect(started, isFalse);
      expect(provider.startError, isNotNull);
      expect(provider.phase, BattlePhase.setup);
      expect(provider.opponent, isNull);
      expect(provider.isBotMatch, isTrue);
      expect(provider.hasMatchSession, isFalse);
      // The queue entry claimed for this attempt is gone again.
      expect(rooms.leftQueue, contains(_myUid));
    });

    test('a rejected claim (rules/index) fails instead of falling back',
        () async {
      rooms.claimResult = (roomId) => QueueClaimOutcome.failure(
            roomId: roomId,
            error: 'permission-denied',
          );
      final provider = newProvider();

      expect(
        await provider.startBattleWithOpponent(
          opponentUid: _opponentUid,
          opponentName: 'Zeta',
          opponentAvatar: 'z.png',
        ),
        isFalse,
      );
      expect(provider.startError, isNotNull);
      expect(provider.questions, isEmpty);
    });

    test('two consecutive matches get different session ids', () async {
      final provider = newProvider();

      await provider.startBattleWithOpponent(
        opponentUid: _opponentUid,
        opponentName: 'Zeta',
        opponentAvatar: 'z.png',
      );
      final first = provider.matchSessionId;

      await provider.startBattleWithOpponent(
        opponentUid: _opponentUid,
        opponentName: 'Zeta',
        opponentAvatar: 'z.png',
      );
      final second = provider.matchSessionId;

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(second, isNot(first));
    });
  });

  group('R11 — room lifecycle', () {
    test('an answer round-trips through the nested room map', () {
      final room = _roomJson();
      const answer = BattleAnswer(
        selected: 1,
        correct: true,
        points: 23,
        timeBonus: 10,
        firstBonus: 3,
        streakBonus: 0,
        msTaken: 4200,
        timedOut: false,
      );

      final merged = mergeRoomFields(
        room,
        roomAnswersPatch(side: 'a', questionIndex: 0, answer: answer),
      );
      final data = BattleRoomData.fromJson('room_x', merged);

      final read = data.playerA?.answerFor(0);
      expect(read, isNotNull);
      expect(read!.selected, 1);
      expect(read.correct, isTrue);
      expect(read.points, 23);
      expect(read.msTaken, 4200);

      // The wire shape is a nested map, never a dotted field name.
      final players = merged['players'] as Map;
      final playerA = players['a'] as Map;
      expect((playerA['answers'] as Map).keys.toList(), ['0']);
      expect(merged.containsKey('answers.0'), isFalse);
      expect(playerA.containsKey('answers.0'), isFalse);
    });

    test('both-answered synchronisation works with real answers', () {
      var room = _roomJson();
      const answerA = BattleAnswer(
        selected: 0,
        correct: true,
        points: 20,
        timeBonus: 10,
        streakBonus: 0,
        timedOut: false,
      );
      const answerB = BattleAnswer(
        selected: 1,
        correct: false,
        points: 0,
        timeBonus: 0,
        streakBonus: 0,
        timedOut: false,
      );

      room = mergeRoomFields(
        room,
        roomAnswersPatch(side: 'a', questionIndex: 0, answer: answerA),
      );
      expect(
        BattleRoomData.fromJson('room_x', room).hasBothAnswered(0),
        isFalse,
      );

      room = mergeRoomFields(
        room,
        roomAnswersPatch(side: 'b', questionIndex: 0, answer: answerB),
      );
      final data = BattleRoomData.fromJson('room_x', room);
      expect(data.hasBothAnswered(0), isTrue);
      // Answers of different players never overwrite each other.
      expect(data.playerA?.answerFor(0)?.correct, isTrue);
      expect(data.playerB?.answerFor(0)?.correct, isFalse);
    });

    test('the legacy dotted field is invisible to the reader (why it broke)',
        () {
      // Exactly what the old writer produced: a field literally named
      // "answers.0" instead of a nested answers map.
      final room = _roomJson();
      final players = Map<String, dynamic>.from(room['players'] as Map);
      final playerA = Map<String, dynamic>.from(players['a'] as Map);
      playerA['answers.0'] = const BattleAnswer(
        selected: 1,
        correct: true,
        points: 23,
        timeBonus: 10,
        streakBonus: 0,
        timedOut: false,
      ).toJson();
      players['a'] = playerA;
      room['players'] = players;

      final data = BattleRoomData.fromJson('room_x', room);
      expect(data.playerA?.answerFor(0), isNull);
      expect(data.hasBothAnswered(0), isFalse);
    });

    test('room status drives "has started" (race vs departure)', () {
      expect(BattleRoomStatus.parse('created').hasStarted, isFalse);
      expect(BattleRoomStatus.parse('ready').isPlayable, isTrue);
      expect(BattleRoomStatus.parse('ready').hasStarted, isFalse);
      expect(BattleRoomStatus.parse('active').hasStarted, isTrue);
      expect(BattleRoomStatus.parse('finished').hasStarted, isTrue);
      expect(BattleRoomStatus.parse('abandoned').hasStarted, isTrue);
      // Legacy documents only knew active/finished; unknown values stay
      // playable so an old room is not abandoned by accident.
      expect(BattleRoomStatus.parse('legacy-value').hasStarted, isTrue);

      expect(
        BattleRoomData.fromJson('room_x', _roomJson(status: 'created'))
            .hasStarted,
        isFalse,
      );
      expect(
        BattleRoomData.fromJson('room_x', _roomJson(status: 'active'))
            .hasStarted,
        isTrue,
      );
    });

    test('bothAttached needs both sides', () {
      final one = _roomJson();
      (one['players'] as Map)['b'] = const BattleRoomPlayer(
        uid: _opponentUid,
        name: 'Zeta',
        avatar: 'z.png',
      ).toJson();
      expect(BattleRoomData.fromJson('room_x', one).bothAttached, isFalse);

      expect(
        BattleRoomData.fromJson('room_x', _roomJson()).bothAttached,
        isTrue,
      );
    });

    test('a missing room before creation is a race, not a forfeit', () async {
      final provider = newProvider();
      await provider.startBattleWithOpponent(
        opponentUid: _opponentUid,
        opponentName: 'Zeta',
        opponentAvatar: 'z.png',
      );

      // The joiner/slow creator sees no document yet.
      rooms.roomStream.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(provider.phase, BattlePhase.found);
      expect(provider.isForfeit, isFalse);
    });

    test('a room that disappears mid-match is a forfeit win', () async {
      final provider = newProvider();
      await provider.startBattleWithOpponent(
        opponentUid: _opponentUid,
        opponentName: 'Zeta',
        opponentAvatar: 'z.png',
      );

      rooms.roomStream.add(
        BattleRoomData.fromJson('room_x', _roomJson(status: 'active')),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(provider.phase, isNot(BattlePhase.finished));

      rooms.roomStream.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(provider.isForfeit, isTrue);
      expect(provider.phase, BattlePhase.finished);
      expect(rooms.finished, isNotEmpty);
    });

    test('the reward guard is per match, not per room', () async {
      final provider = newProvider();
      await provider.startBattleWithOpponent(
        opponentUid: _opponentUid,
        opponentName: 'Zeta',
        opponentAvatar: 'z.png',
      );
      final matchId = provider.matchSessionId!;
      final roomId = BattleRoomService.roomIdFor(_myUid, _opponentUid);

      rooms.roomStream.add(
        BattleRoomData.fromJson('room_x', _roomJson(status: 'active')),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      rooms.roomStream.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(
        HiveService.isBattleRoomProcessed('$roomId#$matchId'),
        isTrue,
        reason: 'the settled match must be remembered exactly once',
      );
      expect(
        HiveService.isBattleRoomProcessed('$roomId#m_rematch_2'),
        isFalse,
        reason: 'a rematch in the same room is a new match and must pay again',
      );
    });

    test('a live answer is written through the nested-map writer', () async {
      final provider = newProvider();
      await provider.startBattleWithOpponent(
        opponentUid: _opponentUid,
        opponentName: 'Zeta',
        opponentAvatar: 'z.png',
      );

      // A room whose countdown already elapsed → the next tick starts
      // question 0.
      final json = _roomJson(status: 'active');
      (json['state'] as Map)['countdown_until'] =
          DateTime.now().millisecondsSinceEpoch - 1000;
      rooms.roomStream.add(BattleRoomData.fromJson('room_x', json));
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(provider.phase, BattlePhase.question);
      expect(rooms.calls, contains('markActive'));

      provider.answerQuestion(0);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(rooms.answerWrites, hasLength(1));
      final write = rooms.answerWrites.single;
      expect(write['index'], 0);
      expect(write['side'], 'a');
      expect((write['answer'] as Map)['correct'], isTrue);
      expect((write['answer'] as Map)['selected'], 0);
      // The answers never travel as dotted field paths.
      expect(
        rooms.playerWrites
            .expand((w) => (w['fields'] as Map).keys)
            .where((k) => k.toString().startsWith('answers')),
        isEmpty,
      );
    });
  });

  group('R17 — matchmaking failures are not disguised as "empty queue"', () {
    test('index/permission errors are configuration failures', () {
      final index = QueueSearchResult.failure(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'failed-precondition',
          message: 'The query requires an index.',
        ),
      );
      expect(index.isConfigurationError, isTrue);
      expect(index.isEmpty, isFalse);

      final denied = QueueSearchResult.failure(
        Exception('permission-denied: Missing or insufficient permissions.'),
      );
      expect(denied.isConfigurationError, isTrue);

      final offline = QueueSearchResult.failure(
        Exception('SocketException: connection refused'),
      );
      expect(offline.isConfigurationError, isFalse);
      expect(offline.isEmpty, isFalse);

      expect(QueueSearchResult.empty().isEmpty, isTrue);
      expect(QueueSearchResult.empty().isConfigurationError, isFalse);
    });
  });
}
