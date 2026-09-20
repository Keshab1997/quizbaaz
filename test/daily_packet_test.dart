import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:quizbaaz/data/models/champion_model.dart';
import 'package:quizbaaz/data/models/chapter_model.dart';
import 'package:quizbaaz/data/models/daily_quiz_packet.dart';
import 'package:quizbaaz/data/models/leaderboard_model.dart';
import 'package:quizbaaz/data/models/localized_text.dart';
import 'package:quizbaaz/data/models/question_model.dart';
import 'package:quizbaaz/data/repositories/quiz_repository.dart';
import 'package:quizbaaz/data/services/competition_clock.dart';
import 'package:quizbaaz/data/services/daily_quiz_generator.dart';
import 'package:quizbaaz/data/services/daily_quiz_packet_service.dart';
import 'package:quizbaaz/data/services/hive_service.dart';

/// The generator only needs the packet service and a repository for the
/// practice fallback; both are faked so no Firestore is involved.
class _FakePacketService extends DailyQuizPacketService {
  _FakePacketService(this.result);

  final DailyQuizSet result;
  int calls = 0;

  @override
  Future<DailyQuizSet> resolve({DateTime? now, bool forceRefresh = false}) async {
    calls++;
    return result;
  }
}

class _EmptyRepository extends QuizRepository {
  @override
  Future<List<CategoryModel>> getCategoriesAndChapters({
    bool forceRefresh = false,
    bool includeDisabled = false,
  }) async =>
      const [];
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

DailyQuizPacket _packet({
  String dateKey = '2026-09-20',
  int version = 1,
  int count = 2,
  bool approved = true,
  List<Map<String, String>>? questions,
  int deadlineMs = 0,
}) =>
    DailyQuizPacket(
      dateKey: dateKey,
      version: version,
      approved: approved,
      count: count,
      deadlineMs: deadlineMs,
      questions: [
        for (final q in questions ??
            [
              {'chapter_id': 'bio_ch_01', 'question_id': 'bio_ch_01_q001'},
              {'chapter_id': 'bio_ch_02', 'question_id': 'bio_ch_02_q003'},
            ])
          DailyQuizQuestionRef(
            chapterId: q['chapter_id']!,
            questionId: q['question_id']!,
          ),
      ],
    );

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('qb_daily_test');
    Hive.init(tempDir.path);
    await HiveService.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await HiveService.clearAll();
  });

  group('R12 — one competition clock', () {
    test('the day flips exactly at midnight in the competition timezone', () {
      // 18:30 UTC = 00:00 of the next day at UTC+5:30.
      expect(
        CompetitionClock.dateKey(DateTime.utc(2026, 9, 20, 18, 29, 59)),
        '2026-09-20',
      );
      expect(
        CompetitionClock.dateKey(DateTime.utc(2026, 9, 20, 18, 30, 0)),
        '2026-09-21',
      );
      // A device in another timezone still sees the same competition day.
      expect(
        CompetitionClock.dateKey(DateTime.utc(2026, 9, 20, 21, 0, 0)),
        CompetitionClock.dateKey(DateTime.utc(2026, 9, 21, 0, 0, 0)),
      );
    });

    test('day boundaries and the "yesterday" walk line up', () {
      expect(
        CompetitionClock.dayStart('2026-09-20'),
        DateTime.utc(2026, 9, 19, 18, 30),
      );
      expect(
        CompetitionClock.dayEnd('2026-09-20'),
        DateTime.utc(2026, 9, 20, 18, 30),
      );
      expect(CompetitionClock.previousDateKey('2026-09-20'), '2026-09-19');
      // Crossing a month boundary stays a whole day.
      expect(CompetitionClock.previousDateKey('2026-09-01'), '2026-08-31');

      // Time left in the day is never negative.
      expect(
        CompetitionClock.msUntilClose(
          '2026-09-20',
          DateTime.utc(2026, 9, 20, 6, 0),
        ),
        const Duration(hours: 12, minutes: 30).inMilliseconds,
      );
      expect(
        CompetitionClock.msUntilClose(
          '2026-09-20',
          DateTime.utc(2026, 9, 21, 0, 0),
        ),
        0,
      );
    });
  });

  group('R12 — the packet is the competition', () {
    test('only an approved, complete, duplicate-free packet counts', () {
      expect(_packet().isComplete, isTrue);
      expect(_packet().rejectionReason, isNull);

      expect(_packet(approved: false).isComplete, isFalse);
      expect(_packet(approved: false).rejectionReason, contains('approved'));

      expect(_packet(count: 3).isComplete, isFalse);
      expect(_packet(count: 3).rejectionReason, contains('2 of 3'));

      final duplicate = _packet(questions: [
        {'chapter_id': 'bio_ch_01', 'question_id': 'bio_ch_01_q001'},
        {'chapter_id': 'bio_ch_01', 'question_id': 'bio_ch_01_q001'},
      ]);
      expect(duplicate.isComplete, isFalse);
      expect(duplicate.rejectionReason, contains('repeats'));

      expect(_packet(questions: const [], count: 0).isComplete, isFalse);
    });

    test('a closed packet cannot be played as a competition run', () {
      final closed = _packet(
        deadlineMs: DateTime.utc(2026, 9, 20, 18, 30).millisecondsSinceEpoch,
      );
      expect(closed.isOpen(DateTime.utc(2026, 9, 20, 10, 0)), isTrue);
      expect(
        closed.isOpen(DateTime.utc(2026, 9, 20, 18, 30, 1)),
        isFalse,
      );
    });

    test('the cache key is per day and per version', () {
      expect(_packet(version: 1).cacheKey, 'daily_quiz_set_2026-09-20_v1');
      expect(_packet(version: 2).cacheKey, 'daily_quiz_set_2026-09-20_v2');
      // Same version, different day: never shared.
      expect(
        _packet(dateKey: '2026-09-21', version: 1).cacheKey,
        isNot(_packet(version: 1).cacheKey),
      );
    });

    test('parsing drops unusable question refs instead of inventing them', () {
      final parsed = DailyQuizPacket.fromJson('2026-09-20', {
        'version': 4,
        'approved': true,
        'count': 2,
        'deadline_ms': 1234,
        'scoring_contract': 'v2',
        'questions': [
          {'chapter_id': 'bio_ch_01', 'question_id': 'bio_ch_01_q001'},
          {'chapter_id': '', 'question_id': 'x'}, // unusable
          'not-a-map', // unusable
          {'chapter_id': 'bio_ch_02', 'question_id': 'bio_ch_02_q003'},
        ],
      });

      expect(parsed, isNotNull);
      expect(parsed!.version, 4);
      expect(parsed.scoringContract, 'v2');
      expect(parsed.deadlineMs, 1234);
      expect(parsed.questions.map((q) => q.toString()).toList(),
          ['bio_ch_01/bio_ch_01_q001', 'bio_ch_02/bio_ch_02_q003']);
      expect(parsed.isComplete, isTrue);
    });

    test('a ranked packet is played as published', () async {
      final packet = _packet();
      final generator = DailyQuizGenerator(
        quizRepository: _EmptyRepository(),
        packetService: _FakePacketService(
          DailyQuizSet(
            questions: [_question('bio_ch_01_q001'), _question('bio_ch_02_q003')],
            ranked: true,
            packet: packet,
          ),
        ),
      );

      final set = await generator.generateDailySet(date: DateTime.utc(2026, 9, 20, 6));

      expect(set.ranked, isTrue);
      expect(set.unrankedReason, isNull);
      expect(set.questions.map((q) => q.id).toList(),
          ['bio_ch_01_q001', 'bio_ch_02_q003']);
      expect(set.packet?.version, 1);
    });

    test('an incomplete packet falls back to an unranked practice set',
        () async {
      final generator = DailyQuizGenerator(
        quizRepository: _EmptyRepository(),
        packetService: _FakePacketService(
          DailyQuizSet(
            questions: const [],
            ranked: false,
            packet: _packet(approved: false),
            unrankedReason: 'packet not approved yet',
          ),
        ),
      );

      final set = await generator.generateDailySet(date: DateTime.utc(2026, 9, 20, 6));

      expect(set.ranked, isFalse);
      expect(set.questions, isEmpty);
      // The reason survives, the practice fallback changed nothing about it.
      expect(set.unrankedReason, contains('not approved'));
    });

    test('the practice pool is cached under its own key, never the packet key',
        () async {
      final generator = DailyQuizGenerator(
        quizRepository: _EmptyRepository(),
        packetService: _FakePacketService(
          const DailyQuizSet(
            questions: [],
            ranked: false,
            unrankedReason: 'no packet published for 2026-09-20',
          ),
        ),
      );

      await generator.generateDailySet(date: DateTime.utc(2026, 9, 20, 6));

      expect(
        HiveService.cacheGetList('daily_quiz_practice_2026-09-20'),
        isEmpty,
        reason: 'an empty pool must not be cached as a playable set',
      );
      expect(
        HiveService.cacheGetList('daily_quiz_set_2026-09-20_v1'),
        isEmpty,
      );
    });
  });

  group('R12 — reward identity is the uid', () {
    test('duplicate usernames cannot match each other\'s row', () {
      final mine = LeaderboardItem(
        rank: 3,
        userId: 'uid-me',
        name: 'Me',
        username: 'riyad',
        avatarPath: 'a.png',
        score: 90,
        timeSeconds: 40,
        streak: 2,
      );
      final twin = LeaderboardItem(
        rank: 4,
        userId: 'uid-other',
        name: 'Other',
        username: 'riyad', // same username, different player
        avatarPath: 'b.png',
        score: 80,
        timeSeconds: 50,
        streak: 1,
      );

      expect(leaderboardRowBelongsToUser(mine, userId: 'uid-me'), isTrue);
      expect(leaderboardRowBelongsToUser(twin, userId: 'uid-me'), isFalse);
      expect(leaderboardRowBelongsToUser(mine, userId: 'uid-other'), isFalse);
      // An empty uid never matches anything (guests have no row).
      expect(leaderboardRowBelongsToUser(mine, userId: ''), isFalse);
      expect(leaderboardRowBelongsToUser(mine, userId: 'uid-'), isFalse);
    });

    test('the same rule guards the daily champion rewards', () {
      final champion = ChampionModel(
        rank: 1,
        userId: 'uid-other',
        name: 'Other',
        username: 'riyad',
        avatarPath: 'b.png',
        score: 100,
        timeSeconds: 30,
      );
      expect(championRowBelongsToUser(champion, userId: 'uid-me'), isFalse);
      expect(championRowBelongsToUser(champion, userId: 'uid-other'), isTrue);
      expect(championRowBelongsToUser(champion, userId: ''), isFalse);
    });

    test('the leaderboard cache is scoped to the competition day', () {
      expect(
        HiveService.cacheLeaderboardFor('2026-09-20'),
        isNot(HiveService.cacheLeaderboardFor('2026-09-21')),
      );
      // Today's key comes from the competition clock, so a device that thinks
      // it is still the previous day still writes into the right bucket.
      expect(
        HiveService.cacheLeaderboardFor(
          CompetitionClock.dateKey(DateTime.utc(2026, 9, 20, 6)),
        ),
        'leaderboard_2026-09-20',
      );
    });
  });
}
