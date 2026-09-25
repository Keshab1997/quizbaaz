import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:quizbaaz/data/models/shop_item.dart';
import 'package:quizbaaz/data/providers/user_provider.dart';
import 'package:quizbaaz/data/services/competition_clock.dart';
import 'package:quizbaaz/data/services/daily_score_lock.dart';
import 'package:quizbaaz/data/services/hive_service.dart';

/// The daily competition rule: **one counted score per player per day**.
///
/// The first ranked run is written to today's leaderboard row and locks the
/// day; every later run is played for coins, XP and the streak but never
/// changes the row — not with a better score either. A Score Shield is the one
/// exception: it reopens the day for exactly one replacement run.
void main() {
  late Directory tempDir;
  late String dayKey;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir =
        await Directory.systemTemp.createTemp('quizbaaz_daily_lock_test_');
    Hive.init(tempDir.path);
    await HiveService.initialize();
    dayKey = CompetitionClock.dateKey(DateTime.now());
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// A signed-in player with a clean competition day.
  ///
  /// Guests are skipped by the rule, so the tests need a real (non-guest)
  /// profile. The day's markers are cleared first: they live in the shared
  /// Hive box the whole test file uses.
  Future<UserProvider> newPlayer() async {
    await DailyScoreLock.reset(dayKey);
    await HiveService.setMeta(DailyScoreLock.attemptKey(dayKey), 0);
    final provider = UserProvider()..setGuestMode(false);
    await Future<void>.delayed(Duration.zero);
    return provider;
  }

  /// One finished daily run (10 questions, 10 points each).
  Future<DailyScoreOutcome> play(
    UserProvider provider,
    int score, {
    bool ranked = true,
    double timeSeconds = 45,
  }) =>
      provider.recordQuizResult(
        answered: 10,
        correct: score ~/ 10,
        timeSeconds: timeSeconds,
        isDaily: true,
        ranked: ranked,
        score: score,
      );

  group('one counted score per competition day', () {
    test('the first ranked run is counted and locks the day', () async {
      final user = await newPlayer();

      final outcome = await play(user, 70);

      expect(outcome, DailyScoreOutcome.counted);
      expect(user.todayCountedScore, 70);
      expect(user.todayCountedTimeSeconds, 45);
      expect(user.isDailyScoreLockedToday, isTrue);
      expect(user.dailyRunsToday, 1);
      // The counted score is the one the leaderboard row would carry.
      expect(HiveService.getMeta<int>(DailyScoreLock.scoreKey(dayKey)), 70);
    });

    test('a better replay is played but never replaces the counted score',
        () async {
      final user = await newPlayer();
      await play(user, 40);
      final historyBefore = HiveService.loadQuizHistory().length;

      final outcome = await play(user, 100);

      expect(outcome, DailyScoreOutcome.ignored);
      expect(user.todayCountedScore, 40, reason: 'the day is locked at 40');
      expect(HiveService.getMeta<int>(DailyScoreLock.scoreKey(dayKey)), 40);
      // The replay is still a real run: it is counted as an attempt and it
      // lands in the player's own history.
      expect(user.dailyRunsToday, 2);
      expect(HiveService.loadQuizHistory().length, historyBefore + 1);
    });

    test('an unranked practice run never counts', () async {
      final user = await newPlayer();

      final outcome = await play(user, 90, ranked: false);

      expect(outcome, DailyScoreOutcome.notApplicable);
      expect(user.todayCountedScore, 0);
      expect(user.isDailyScoreLockedToday, isFalse);
      // …but a later ranked run still can.
      expect(await play(user, 60), DailyScoreOutcome.counted);
      expect(user.todayCountedScore, 60);
    });

    test('a guest keeps nothing on the leaderboard', () async {
      await DailyScoreLock.reset(dayKey);
      await HiveService.setMeta(DailyScoreLock.attemptKey(dayKey), 0);
      final guest = UserProvider()..setGuestMode(true);
      await Future<void>.delayed(Duration.zero);

      expect(await play(guest, 80), DailyScoreOutcome.notApplicable);
      expect(guest.isDailyScoreLockedToday, isFalse);
    });
  });

  group('Score Shield', () {
    test('a shield reopens the day for one replacement run', () async {
      final user = await newPlayer();
      await play(user, 30);

      user.user.inventory[ShopItemIds.scoreShield] = 2;
      expect(user.canRetryDailyScoreWithShield, isTrue);

      expect(await user.unlockDailyScoreWithShield(), isTrue);
      expect(user.inventoryCount(ShopItemIds.scoreShield), 1);
      // The locked score stays until the replacement run is actually played.
      expect(user.todayCountedScore, 30);

      expect(await play(user, 80), DailyScoreOutcome.replaced);
      expect(user.todayCountedScore, 80);
      expect(user.canRetryDailyScoreWithShield, isFalse,
          reason: 'the retry is spent; only one shield may be used per day');

      // …and the day is locked again.
      await play(user, 100);
      expect(user.todayCountedScore, 80);
    });

    test('a shield is never spent when there is nothing to replace', () async {
      final user = await newPlayer();
      user.user.inventory[ShopItemIds.scoreShield] = 1;

      // No counted run today: nothing to unlock.
      expect(user.canRetryDailyScoreWithShield, isFalse);
      expect(await user.unlockDailyScoreWithShield(), isFalse);
      expect(user.inventoryCount(ShopItemIds.scoreShield), 1);
    });
  });
}
