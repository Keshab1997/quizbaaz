import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:quizbaaz/data/services/hive_service.dart';
import 'package:quizbaaz/data/models/localized_text.dart';
import 'package:quizbaaz/data/models/question_model.dart';
import 'package:quizbaaz/data/providers/quiz_provider.dart';
import 'package:quizbaaz/data/providers/user_provider.dart';
import 'package:quizbaaz/data/repositories/quiz_repository.dart';

class _ControlledQuizRepository extends QuizRepository {
  _ControlledQuizRepository({this.chapterQuestions});

  final Future<List<QuestionModel>>? chapterQuestions;

  @override
  Future<List<QuestionModel>> getChapterQuestions(
    String jsonFilePath, {
    String? chapterId,
    bool forceRefresh = false,
  }) =>
      chapterQuestions ?? Future<List<QuestionModel>>.value(const []);
}

QuestionModel _question(String id) => QuestionModel(
      id: id,
      questionText: const LocalizedText({'en': 'Which option is correct?'}),
      optionTexts: const [
        LocalizedText({'en': 'First'}),
        LocalizedText({'en': 'Second'}),
      ],
      correctIndex: 0,
    );

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('quizbaaz_lifecycle_test_');
    Hive.init(tempDir.path);
    // QuizProvider.startChapterQuiz plays a sound and reads its settings from
    // Hive, so the box has to exist before a run can start.
    await HiveService.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('quitting while a chapter is loading ignores its late result', () async {
    final result = Completer<List<QuestionModel>>();
    final quiz = QuizProvider(
      UserProvider(),
      repository: _ControlledQuizRepository(chapterQuestions: result.future),
    );

    final starting = quiz.startChapterQuiz('ignored.json', chapterId: 'chapter');
    expect(quiz.isLoading, isTrue);

    quiz.quitQuiz();
    result.complete([_question('late-question')]);
    await starting;

    expect(quiz.isLoading, isFalse);
    expect(quiz.questions, isEmpty);
    expect(quiz.currentQuestion, isNull);
    expect(quiz.isQuizCompleted, isFalse);
  });

  test('abandoning after an answer prevents delayed auto-advance', () async {
    final quiz = QuizProvider(
      UserProvider(),
      repository: _ControlledQuizRepository(
        chapterQuestions: Future<List<QuestionModel>>.value([
          _question('first'),
          _question('second'),
        ]),
      ),
    );
    await quiz.startChapterQuiz('ignored.json', chapterId: 'chapter');

    quiz.selectOption(quiz.currentQuestion!.correctIndex);
    expect(quiz.isAnswerSubmitted, isTrue);

    quiz.quitQuiz();
    await Future<void>.delayed(const Duration(milliseconds: 1900));

    // The delayed auto-advance that was already scheduled must not move the
    // player on, and the run must never be scored as completed.
    expect(quiz.isAbandoned, isTrue);
    expect(quiz.currentIndex, 0);
    expect(quiz.isQuizCompleted, isFalse);
  });
}
