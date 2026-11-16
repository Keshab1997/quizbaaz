import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:quizbaaz/data/models/champion_model.dart';
import 'package:quizbaaz/data/models/notification_item.dart';
import 'package:quizbaaz/data/providers/user_provider.dart';
import 'package:quizbaaz/data/services/competition_clock.dart';
import 'package:quizbaaz/data/services/hive_service.dart';
import 'package:quizbaaz/data/services/notification_inbox.dart';
import 'package:quizbaaz/data/services/notification_planner.dart';
import 'package:quizbaaz/data/services/notification_service.dart';
import 'package:quizbaaz/data/services/notification_winner_sync.dart';
import 'package:quizbaaz/l10n/app_strings.dart';
import 'package:quizbaaz/presentation/screens/notifications/notification_history_screen.dart';

void main() {
  ChampionModel champ({
    int rank = 1,
    String userId = 'u_winner',
    String name = 'Aarav Sharma',
    String username = 'aarav',
    int score = 100,
    String giftName = '',
    String dateKey = '2026-11-15',
  }) {
    return ChampionModel(
      rank: rank,
      userId: userId,
      name: name,
      username: username,
      avatarPath: '',
      score: score,
      timeSeconds: 32.5,
      giftName: giftName,
      giftIcon: '',
      bonusCoins: 100,
      badgeTitle: 'Champion',
      dateKey: dateKey,
    );
  }

  group('NotificationWinnerSync.buildWinnerItem', () {
    setUp(() => S.load('en'));

    test('returns null when no champions exist for yesterday', () {
      expect(
        NotificationWinnerSync.buildWinnerItem(
          champions: [champ(dateKey: '2026-11-14')],
          yesterdayKey: '2026-11-15',
          currentUserId: 'me',
        ),
        isNull,
      );
    });

    test('creates general winner card with gift details', () {
      final item = NotificationWinnerSync.buildWinnerItem(
        champions: [
          champ(rank: 2, userId: 'u2', name: 'Riya', score: 90),
          champ(
            rank: 1,
            userId: 'u1',
            name: 'Aarav Sharma',
            score: 100,
            giftName: 'Neon Badge',
          ),
        ],
        yesterdayKey: '2026-11-15',
        currentUserId: 'someone_else',
      );
      expect(item, isNotNull);
      expect(item!.id, 'winner_2026-11-15');
      expect(item.kind, NotificationItem.kindWinner);
      expect(item.open, 'winners');
      expect(item.title, contains('Aarav Sharma'));
      expect(item.body, contains('100'));
      expect(item.body, contains('Neon Badge'));
    });

    test('personalizes card when current user won #1', () {
      final item = NotificationWinnerSync.buildWinnerItem(
        champions: [champ(rank: 1, userId: 'me', score: 100)],
        yesterdayKey: '2026-11-15',
        currentUserId: 'me',
      );
      expect(item!.title, S.notifWinnerSelfChampTitle);
      expect(item.body, contains('100'));
    });

    test('personalizes card when current user placed #2..#10', () {
      final item = NotificationWinnerSync.buildWinnerItem(
        champions: [
          champ(rank: 1, userId: 'u1', name: 'Aarav', score: 100),
          champ(rank: 3, userId: 'me', name: 'Me', score: 80),
        ],
        yesterdayKey: '2026-11-15',
        currentUserId: 'me',
      );
      expect(item!.title, contains('#3'));
      expect(item.body, contains('Aarav'));
    });
  });

  group('NotificationService localized copy', () {
    tearDown(() => S.load('en'));

    test('all slots and topics resolve non-empty copy in en, bn, hi', () {
      final now = DateTime(2026, 11, 16, 7, 0);
      final plan = NotificationPlanner.planSchedule(
        now: now,
        playedToday: false,
        streak: 6,
        mistakeCount: 3,
        days: 4,
      );
      for (final lang in ['en', 'bn', 'hi']) {
        S.load(lang);
        for (final planned in plan) {
          final copy = NotificationService.copyForPlanned(
            planned,
            streak: 6,
            mistakeCount: 3,
          );
          expect(copy.title.trim(), isNotEmpty);
          expect(copy.body.trim(), isNotEmpty);
        }
      }
    });

    test('winner slot for today uses cached champion name when available', () {
      S.load('en');
      final when = DateTime(2026, 11, 16, 8, 15);
      final planned = PlannedNotification(
        id: NotificationPlanner.slotNotificationId(
          when,
          NotificationSlot.winnerReveal,
        ),
        scheduledAt: when,
        slot: NotificationSlot.winnerReveal,
        dayIndex: 0,
        open: 'winners',
      );

      final generic = NotificationService.copyForPlanned(planned, streak: 0);
      expect(generic.title, S.notifWinnerMorningTitle);

      final personalized = NotificationService.copyForPlanned(
        planned,
        streak: 0,
        yesterdayWinner: champ(name: 'Ananya Roy', score: 95),
      );
      expect(personalized.title, contains('Ananya Roy'));
      expect(personalized.body, contains('95'));
      expect(personalized.kind, NotificationItem.kindWinner);
    });
  });

  group('NotificationWinnerSync Hive & NotificationHistoryScreen', () {
    late Directory tempDir;
    late String yesterdayKey;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tempDir = await Directory.systemTemp.createTemp('qb_winner_notif_');
      Hive.init(tempDir.path);
      await HiveService.initialize();
      yesterdayKey = CompetitionClock.previousDateKey(
        CompetitionClock.dateKey(DateTime.now()),
      );
    });

    tearDownAll(() async {
      // A Hive write started inside a testWidgets fake zone (`markAllRead`) can
      // leave `Hive.close()` waiting forever; drain with a real-clock deadline.
      final closing = Hive.close();
      var done = false;
      closing.whenComplete(() {
        done = true;
      });
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!done && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (done) await closing;
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    setUp(() async {
      S.load('en');
      NotificationInbox.instance.debugReset();
      await HiveService.clearNotificationHistory();
      await HiveService.setMeta(
        NotificationWinnerSync.metaAnnouncedWinnerDate,
        null,
      );
    });

    test('announceIfNeeded writes once per competition day', () async {
      final champions = [
        champ(
          rank: 1,
          userId: 'u_champ',
          name: 'Priya Sen',
          score: 100,
          dateKey: yesterdayKey,
        ),
      ];

      final first = await NotificationWinnerSync.announceIfNeeded(
        champions: champions,
        currentUserId: 'player_1',
      );
      expect(first, isTrue);
      expect(NotificationInbox.instance.items, hasLength(1));
      expect(NotificationInbox.instance.items.first.isWinner, isTrue);
      expect(
        NotificationInbox.instance.items.first.title,
        contains('Priya Sen'),
      );

      final second = await NotificationWinnerSync.announceIfNeeded(
        champions: champions,
        currentUserId: 'player_1',
      );
      expect(second, isFalse);
      expect(NotificationInbox.instance.items, hasLength(1));
    });

    testWidgets(
      'NotificationHistoryScreen renders winner and challenge cards',
      (tester) async {
        await tester.runAsync(() async {
          await NotificationInbox.instance.add(
            NotificationItem(
              id: 'winner_$yesterdayKey',
              kind: NotificationItem.kindWinner,
              title: 'Yesterday\'s Winner: Priya Sen',
              body: 'Topped yesterday\'s Daily Quiz with 100 pts!',
              open: 'winners',
              receivedAt: DateTime.now(),
            ),
          );
          await NotificationInbox.instance.add(
            NotificationItem(
              id: 'engage_1',
              kind: NotificationItem.kindEngage,
              title: 'Ready for a 1v1 quiz battle?',
              body: 'Challenge a player now!',
              open: 'battle',
              receivedAt: DateTime.now(),
            ),
          );
        });

        await tester.pumpWidget(
          ChangeNotifierProvider(
            create: (_) => UserProvider(),
            child: const MaterialApp(home: NotificationHistoryScreen()),
          ),
        );
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();

        expect(find.text(S.notifKindWinner), findsOneWidget);
        expect(find.text(S.notifKindEngage), findsOneWidget);
        expect(find.textContaining('Priya Sen'), findsOneWidget);
        expect(find.textContaining('1v1 quiz battle'), findsOneWidget);
      },
    );
  });
}
