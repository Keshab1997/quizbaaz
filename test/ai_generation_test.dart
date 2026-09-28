import 'package:flutter_test/flutter_test.dart';
import 'package:quizbaaz/data/services/ai_question_generator.dart';
import 'package:quizbaaz/data/services/question_fingerprint.dart';
import 'package:quizbaaz/data/services/question_prompt_builder.dart';
import 'package:quizbaaz/data/services/question_validator.dart';
import 'package:quizbaaz/data/models/chapter_model.dart';
import 'package:quizbaaz/data/models/localized_text.dart';

/// A well-formed single-question response, as the prompt asks for it.
const _goodResponse = '''
[
  {
    "id": "math_ch1_q001",
    "question": {
      "en": "What is the HCF of 96 and 404?",
      "bn": "৯৬ এবং ৪০৪-এর গ.সা.গু. কত?",
      "hi": "96 और 404 का म.स.प. क्या है?"
    },
    "options": [
      {"en": "2",  "bn": "২",  "hi": "2"},
      {"en": "4",  "bn": "৪",  "hi": "4"},
      {"en": "8",  "bn": "৮",  "hi": "8"},
      {"en": "16", "bn": "১৬", "hi": "16"}
    ],
    "correct_index": 1,
    "explanation": {
      "en": "Euclid's algorithm gives 4 as the highest common factor.",
      "bn": "ইউক্লিডের পদ্ধতিতে গ.সা.গু. ৪ পাওয়া যায়।",
      "hi": "यूक्लिड एल्गोरिथ्म से म.स.प. 4 प्राप्त होता है।"
    },
    "points": 10,
    "time_limit_sec": 15
  }
]
''';

