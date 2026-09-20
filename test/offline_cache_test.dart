import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:quizbaaz/data/models/question_model.dart';
import 'package:quizbaaz/data/repositories/quiz_repository.dart';
import 'package:quizbaaz/data/services/hive_service.dart';
import 'package:quizbaaz/data/services/question_bank_service.dart';

/// Offline behaviour of the question cache.
///
/// A student on a 2G connection loses the network constantly. Before this,
/// `cacheGet(..., maxAge: 15min)` returned `null` the moment the entry aged
/// out, so a chapter that was playable a minute ago became "no questions here"
/// — and the bundled banks were empty, so there was nothing to fall back to.
///
/// Now an old entry is still served and a refresh is attempted in the
/// background. These tests pin that down.
class _OfflineBankService extends QuestionBankService {
  /// Every network path here is dead — exactly like an offline device.
  @override
  Future<List<QuestionModel>> fetchQuestions(String chapterId) async => const [];

  @override
  Future<Map<String, int>> fetchQuestionCounts() async => const {};
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('quizbaaz_offline_test_');
    Hive.init(tempDir.path);
    await HiveService.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('HiveService TTL cache', () {
    test('a fresh entry is served and reported fresh', () async {
      await HiveService.cachePut('offline_fresh', [
        {'id': 'q1'},
        {'id': 'q2'},
      ]);

      expect(
        HiveService.cacheGetList('offline_fresh',
            maxAge: const Duration(minutes: 15)),
        hasLength(2),
      );
      expect(
        HiveService.isCacheFresh('offline_fresh', const Duration(minutes: 15)),
        isTrue,
      );
    });

    test('an aged entry is hidden by maxAge but revealed by allowStale',
        () async {
      await HiveService.cachePut('offline_stale', [
        {'id': 'q1'},
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      const window = Duration(milliseconds: 10);

      // The old behaviour: gone the moment it aged out.
      expect(HiveService.cacheGetList('offline_stale', maxAge: window), isEmpty);
      expect(HiveService.isCacheFresh('offline_stale', window), isFalse);

      // The new behaviour: still there for the student.
      expect(
        HiveService.cacheGetList('offline_stale', maxAge: window, allowStale: true),
        hasLength(1),
      );
      expect(HiveService.cacheAge('offline_stale'), isNotNull);
    });

    test('a missing key is empty, not an error', () {
      expect(HiveService.cacheGetList('offline_never_written',
          maxAge: const Duration(seconds: 1), allowStale: true), isEmpty);
      expect(HiveService.cacheAge('offline_never_written'), isNull);
      expect(HiveService.isCacheFresh('offline_never_written', const Duration(days: 1)),
          isFalse);
    });

    test('a value that is not a list decodes to an empty list', () async {
      await HiveService.cachePut('offline_not_a_list', {'id': 'q1'});
      expect(HiveService.cacheGetList('offline_not_a_list', allowStale: true),
          isEmpty);
    });
  });

  group('QuizRepository serves a stale chapter offline', () {
    test('questions come from an aged cache instead of the network', () async {
      const path = 'assets/data/questions/offline_test_chapter.json';
      const cacheKey = 'chapter_questions:$path';

      final question = QuestionModel.fromJson({
        'id': 'offline_q1',
        'question': {'en': 'Which gas do plants absorb?', 'bn': 'গাছ কোন গ্যাস নেয়?', 'hi': 'पौधे कौन-सी गैस लेते हैं?'},
        'options': [
          {'en': 'Carbon dioxide', 'bn': 'কার্বন ডাই-অক্সাইড', 'hi': 'कार्बन डाइऑक्साइड'},
          {'en': 'Oxygen', 'bn': 'অক্সিজেন', 'hi': 'ऑक्सीजन'},
        ],
        'correct_index': 0,
        'explanation': {'en': 'Photosynthesis.', 'bn': 'সালোকসংশ্লেষ।', 'hi': 'प्रकाश संश्लेषण।'},
      });

      await HiveService.cachePut(cacheKey, [question.toJson()]);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final repository = QuizRepository(bankService: _OfflineBankService());
      final rows = await repository.getChapterQuestions(
        path,
        chapterId: 'offline_test_chapter',
      );

      expect(rows, hasLength(1));
      expect(rows.single.id, 'offline_q1');
      expect(rows.single.optionsIn('en'), contains('Carbon dioxide'));

      // The refresh was attempted (and, offline, quietly failed) — the student
      // still got their questions, which is the whole point.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(QuizRepository.isRevalidating(cacheKey), isFalse);
    });

    test('a disabled chapter stays hidden when served from cache', () async {
      // Guards the one thing a stale read must not break: chapter visibility.
      final categories = [
        {
          'category_id': 'cat_test',
          'category_name': {'en': 'Test', 'bn': 'পরীক্ষা', 'hi': 'परीक्षण'},
          'category_icon': '',
          'color_hex': '#FFFFFF',
          'chapters': [
            {
              'chapter_id': 'hidden_chapter',
              'chapter_number': 1,
              'title': {'en': 'Hidden', 'bn': 'লুকানো', 'hi': 'छिपा'},
              'total_questions': 5,
              'json_file': 'assets/data/questions/offline_test_chapter.json',
              'is_enabled': false,
            },
          ],
        },
      ];

      await HiveService.cachePut(HiveService.cacheChapters, categories);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final repository = QuizRepository(bankService: _OfflineBankService());
      final visible = await repository.getCategoriesAndChapters();
      expect(visible, isEmpty, reason: 'a disabled chapter must stay hidden');

      final adminView =
          await repository.getCategoriesAndChapters(includeDisabled: true);
      expect(adminView, hasLength(1));
      expect(adminView.single.chapters, hasLength(1));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(QuizRepository.isRevalidating(HiveService.cacheChapters), isFalse);
    });
  });
}
