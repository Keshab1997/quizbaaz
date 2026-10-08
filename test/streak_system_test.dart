import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:quizbaaz/data/models/user_model.dart';
import 'package:quizbaaz/data/providers/user_provider.dart';
import 'package:quizbaaz/data/services/hive_service.dart';
import 'package:quizbaaz/data/services/onesignal_service.dart';
import 'package:quizbaaz/presentation/widgets/streak_flame_widget.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    OneSignalService.disabledForTests = true;
    tempDir = await Directory.systemTemp.createTemp('quizbaaz_streak_test_');
    Hive.init(tempDir.path);
    await HiveService.initialize();
  });

  setUp(() async {
    await HiveService.clearAll();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('UserModel & UserProvider streak logic', () {
    test('Battle Arena and Daily Quiz both advance streak once per day', () {
      final user = UserModel.newPlayer();
      final thu = DateTime(2026, 10, 8, 10, 0); // Thursday
      final fri = DateTime(2026, 10, 9, 11, 0); // Friday

      // 1. Battle Arena on Thursday -> streak = 1, playedTodayDailyQuiz = false
      expect(user.registerPlayOn(thu, isDailyQuiz: false), isTrue);
      expect(user.dailyStreak, 1);
      expect(user.lastStreakDate, '2026-10-08');
      expect(user.playedTodayDailyQuiz, isFalse);
      expect(user.streakDates, contains('2026-10-08'));

      // 2. Daily Quiz later on Thursday -> streak stays 1, playedTodayDailyQuiz = true
      expect(user.registerPlayOn(thu, isDailyQuiz: true), isTrue);
      expect(user.dailyStreak, 1);
      expect(user.playedTodayDailyQuiz, isTrue);

      // 3. Another Battle on Friday -> consecutive streak grows to 2
      expect(user.registerPlayOn(fri, isDailyQuiz: false), isTrue);
      expect(user.dailyStreak, 2);
      expect(user.lastStreakDate, '2026-10-09');
      expect(user.playedTodayDailyQuiz, isFalse);
      expect(
        user.streakDates,
        containsAll(<String>['2026-10-08', '2026-10-09']),
      );
    });

    test(
      'Missing a day resets consecutive streak to 1 while keeping played dates',
      () {
        final user = UserModel.newPlayer();
        final mon = DateTime(2026, 10, 5, 9, 0); // Monday
        final thu = DateTime(2026, 10, 8, 9, 0); // Thursday (missed Tue & Wed)

        user.registerPlayOn(mon, isDailyQuiz: true);
        expect(user.dailyStreak, 1);

        user.registerPlayOn(thu, isDailyQuiz: false);
        expect(user.dailyStreak, 1);
        expect(user.hasPlayedOnDate(mon), isTrue);
        expect(user.hasPlayedOnDate(DateTime(2026, 10, 6)), isFalse);
        expect(user.hasPlayedOnDate(DateTime(2026, 10, 7)), isFalse);
        expect(user.hasPlayedOnDate(thu), isTrue);
      },
    );

    test(
      'UserProvider.recordBattleResult advances dailyStreak in Hive',
      () async {
        final provider = UserProvider();
        expect(provider.user.dailyStreak, 0);

        await provider.recordBattleResult(won: true);
        expect(provider.user.dailyStreak, 1);
        expect(provider.user.playedTodayDailyQuiz, isFalse);
        expect(provider.stats.longestStreak, 1);

        final persisted = HiveService.loadUser();
        expect(persisted, isNotNull);
        expect(persisted!.dailyStreak, 1);
      },
    );

    test('Chapter quiz does not advance dailyStreak', () async {
      final provider = UserProvider();
      await provider.recordQuizResult(
        answered: 10,
        correct: 8,
        timeSeconds: 45,
        isDaily: false,
        chapterId: 'ch_1',
      );
      expect(provider.user.dailyStreak, 0);
    });
  });

  group('StreakFlameWidget weekly calendar markers', () {
    testWidgets(
      'Playing on Thursday after missing Mon–Wed marks Mon–Wed as cross and Thu as check',
      (tester) async {
        final thursday = DateTime(2026, 10, 8, 14, 0); // Thu

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StreakFlameWidget(
                streakDays: 1,
                lastStreakDate: '2026-10-08',
                streakDates: const ['2026-10-08'],
                referenceDate: thursday,
              ),
            ),
          ),
        );

        expect(find.text('1 Days'), findsOneWidget);
        // Mon, Tue, Wed missed -> 3 crosses
        expect(find.byIcon(Icons.close_rounded), findsNWidgets(3));
        // Thu played -> 1 check
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'Mid-week broken streak shows check on Monday & Thursday, cross on Tuesday & Wednesday, and 1 Days on top',
      (tester) async {
        final thursday = DateTime(2026, 10, 8, 14, 0); // Thu

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StreakFlameWidget(
                streakDays: 1,
                lastStreakDate: '2026-10-08',
                streakDates: const ['2026-10-05', '2026-10-08'],
                referenceDate: thursday,
              ),
            ),
          ),
        );

        expect(find.text('1 Days'), findsOneWidget);
        // Mon & Thu played -> 2 checks
        expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
        // Tue & Wed missed -> 2 crosses
        expect(find.byIcon(Icons.close_rounded), findsNWidgets(2));
      },
    );
  });
}
