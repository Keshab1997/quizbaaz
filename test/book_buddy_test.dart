import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quizbaaz/data/providers/book_buddy_provider.dart';
import 'package:quizbaaz/data/providers/quiz_provider.dart';
import 'package:quizbaaz/data/providers/user_provider.dart';
import 'package:quizbaaz/data/services/book_buddy_service.dart';
import 'package:quizbaaz/data/services/hive_service.dart';
import 'package:quizbaaz/l10n/app_strings.dart';
import 'package:quizbaaz/presentation/widgets/book_markdown_view.dart';
import 'package:smart_ocr_ai_bridge/smart_ocr_ai_bridge.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('quizbaaz_book_buddy_');
    Hive.init(tempDir.path);
    await HiveService.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveService.clearBookStudySessions();
  });

  test(
    'scans textbook page via SmartOcrAiBridge, asks follow-up, generates MCQs, and persists in Hive',
    () async {
      final extractor = MultilingualOcrExtractor(
        tempDirOverride: tempDir,
        scriptRunner: (script, _) async {
          if (script == OcrScript.latin) {
            return const ScriptOcrPass(
              text:
                  'Chapter 3: Photosynthesis\nPlants convert sunlight, water, and CO2 into glucose and oxygen inside chloroplasts.',
            );
          }
          return const ScriptOcrPass(text: '');
        },
      );

      var requestCount = 0;
      final mockHttp = MockClient((http.Request request) async {
        requestCount++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final messages = body['messages'] as List<dynamic>;
        final userText =
            (messages.last as Map<String, dynamic>)['content'].toString();

        if (userText.contains('Create exactly 3 multiple-choice questions')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': jsonEncode({
                        'questions': [
                          {
                            'question': 'কোথায় সালোকসংশ্লেষ ঘটে?',
                            'options': [
                              'ক্লোরোপ্লাস্ট',
                              'মাইটোকন্ড্রিয়া',
                              'রাইবোজোম',
                              'নিউক্লিয়াস',
                            ],
                            'correct_index': 0,
                            'explanation':
                                'ক্লোরোপ্লাস্টের ভেতরে সালোকসংশ্লেষ প্রক্রিয়া সম্পন্ন হয়।',
                          },
                          {
                            'question': 'সালোকসংশ্লেষে কোন গ্যাস নির্গত হয়?',
                            'options': [
                              'অক্সিজেন',
                              'কার্বন ডাই-অক্সাইড',
                              'নাইট্রোজেন',
                              'হাইড্রোজেন',
                            ],
                            'correct_index': 0,
                            'explanation':
                                'উদ্ভিদ উপজাত হিসেবে অক্সিজেন ছাড়ে।',
                          },
                          {
                            'question': 'সালোকসংশ্লেষে উৎপন্ন খাদ্য কোনটি?',
                            'options': ['গ্লুকোজ', 'প্রোটিন', 'ফ্যাট', 'লবণ'],
                            'correct_index': 0,
                            'explanation': 'গ্লুকোজ তৈরি হয়।',
                          },
                        ],
                      }),
                    },
                  },
                ],
              }),
            ),
            200,
          );
        }

        if (userText.contains('ক্লোরোফিল কী?')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content':
                          'ক্লোরোফিল হলো পাতায় থাকা সবুজ রঞ্জক যা সূর্যালোক শোষণ করে।',
                    },
                  },
                ],
              }),
            ),
            200,
          );
        }

        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content':
                        'TITLE: সালোকসংশ্লেষ (Photosynthesis)\n\nসূর্যালোক ও জলের সাহায্যে উদ্ভিদ নিজের খাদ্য তৈরি করে।',
                  },
                },
              ],
            }),
          ),
          200,
        );
      });

      final bridge = SmartOcrAiBridge(
        keyPool: KeyPoolAdapter.fromStaticKeys(const [
          BridgeApiKey(
            id: 'test-key-1',
            name: 'Test Key',
            key: 'sk-test',
            baseUrl: 'https://openrouter.ai/api/v1',
            model: 'openai/gpt-4o-mini',
            provider: 'openrouter',
          ),
        ]),
        ocrExtractor: extractor,
        httpClient: mockHttp,
      );

      final provider = BookBuddyProvider(
        service: BookBuddyService(bridge: bridge),
      );
      addTearDown(provider.dispose);

      // 1. Scan & explain page (text-only route because OCR score >= 20)
      final scanned = await provider.scanBookPage(
        imageBytes: Uint8List.fromList([1, 2, 3, 4]),
        languageCode: 'bn',
        defaultTitle: 'বইয়ের পাতা',
        initialQuestionLabel: 'বইয়ের পাতাটি বুঝিয়ে দাও',
      );

      expect(scanned, isTrue, reason: provider.errorMessage);
      expect(provider.activeSession, isNotNull);
      expect(
        provider.activeSession!.title,
        equals('সালোকসংশ্লেষ (Photosynthesis)'),
      );
      expect(provider.activeSession!.usedVisionFallback, isFalse);
      expect(provider.activeSession!.turns.length, equals(1));

      // 2. Ask follow-up question (reuses compacted OCR text)
      final asked = await provider.askQuestion(
        question: 'ক্লোরোফিল কী?',
        languageCode: 'bn',
      );
      expect(asked, isTrue);
      expect(provider.activeSession!.turns.length, equals(2));
      expect(provider.activeSession!.turns.last.answer, contains('সবুজ রঞ্জক'));

      // 3. Generate practice MCQs
      final mcqs = await provider.generateMcqs(languageCode: 'bn', count: 3);
      expect(mcqs.length, equals(3));
      expect(mcqs.first.optionsIn('bn').length, equals(4));

      // 4. Verify Hive persistence
      final reloaded = HiveService.loadBookStudySessions();
      expect(reloaded.length, equals(1));
      expect(reloaded.first.generatedMcqs.length, equals(3));
      expect(requestCount, equals(3));
    },
  );

  test(
    'QuizProvider.startCustomPracticeQuiz plays generated MCQs in unranked practice mode (0 coins/gems)',
    () async {
      final mcqs = BookBuddyService.parseGeneratedMcqs(
        {
          'questions': [
            {
              'question': 'What is H2O?',
              'options': ['Water', 'Oxygen', 'Salt', 'Acid'],
              'correct_index': 0,
              'explanation': 'H2O is the chemical formula of water.',
            },
          ],
        },
        languageCode: 'en',
        idPrefix: 'bb_test',
      );

      final userProvider = UserProvider();
      await userProvider.initialize();
      final initialCoins = userProvider.user.coins;
      final initialGems = userProvider.user.gems;

      final quiz = QuizProvider(userProvider);
      addTearDown(() {
        quiz.quitQuiz();
        quiz.dispose();
        userProvider.dispose();
      });

      await quiz.startCustomPracticeQuiz(mcqs, title: 'Chemistry Page');

      expect(quiz.isPractice, isTrue);
      expect(quiz.isCustomPractice, isTrue);
      expect(quiz.isDailyQuiz, isFalse);
      expect(quiz.questions.length, equals(1));

      final correctIdx = quiz.currentQuestion!.correctIndex;
      quiz.selectOption(correctIdx);
      quiz.nextQuestion();

      expect(quiz.isQuizCompleted, isTrue);
      expect(quiz.earnedCoins, equals(0));
      expect(quiz.earnedGems, equals(0));
      expect(userProvider.user.coins, equals(initialCoins));
      expect(userProvider.user.gems, equals(initialGems));
    },
  );

  test(
    'replyLanguage and textScale persist independently of app S.code',
    () async {
      S.load('en'); // App UI is in English
      await HiveService.setMeta(HiveService.metaBookBuddyLanguage, null);

      final provider = BookBuddyProvider(
        service: BookBuddyService(
          bridge: SmartOcrAiBridge(
            keyPool: KeyPoolAdapter.fromStaticKeys(const []),
          ),
        ),
      );
      addTearDown(provider.dispose);

      // Student switches AI reply language to Bengali while app stays English
      await provider.setReplyLanguage('bn');
      expect(provider.replyLanguage, equals('bn'));
      expect(
        HiveService.getMeta<String>(HiveService.metaBookBuddyLanguage),
        equals('bn'),
      );

      await provider.adjustTextScale(0.1);
      expect(
        provider.textScale,
        closeTo(BookBuddyProvider.defaultTextScale + 0.1, 0.01),
      );

      // Generated Bengali MCQs still show Bengali text even when S.code == 'en'
      final mcqs = BookBuddyService.parseGeneratedMcqs({
        'questions': [
          {
            'question': 'শক্তির একক কী?',
            'options': ['জুল', 'ওয়াট', 'নিউটন', 'পাস্কাল'],
            'correct_index': 0,
            'explanation': 'শক্তির SI একক জুল।',
          },
        ],
      }, languageCode: 'bn');
      expect(mcqs.first.question, equals('শক্তির একক কী?'));
    },
  );

  testWidgets(
    'BookMarkdownView renders tables, headings, and callouts without raw syntax',
    (WidgetTester tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;

      const sampleMarkdown = '''
## ১. শক্তির রূপান্তর (Energy Transformation)

| ঘটনা | শক্তির রূপান্তর |
|------|-----------------|
| পটকা ফাটালে শব্দ হয় | রাসায়নিক শক্তি → শব্দশক্তি |

**মূল কথা:** শক্তি নষ্ট হয় না, শুধু এক রূপ থেকে অন্য রূপে পরিবর্তিত হয়।
''';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BookMarkdownView(
                markdown: sampleMarkdown,
                languageCode: 'bn',
                textScale: 1.15,
              ),
            ),
          ),
        ),
      );

      expect(
        find.text('১. শক্তির রূপান্তর (Energy Transformation)'),
        findsOneWidget,
      );
      expect(find.text('ঘটনা'), findsOneWidget);
      expect(find.text('রাসায়নিক শক্তি → শব্দশক্তি'), findsOneWidget);
      expect(find.textContaining('##'), findsNothing);
      expect(find.textContaining('|---'), findsNothing);
    },
  );
}
