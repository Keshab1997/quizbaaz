import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:quizbaaz/data/providers/user_provider.dart';
import 'package:quizbaaz/data/services/competition_clock.dart';
import 'package:quizbaaz/data/services/hive_service.dart';

/// The daily-winner celebration must survive the claim that pays for it.
///
/// The claim (coins, gems, items) is recorded once per competition day and
/// credits immediately. The popup is presentation: the dashboard skips it
/// when it is not the current route (the player navigated during the startup
/// awaits), and the day's claim flag means the claim never fires again — so
/// without the pending slot the player would be paid silently and never see
/// the "Yesterday's Quiz Rewards!" card at all.
///
/// What this file pins down:
/// * a successful claim parks the result in `pending_daily_celebration`;
/// * the claim returning null later (already claimed today) does NOT clear
///   the slot — a later dashboard start still finds it;
/// * the slot is read fresh from Hive, so it survives an app restart;
/// * only presenting the dialog (markDailyCelebrationShown) clears it.
void main() {
  late Directory tempDir;
  late String yesterdayKey;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp(
      'quizbaaz_celebration_test_',
    );
    Hive.init(tempDir.path);
    await HiveService.initialize();
    yesterdayKey = CompetitionClock.previousDateKey(
      CompetitionClock.dateKey(DateTime.now()),
    );
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    // The slots this file owns live in the shared Hive box — clear them so
    // each test starts from a clean competition day.
    await HiveService.setMeta('claimed_daily_rank_$yesterdayKey', null);
    await HiveService.setMeta('pending_daily_celebration', null);
    await HiveService.setMeta('winning_streak', null);
  });

  /// A signed-in player whose #1 finish on yesterday's leaderboard is in the
  /// champions cache. Firestore is never ready in tests, so `pullChampions`
  /// falls back to this cache — exactly the path a real offline refresh takes.
  Future<UserProvider> playerWhoWonYesterday() async {
    final provider =
        UserProvider()
          ..setGuestMode(false)
          ..updateUsername('tester');
    await HiveService.cachePut(HiveService.cacheChampions, [
      {
        'rank': 1,
        'user_id': provider.user.userId,
        'name': 'tester',
        'username': 'tester',
        'avatar_path': '',
        'name_effect': '',
        'score': 100,
        'time_seconds': 30,
        'gift_name': '',
        'gift_icon': '',
        'bonus_coins': 0,
        'badge_title': '',
        'date_key': yesterdayKey,
      },
    ]);
    return provider;
  }

  test('a claim parks the celebration until a dashboard shows it', () async {
    final provider = await playerWhoWonYesterday();

    final claim = await provider.checkAndClaimDailyLeaderboardRewards();
    expect(claim, isNotNull);
    expect(claim!.rank, 1);
    expect(claim.coins, 100);
    expect(provider.user.coins, 100, reason: 'the claim credits immediately');

    // Nothing has presented the dialog yet — the result must be waiting.
    final pending = provider.pendingDailyCelebration;
    expect(pending, isNotNull);
    expect(pending!.rank, 1);
    expect(pending.coins, 100);

    // A later dashboard start: the claim is already marked for the day and
    // returns null, but the slot must still hold the celebration.
    expect(await provider.checkAndClaimDailyLeaderboardRewards(), isNull);
    expect(provider.pendingDailyCelebration, isNotNull);
    expect(
      provider.user.coins,
      100,
      reason: 'a second claim must not credit again',
    );

    // Only presenting the dialog clears it.
    await provider.markDailyCelebrationShown();
    expect(provider.pendingDailyCelebration, isNull);
  });

  test('the pending slot survives an app restart', () async {
    final provider = await playerWhoWonYesterday();
    await provider.checkAndClaimDailyLeaderboardRewards();

    // A new provider stands in for the next app launch: the getter reads
    // Hive, so the celebration is still there for the next dashboard.
    final restarted = UserProvider();
    final pending = restarted.pendingDailyCelebration;
    expect(pending, isNotNull);
    expect(pending!.winningStreak, 1);
  });
}