void main() {
  group('parsing what models actually return', () {
    test('clean JSON array', () {
      final parsed = parseGeneratedQuestions(_goodResponse);
      expect(parsed, hasLength(1));
      expect(parsed.first.correctIndex, 1);
      expect(parsed.first.optionsIn('bn')[1], '৪');
    });

    test('wrapped in a markdown fence', () {
      final parsed = parseGeneratedQuestions('```json\n$_goodResponse\n```');
      expect(parsed, hasLength(1));
    });

    test('fence with no language tag', () {
      final parsed = parseGeneratedQuestions('```\n$_goodResponse\n```');
      expect(parsed, hasLength(1));
    });

    test('prose before and after the array', () {
      final parsed = parseGeneratedQuestions(
        'Sure! Here are your questions:\n\n$_goodResponse\n\n'
        'Let me know if you want more.',
      );
      expect(parsed, hasLength(1));
    });

    test('a bare object instead of an array', () {
      final single = _goodResponse.trim();
      final inner = single.substring(1, single.length - 1);
      expect(parseGeneratedQuestions(inner), hasLength(1));
    });

    test('truncated JSON yields nothing rather than a half question', () {
      final truncated = _goodResponse.substring(0, _goodResponse.length ~/ 2);
      expect(parseGeneratedQuestions(truncated), isEmpty);
    });

    test('an apology instead of JSON', () {
      expect(
        parseGeneratedQuestions("I'm sorry, I can't help with that request."),
        isEmpty,
      );
    });

    test('empty response', () {
      expect(parseGeneratedQuestions(''), isEmpty);
      expect(parseGeneratedQuestions('   \n  '), isEmpty);
    });

    test('a malformed entry is skipped, valid siblings survive', () {
      const mixed = '''
[
  {"id": "q1", "question": "Only English", "options": [], "correct_index": 0},
  {
    "id": "q2",
    "question": {"en": "Real", "bn": "বাস্তব", "hi": "वास्तविक"},
    "options": [
      {"en": "A", "bn": "ক", "hi": "अ"},
      {"en": "B", "bn": "খ", "hi": "ब"}
    ],
    "correct_index": 0
  }
]
''';
      final parsed = parseGeneratedQuestions(mixed);
      expect(parsed, hasLength(2),
          reason: 'both parse; the validator is what rejects the bad one');

      final results = QuestionValidator.validateBatch(parsed);
      expect(results[0].isAcceptable, isFalse,
          reason: 'no options and no translations');
      expect(results[1].isAcceptable, isTrue);
    });
  });

  group('the validator catches what the parser lets through', () {
    ChapterModel chapter() => const ChapterModel(
          chapterId: 'math_ch_01',
          chapterNumber: 1,
          titleText: LocalizedText({'en': 'Real Numbers'}),
          descriptionText: LocalizedText.empty(),
          totalQuestions: 0,
          jsonFile: 'assets/data/questions/class10_math_ch1.json',
          isUnlocked: true,
          stars: 0,
          bestScore: 0,
        );

    test('a model that drops Hindi on the last option', () {
      // The exact drift that motivated generating in chunks of five.
      const response = '''
[
  {
    "id": "q1",
    "question": {"en": "Pick one", "bn": "একটি বাছুন", "hi": "एक चुनें"},
    "options": [
      {"en": "Alpha", "bn": "আলফা", "hi": "अल्फा"},
      {"en": "Beta", "bn": "বিটা", "hi": "बीटा"},
      {"en": "Gamma", "bn": "গামা", "hi": "गामा"},
      {"en": "Delta", "bn": "ডেল্টা"}
    ],
    "correct_index": 0
  }
]
''';
      final parsed = parseGeneratedQuestions(response);
      final result = QuestionValidator.validate(parsed.first);
      expect(result.isAcceptable, isFalse);
      expect(result.summary, contains('hi'));
    });

    test('an index pointing past the options', () {
      const response = '''
[
  {
    "id": "q1",
    "question": {"en": "Pick one", "bn": "একটি বাছুন", "hi": "एक चुनें"},
    "options": [
      {"en": "Alpha", "bn": "আলফা", "hi": "अल्फा"},
      {"en": "Beta", "bn": "বিটা", "hi": "बीटा"}
    ],
    "correct_index": 3
  }
]
''';
      final result =
          QuestionValidator.validate(parseGeneratedQuestions(response).first);
      expect(result.isAcceptable, isFalse);
      expect(result.summary, contains('correct_index'));
    });

    test('chapter context reaches the prompt', () {
      final prompt = QuestionPromptBuilder.buildGenerationPrompt(
        chapter: chapter(),
        subjectName: 'Mathematics',
        count: 5,
        idPrefix: 'math_ch_01',
        startSequence: 41,
      );

      expect(prompt, contains('Real Numbers'));
      expect(prompt, contains('Mathematics'));
      expect(prompt, contains('West Bengal'));
      expect(prompt, contains('math_ch_01_q041'),
          reason: 'ids must continue from the existing bank');
      expect(prompt, contains('math_ch_01_q045'));
      expect(prompt, contains('"correct_index"'));
    });

    test('existing stems are sent as do-not-repeat', () {
      final prompt = QuestionPromptBuilder.buildGenerationPrompt(
        chapter: chapter(),
        subjectName: 'Mathematics',
        count: 3,
        idPrefix: 'math_ch_01',
        startSequence: 1,
        existingStems: const ['What is the HCF of 96 and 404?'],
      );
      expect(prompt, contains('ALREADY IN THIS CHAPTER'));
      expect(prompt, contains('What is the HCF of 96 and 404?'));
    });

    test('a very long chapter does not send every stem', () {
      final many = List.generate(400, (i) => 'Existing question $i?');
      final prompt = QuestionPromptBuilder.buildGenerationPrompt(
        chapter: chapter(),
        subjectName: 'Mathematics',
        count: 5,
        idPrefix: 'math_ch_01',
        startSequence: 401,
        existingStems: many,
      );

      // Capped, and it keeps the most recent — those are what a model is most
      // likely to reproduce.
      expect(prompt.contains('Existing question 399?'), isTrue);
      expect(prompt.contains('Existing question 0?'), isFalse);
    });

    test('difficulty reaches the prompt', () {
      final harder = QuestionPromptBuilder.buildGenerationPrompt(
        chapter: chapter(),
        subjectName: 'Mathematics',
        count: 5,
        idPrefix: 'math_ch_01',
        startSequence: 1,
        difficulty: DifficultyMix.harder,
      );
      expect(harder, contains('40% hard'));
    });

    test('the verification prompt marks the answer under review', () {
      final prompt = QuestionPromptBuilder.buildVerificationPrompt(
        questionEn: 'What is the HCF of 96 and 404?',
        optionsEn: const ['2', '4', '8', '16'],
        markedIndex: 1,
        explanationEn: 'Euclid gives 4.',
      );
      expect(prompt, contains('[1] 4 <-- marked correct'));
      expect(prompt, contains('"verdict"'));
    });
  });

  group('generated ids continue the chapter', () {
    test('a batch numbers on from the highest existing id', () {
      // The generator renumbers whatever the model returns, because models
      // routinely restart at q001 and a clash would overwrite a live question.
      final existing = ['math_ch_01_q001', 'math_ch_01_q040'];
      final next = QuestionFingerprint.nextSequence(existing);
      expect(next, 41);

      final ids = List.generate(
          10, (i) => QuestionFingerprint.buildId('math_ch_01', next + i));
      expect(ids.first, 'math_ch_01_q041');
      expect(ids.last, 'math_ch_01_q050');
      expect(ids.toSet().intersection(existing.toSet()), isEmpty,
          reason: 'a generated id must never collide with an existing one');
    });
  });
}
