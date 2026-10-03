import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:quizbaaz/data/providers/quiz_provider.dart';
import 'package:quizbaaz/data/providers/user_provider.dart';
import 'package:quizbaaz/data/services/hive_service.dart';
import 'package:quizbaaz/l10n/app_strings.dart';
import 'package:quizbaaz/presentation/screens/daily_quiz/daily_quiz_ready_screen.dart';
import 'package:quizbaaz/presentation/screens/daily_quiz/daily_quiz_screen.dart';

/// The 19:00 reminder opens the ready gate — it must never start a run, and
/// never restart one that is already live.
///
/// See `AppNavigator` case `daily_quiz` and [QuizProvider.hasLiveDailyRun]:
/// a reminder tap used to call `startDailyQuiz()` and open the quiz screen in
/// the same breath, which spent the day's one counted attempt before the
/// player decided to play.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp(
      'quizbaaz_ready_gate_test_',
    );
    Hive.init(tempDir.path);
    await HiveService.initialize();
    S.load('en');
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Pushes the gate over a placeholder route, exactly like a notification
  /// tap does, so a pop can be observed.
  ///
  /// The gate is a full phone screen (mascot + copy + buttons) and taller than
  /// the default 800x600 test surface, so the surface is set to a phone shape
  /// — otherwise the lower buttons sit outside the viewport and a tap misses
  /// them.
  Future<QuizProvider> pumpGate(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final userProvider = UserProvider();
    final quizProvider = QuizProvider(userProvider);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ChangeNotifierProvider<QuizProvider>.value(value: quizProvider),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Center(child: Text('dashboard'))),
        ),
      ),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(builder: (_) => const DailyQuizReadyScreen()),
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return quizProvider;
  }

  testWidgets('opening the gate starts nothing', (tester) async {
    final quiz = await pumpGate(tester);

    expect(find.text(S.dailyReadyStart), findsOneWidget);
    expect(find.text(S.dailyReadyNotNow), findsOneWidget);
    expect(find.byType(DailyQuizScreen), findsNothing);
    expect(quiz.isLoading, isFalse);
    expect(quiz.questions, isEmpty);
    expect(quiz.hasLiveDailyRun, isFalse);
  });

  testWidgets('"Not now" closes the gate without starting a run', (
    tester,
  ) async {
    final quiz = await pumpGate(tester);
    final notNow = find.widgetWithText(TextButton, S.dailyReadyNotNow);

    await tester.ensureVisible(notNow);
    await tester.pump();
    await tester.tap(notNow);
    await tester.pumpAndSettle();

    expect(find.text('dashboard'), findsOneWidget);
    expect(find.byType(DailyQuizReadyScreen), findsNothing);
    expect(quiz.isLoading, isFalse);
    expect(quiz.questions, isEmpty);
  });
}
