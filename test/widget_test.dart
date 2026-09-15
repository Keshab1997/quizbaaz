import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:quizbaaz/data/models/localized_text.dart';
import 'package:quizbaaz/data/models/question_model.dart';
import 'package:quizbaaz/data/models/user_stats.dart';
import 'package:quizbaaz/data/providers/locale_provider.dart';
import 'package:quizbaaz/data/providers/quiz_provider.dart';
import 'package:quizbaaz/data/providers/user_provider.dart';
import 'package:quizbaaz/data/services/hive_service.dart';
import 'package:quizbaaz/l10n/app_strings.dart';
import 'package:quizbaaz/l10n/strings_bn.dart';
import 'package:quizbaaz/l10n/strings_en.dart';
import 'package:quizbaaz/l10n/strings_hi.dart';
import 'package:quizbaaz/main.dart';
import 'package:quizbaaz/presentation/screens/daily_quiz/daily_quiz_loading_card.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('quizbaaz_test_');
    Hive.init(tempDir.path);
    await HiveService.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('daily quiz loading card shows the 3D intro', (tester) async {
    S.load('en');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => UserProvider()),
          ChangeNotifierProvider(
            create: (ctx) => QuizProvider(ctx.read<UserProvider>()),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: DailyQuizLoadingCard()),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(DailyQuizLoadingCard), findsOneWidget);
    expect(find.text(S.quizLoadStepShuffle), findsOneWidget);
  });

  testWidgets('QuizBaazApp builds without crashing', (tester) async {
    await tester.pumpWidget(
      QuizBaazApp(localeProvider: LocaleProvider()..initialize()),
    );
    await tester.pump();
    // The dashboard kicks off optional-SDK work after the first frame (UMP
    // consent waits up to 5s per step). Advance the fake clock so those
    // timeout timers fire before teardown, otherwise flutter_test fails
    // with "A Timer is still pending".
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();

    expect(find.byType(QuizBaazApp), findsOneWidget);
  });

  group('localisation', () {
    tearDown(() => S.load('en'));

    test('every shipped catalogue covers all English keys', () {
      for (final entry in {'bn': kStringsBn, 'hi': kStringsHi}.entries) {
        final missing =
            kStringsEn.keys.where((k) => !entry.value.containsKey(k)).toList();
        expect(missing, isEmpty,
            reason: '${entry.key} is missing ${missing.length} key(s)');
      }
    });

    test('no translation invents a key the base language lacks', () {
      for (final entry in {'bn': kStringsBn, 'hi': kStringsHi}.entries) {
        final stray =
            entry.value.keys.where((k) => !kStringsEn.containsKey(k)).toList();
        expect(stray, isEmpty,
            reason: '${entry.key} has stray key(s): $stray');
      }
    });

    test('placeholders match across languages', () {
      final pattern = RegExp(r'\{(\w+)\}');
      Set<String> holders(String v) =>
          pattern.allMatches(v).map((m) => m.group(1)!).toSet();

      for (final entry in {'bn': kStringsBn, 'hi': kStringsHi}.entries) {
        for (final key in kStringsEn.keys) {
          final translated = entry.value[key];
          if (translated == null) continue;
          expect(holders(translated), holders(kStringsEn[key]!),
              reason: '${entry.key} placeholder mismatch on "$key"');
        }
      }
    });

    test('S switches catalogue and falls back to English', () {
      S.load('bn');
      expect(S.code, 'bn');
      expect(S.cancel, kStringsBn['cancel']);

      S.load('hi');
      expect(S.cancel, kStringsHi['cancel']);

      // An unsupported code must not throw — it degrades to English.
      S.load('xx');
      expect(S.code, 'en');
      expect(S.cancel, kStringsEn['cancel']);

      // A key nobody translated still resolves to something readable.
      expect(S.raw('definitely_not_a_key'), 'definitely_not_a_key');
    });

    test('fill substitutes every placeholder occurrence', () {
      expect(S.fill('{n} of {n} in {where}', {'n': 3, 'where': 'Howrah'}),
          '3 of 3 in Howrah');
      expect(S.chapterCount(n: 12), contains('12'));
    });

    test('language choice survives a restart', () async {
      final provider = LocaleProvider()..initialize();
      await provider.setAppLanguage('bn');
      expect(provider.appLanguage, 'bn');
      expect(provider.followSystem, isFalse);

      // A fresh provider reads the same Hive box a cold start would.
      final restarted = LocaleProvider()..initialize();
      expect(restarted.appLanguage, 'bn');
      expect(S.code, 'bn');

      await restarted.useSystemLanguage();
      expect(restarted.followSystem, isTrue);
    });

  });

  test('a fresh install starts with zeroed stats (no fake data)', () {
    final stats = HiveService.loadStats();
    expect(stats.totalAnswered, 0);
    expect(stats.totalCorrect, 0);
    expect(stats.hasData, isFalse);
    expect(stats.accuracyLabel, '--');
  });

  test('stats survive a Hive round-trip', () async {
    final stats = UserStats.empty()
      ..recordQuiz(
        answered: 10,
        correct: 8,
        timeSeconds: 60,
        isDaily: true,
        dailyScore: 120,
      );
    await HiveService.saveStats(stats);

    final restored = HiveService.loadStats();
    expect(restored.totalAnswered, 10);
    expect(restored.totalCorrect, 8);
    expect(restored.accuracyRounded, 80);
    expect(restored.bestDailyScore, 120);
  });

  test('offline writes are queued and can be drained', () async {
    await HiveService.clearPending();
    await HiveService.enqueuePending('save_user', {'user_id': 'u1'});
    expect(HiveService.pendingCount, 1);

    final ops = HiveService.pendingOps();
    expect(ops.first.value['type'], 'save_user');

    await HiveService.removePending(ops.first.key);
    expect(HiveService.pendingCount, 0);
  });

  group('localized quiz content', () {
    tearDown(() => S.load('en'));

    Map<String, dynamic> sampleQuestion() => {
          'id': 'q1',
          'question': {
            'en': 'Which gas do plants absorb?',
            'bn': 'গাছ কোন গ্যাস গ্রহণ করে?',
            'hi': 'पौधे कौन सी गैस लेते हैं?',
          },
          'options': [
            {'en': 'Oxygen', 'bn': 'অক্সিজেন', 'hi': 'ऑक्सीजन'},
            {'en': 'Carbon dioxide', 'bn': 'কার্বন ডাইঅক্সাইড', 'hi': 'कार्बन डाइऑक्साइड'},
          ],
          'correct_index': 1,
          'explanation': {'en': 'Photosynthesis uses CO2.'},
          'points': 10,
          'time_limit_sec': 15,
        };

    test('question text follows the app language', () {
      final q = QuestionModel.fromJson(sampleQuestion());

      S.load('en');
      expect(q.question, 'Which gas do plants absorb?');
      expect(q.options[1], 'Carbon dioxide');

      S.load('bn');
      expect(q.question, 'গাছ কোন গ্যাস গ্রহণ করে?');
      expect(q.options[1], 'কার্বন ডাইঅক্সাইড');

      S.load('hi');
      expect(q.question, 'पौधे कौन सी गैस लेते हैं?');
      expect(q.correctAnswer, 'कार्बन डाइऑक्साइड');
    });

    test('a missing language falls back to English, never to blank', () {
      final q = QuestionModel.fromJson(sampleQuestion());

      // The explanation was only authored in English.
      S.load('bn');
      expect(q.explanation, 'Photosynthesis uses CO2.');
      S.load('hi');
      expect(q.explanation, 'Photosynthesis uses CO2.');
    });

    test('a bare string is accepted as English-only shorthand', () {
      final text = LocalizedText.fromJson('Plain English');
      expect(text.resolve('bn'), 'Plain English');
      expect(text.has('bn'), isFalse);
      expect(text.has('en'), isTrue);
    });

    test('empty and null content resolve to an empty string', () {
      expect(LocalizedText.fromJson(null).resolve('en'), '');
      expect(LocalizedText.fromJson('').isEmpty, isTrue);
      expect(LocalizedText.fromJson({'en': '   '}).isEmpty, isTrue);
    });

    test('translation completeness is reported per question', () {
      final complete = QuestionModel.fromJson(sampleQuestion());
      expect(complete.isFullyTranslated, isTrue);
      expect(complete.missingLanguages, isEmpty);

      final partial = QuestionModel.fromJson({
        ...sampleQuestion(),
        'question': {'en': 'Only English here'},
      });
      expect(partial.isFullyTranslated, isFalse);
      expect(partial.missingLanguages, containsAll(<String>['bn', 'hi']));
    });

    test('toJson round-trips every language, not just the visible one', () {
      final original = QuestionModel.fromJson(sampleQuestion());
      final restored = QuestionModel.fromJson(original.toJson());

      S.load('hi');
      expect(restored.question, original.question);
      expect(restored.options, original.options);
      expect(restored.correctIndex, 1);
      expect(restored.isFullyTranslated, isTrue);
    });
  });
}
