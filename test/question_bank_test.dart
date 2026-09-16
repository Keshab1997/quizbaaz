import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizbaaz/data/models/chapter_model.dart';
import 'package:quizbaaz/data/models/chapter_set_progress.dart';
import 'package:quizbaaz/data/models/localized_text.dart';
import 'package:quizbaaz/data/models/question_model.dart';
import 'package:quizbaaz/data/models/question_set.dart';
import 'package:quizbaaz/data/repositories/quiz_repository.dart';
import 'package:quizbaaz/data/services/chapter_catalog_service.dart';
import 'package:quizbaaz/data/services/question_fingerprint.dart';
import 'package:quizbaaz/data/services/question_validator.dart';

/// Builds a valid trilingual question, with individual pieces overridable so a
/// test can break exactly one rule at a time.
QuestionModel buildQuestion({
  String id = 'math_ch1_q001',
  Map<String, String>? question,
  List<Map<String, String>>? options,
  int correctIndex = 1,
  Map<String, String>? explanation,
  int points = 10,
  int timeLimitSec = 15,
}) {
  return QuestionModel(
    id: id,
    questionText: LocalizedText(question ??
        const {
          'en': 'What is the HCF of 96 and 404?',
          'bn': '৯৬ এবং ৪০৪-এর গ.সা.গু. কত?',
          'hi': '96 और 404 का म.स.प. क्या है?',
        }),
    optionTexts: (options ??
            const [
              {'en': 'Two', 'bn': 'দুই', 'hi': 'दो'},
              {'en': 'Four', 'bn': 'চার', 'hi': 'चार'},
              {'en': 'Eight', 'bn': 'আট', 'hi': 'आठ'},
              {'en': 'Sixteen', 'bn': 'ষোলো', 'hi': 'सोलह'},
            ])
        .map(LocalizedText.new)
        .toList(),
    correctIndex: correctIndex,
    explanationText: LocalizedText(explanation ??
        const {
          'en': 'Euclid division gives 4 as the highest common factor.',
          'bn': 'ইউক্লিডের বিভাজন অনুসারে গ.সা.গু. ৪।',
          'hi': 'यूक्लिड विभाजन से म.स.प. 4 प्राप्त होता है।',
        }),
    points: points,
    timeLimitSec: timeLimitSec,
  );
}

void main() {
  group('QuestionFingerprint.normalise', () {
    test('ignores case, punctuation and spacing', () {
      const a = 'What is the HCF of 96 and 404?';
      const b = '  what   is the hcf of 96 and 404  ';
      expect(QuestionFingerprint.normalise(a),
          QuestionFingerprint.normalise(b));
    });

    test('keeps digits — different numbers are different questions', () {
      expect(
        QuestionFingerprint.fingerprint('Find the HCF of 96 and 404'),
        isNot(QuestionFingerprint.fingerprint('Find the HCF of 18 and 24')),
      );
    });

    test('preserves non-Latin scripts', () {
      final normalised =
          QuestionFingerprint.normalise('গ.সা.গু. কত? — ৯৬ ও ৪০৪');
      expect(normalised, contains('গ'));
      expect(normalised, contains('৯৬'));
      expect(normalised, isNot(contains('.')));
    });

    test('an empty stem has no fingerprint', () {
      expect(QuestionFingerprint.fingerprint('   '), '');
    });
  });

  group('QuestionFingerprint.similarity', () {
    test('rephrasings of the same question score high', () {
      final score = QuestionFingerprint.similarity(
        'What is the HCF of 96 and 404?',
        'Find the HCF of 96 and 404.',
      );
      expect(score, greaterThanOrEqualTo(0.85));
    });

    test('different questions in the same topic score low', () {
      final score = QuestionFingerprint.similarity(
        'What is the HCF of 96 and 404?',
        'State the fundamental theorem of arithmetic.',
      );
      expect(score, lessThan(0.4));
    });

    test('findNearDuplicate reports the closest match above the threshold', () {
      final match = QuestionFingerprint.findNearDuplicate(
        'Find the HCF of 96 and 404.',
        {
          'math_ch1_q014': 'What is the HCF of 96 and 404?',
          'math_ch1_q020': 'Define an irrational number.',
        },
      );
      expect(match, isNotNull);
      expect(match!.questionId, 'math_ch1_q014');
    });

    test('returns null when nothing is close', () {
      expect(
        QuestionFingerprint.findNearDuplicate(
            'Define an irrational number.', {'q1': 'What is 2 plus 2?'}),
        isNull,
      );
    });
  });

  group('QuestionFingerprint.nextSequence', () {
    test('continues from the highest id, not the count', () {
      // The gap matters: q002 was deleted. Reusing 3 would overwrite q003.
      expect(
        QuestionFingerprint.nextSequence(
            ['math_ch1_q001', 'math_ch1_q003', 'math_ch1_q004']),
        5,
      );
    });

    test('starts at 1 for an empty chapter', () {
      expect(QuestionFingerprint.nextSequence(const []), 1);
    });

    test('ignores ids that do not follow the convention', () {
      expect(
        QuestionFingerprint.nextSequence(['legacy-question', 'math_ch1_q007']),
        8,
      );
    });

    test('builds zero-padded ids', () {
      expect(QuestionFingerprint.buildId('math_ch1', 42), 'math_ch1_q042');
      expect(QuestionFingerprint.buildId('math_ch1', 7), 'math_ch1_q007');
    });
  });

  group('QuestionValidator — accepts good content', () {
    test('a complete trilingual question is clean', () {
      final result = QuestionValidator.validate(buildQuestion());
      expect(result.isAcceptable, isTrue);
      expect(result.isClean, isTrue, reason: result.summary);
    });
  });

  group('QuestionValidator — rejects what a model actually gets wrong', () {
    test('correct_index past the end of the options', () {
      final result =
          QuestionValidator.validate(buildQuestion(correctIndex: 4));
      expect(result.isAcceptable, isFalse);
      expect(result.summary, contains('correct_index'));
    });

    test('negative correct_index', () {
      expect(
        QuestionValidator.validate(buildQuestion(correctIndex: -1))
            .isAcceptable,
        isFalse,
      );
    });

    test('an option that lost a language', () {
      final result = QuestionValidator.validate(buildQuestion(options: const [
        {'en': 'Two', 'bn': 'দুই', 'hi': 'दो'},
        {'en': 'Four', 'bn': 'চার'}, // no Hindi
        {'en': 'Eight', 'bn': 'আট', 'hi': 'आठ'},
        {'en': 'Sixteen', 'bn': 'ষোলো', 'hi': 'सोलह'},
      ]));
      expect(result.isAcceptable, isFalse);
      expect(result.rejections.map((i) => i.message).join(),
          contains('missing "hi"'));
    });

    test('two options identical in one language', () {
      final result = QuestionValidator.validate(buildQuestion(options: const [
        {'en': 'Two', 'bn': 'দুই', 'hi': 'दो'},
        // Distinct in English, collapsed in Bangla — unanswerable in bn.
        {'en': 'Twice', 'bn': 'দুই', 'hi': 'दुगुना'},
        {'en': 'Eight', 'bn': 'আট', 'hi': 'आठ'},
        {'en': 'Sixteen', 'bn': 'ষোলো', 'hi': 'सोलह'},
      ]));
      expect(result.isAcceptable, isFalse);
      expect(result.rejections.map((i) => i.message).join(),
          contains('identical in "bn"'));
    });

    test('a translation that is just the English pasted back', () {
      final result = QuestionValidator.validate(buildQuestion(question: const {
        'en': 'What is the HCF of 96 and 404?',
        'bn': 'What is the HCF of 96 and 404?',
        'hi': '96 और 404 का म.स.प. क्या है?',
      }));
      expect(result.isAcceptable, isFalse);
      expect(result.summary, contains('identical to English'));
    });

    test('but identical numeric or symbolic text is allowed', () {
      // "H2O" is the same in every language; that is not a skipped translation.
      final result = QuestionValidator.validate(buildQuestion(options: const [
        {'en': 'H2O', 'bn': 'H2O', 'hi': 'H2O'},
        {'en': 'CO2', 'bn': 'CO2', 'hi': 'CO2'},
        {'en': 'NaCl', 'bn': 'NaCl', 'hi': 'NaCl'},
        {'en': 'O2', 'bn': 'O2', 'hi': 'O2'},
      ]));
      expect(result.isAcceptable, isTrue, reason: result.summary);
    });

    test('a single technical term kept in English is allowed', () {
      // The authoring guide says a term may stay in English when that is what
      // the classroom uses. Only multi-word prose counts as untranslated.
      final result = QuestionValidator.validate(buildQuestion(options: const [
        {'en': 'Router', 'bn': 'Router', 'hi': 'Router'},
        {'en': 'Switch', 'bn': 'Switch', 'hi': 'Switch'},
        {'en': 'Modem', 'bn': 'মডেম', 'hi': 'मॉडेम'},
        {'en': 'Hub', 'bn': 'হাব', 'hi': 'हब'},
      ]));
      expect(result.isAcceptable, isTrue, reason: result.summary);
    });

    test('too few options', () {
      final result = QuestionValidator.validate(buildQuestion(
        options: const [
          {'en': 'Yes', 'bn': 'হ্যাঁ', 'hi': 'हाँ'},
        ],
        correctIndex: 0,
      ));
      expect(result.isAcceptable, isFalse);
    });

    test('three options are allowed but warned about', () {
      final result = QuestionValidator.validate(buildQuestion(
        options: const [
          {'en': 'Two', 'bn': 'দুই', 'hi': 'दो'},
          {'en': 'Four', 'bn': 'চার', 'hi': 'चार'},
          {'en': 'Eight', 'bn': 'আট', 'hi': 'आठ'},
        ],
      ));
      expect(result.isAcceptable, isTrue);
      expect(result.warnings, isNotEmpty);
    });

    test('an empty stem', () {
      final result =
          QuestionValidator.validate(buildQuestion(question: const {}));
      expect(result.isAcceptable, isFalse);
    });

    test('out-of-range points and time limit', () {
      expect(QuestionValidator.validate(buildQuestion(points: 0)).isAcceptable,
          isFalse);
      expect(
        QuestionValidator.validate(buildQuestion(timeLimitSec: 2)).isAcceptable,
        isFalse,
      );
    });

    test('a missing explanation is a warning, not a rejection', () {
      final result =
          QuestionValidator.validate(buildQuestion(explanation: const {}));
      expect(result.isAcceptable, isTrue);
      expect(result.warnings, isNotEmpty);
    });
  });

  group('QuestionValidator — duplicates', () {
    test('an exact duplicate is rejected', () {
      final question = buildQuestion();
      final fingerprint = QuestionFingerprint.fingerprint(
          question.questionText.resolve('en'));

      final result = QuestionValidator.validate(
        question,
        existingFingerprints: {fingerprint},
      );
      expect(result.isAcceptable, isFalse);
      expect(result.summary, contains('already in the chapter'));
    });

    test('a near-duplicate is flagged for review, not rejected', () {
      final result = QuestionValidator.validate(
        buildQuestion(question: const {
          'en': 'Find the HCF of 96 and 404.',
          'bn': '৯৬ ও ৪০৪-এর গ.সা.গু. নির্ণয় করো।',
          'hi': '96 और 404 का म.स.प. ज्ञात कीजिए।',
        }),
        existingStems: const {
          'math_ch1_q014': 'What is the HCF of 96 and 404?',
        },
      );
      expect(result.isAcceptable, isTrue,
          reason: 'a near-duplicate is a judgement call for the admin');
      expect(result.nearDuplicate, isNotNull);
      expect(result.nearDuplicate!.questionId, 'math_ch1_q014');
    });

    test('a batch cannot duplicate itself', () {
      final results = QuestionValidator.validateBatch([
        buildQuestion(id: 'math_ch1_q001'),
        buildQuestion(id: 'math_ch1_q002'), // same stem as the first
      ]);
      expect(results[0].isAcceptable, isTrue);
      expect(results[1].isAcceptable, isFalse,
          reason: 'the second copy must be caught within the same batch');
    });
  });

  group('chapter visibility', () {
    ChapterModel chapter(String id, {bool isEnabled = true}) => ChapterModel(
          chapterId: id,
          chapterNumber: 1,
          titleText: LocalizedText({'en': id}),
          descriptionText: const LocalizedText.empty(),
          totalQuestions: 10,
          jsonFile: 'assets/data/questions/$id.json',
          isUnlocked: true,
          isEnabled: isEnabled,
          stars: 0,
          bestScore: 0,
        );

    CategoryModel category(String id, List<ChapterModel> chapters) =>
        CategoryModel(
          categoryId: id,
          nameText: LocalizedText({'en': id}),
          categoryIcon: '',
          colorHex: '#000000',
          totalChapters: chapters.length,
          chapters: chapters,
        );

    test('legacy chapter data remains enabled by default', () {
      final legacy = ChapterModel.fromJson({
        'chapter_id': 'legacy',
        'chapter_number': 1,
        'title': {'en': 'Legacy chapter'},
        'description': {'en': ''},
        'total_questions': 10,
        'json_file': 'assets/data/questions/legacy.json',
        'is_unlocked': true,
      });

      expect(legacy.isEnabled, isTrue);
    });

    test('visibility value survives a chapter JSON round trip', () {
      final hidden = chapter('hidden', isEnabled: false);
      final restored = ChapterModel.fromJson(hidden.toJson());

      expect(restored.isEnabled, isFalse);
    });

    test('students see only enabled chapters and non-empty subjects', () {
      final all = [
        category('math', [
          chapter('shown'),
          chapter('hidden', isEnabled: false),
        ]),
        category('private', [chapter('also_hidden', isEnabled: false)]),
      ];

      final studentView = QuizRepository.filterForStudents(all);
      expect(studentView, hasLength(1));
      expect(studentView.single.categoryId, 'math');
      expect(studentView.single.totalChapters, 1);
      expect(studentView.single.chapters.single.chapterId, 'shown');

      final adminView =
          QuizRepository.filterForStudents(all, includeDisabled: true);
      expect(adminView, hasLength(2));
      expect(adminView.first.chapters, hasLength(2));
    });

    test('hiding a bundled chapter works through a remote shell', () {
      // Regression: bundled subjects have no Firestore document, so the hide
      // override arrives as a shell category (empty name) carrying only the
      // disabled chapter. Merging must keep the bundled subject metadata but
      // apply the disabled flag, and the student filter must drop it.
      final assets = [
        category('cat_math', [chapter('math_ch_01'), chapter('math_ch_02')]),
      ];
      final remote = [
        const CategoryModel(
          categoryId: 'cat_math',
          nameText: LocalizedText.empty(),
          categoryIcon: '',
          colorHex: '',
          totalChapters: 1,
          chapters: [],
        ),
      ];
      // Rebuild the shell with the disabled override (const cannot hold it).
      final shell = CategoryModel(
        categoryId: 'cat_math',
        nameText: const LocalizedText.empty(),
        categoryIcon: '',
        colorHex: '',
        totalChapters: 1,
        chapters: [chapter('math_ch_01', isEnabled: false)],
      );

      final merged = ChapterCatalogService.mergeWithAssets(assets, [shell]);
      expect(merged, hasLength(1));
      // Subject metadata survives the empty shell.
      expect(merged.single.categoryName, 'cat_math');
      expect(merged.single.chapters, hasLength(2));

      final hidden = merged.single.chapters
          .firstWhere((c) => c.chapterId == 'math_ch_01');
      expect(hidden.isEnabled, isFalse);
      expect(remote.single.nameText.isEmpty, isTrue);

      final studentView = QuizRepository.filterForStudents(merged);
      expect(studentView.single.chapters.map((c) => c.chapterId),
          ['math_ch_02']);

      final adminView =
          QuizRepository.filterForStudents(merged, includeDisabled: true);
      expect(adminView.single.chapters, hasLength(2));
    });
  });

  group('admin question sets', () {
    test('groups consecutive questions in sets of ten', () {
      final questions = List.generate(
        23,
        (index) => buildQuestion(id: 'q${index + 1}'),
      );

      final sets = QuestionSet.fromQuestions(questions);

      expect(sets.map((set) => set.number), [1, 2, 3]);
      expect(sets.map((set) => set.startIndex), [0, 10, 20]);
      expect(sets.map((set) => set.questions.length), [10, 10, 3]);
      expect(sets[1].questions.first.id, 'q11');
      expect(sets[2].questions.last.id, 'q23');
    });

    test('does not create an empty set', () {
      expect(QuestionSet.fromQuestions(const []), isEmpty);
    });
  });

  _setsTests();

  group('option shuffling', () {
    test('the correct answer moves with its option', () {
      final original = buildQuestion();
      final answerBefore = original.optionTexts[original.correctIndex];

      // Every seed must keep the marked answer pointing at the same text.
      for (var seed = 0; seed < 50; seed++) {
        final shuffled = original.withShuffledOptions(Random(seed));
        expect(
          shuffled.optionTexts[shuffled.correctIndex].resolve('en'),
          answerBefore.resolve('en'),
          reason: 'seed $seed moved the answer but not the index',
        );
      }
    });

    test('all options survive, none duplicated or lost', () {
      final original = buildQuestion();
      final shuffled = original.withShuffledOptions(Random(7));

      final before =
          original.optionTexts.map((o) => o.resolve('en')).toSet();
      final after = shuffled.optionTexts.map((o) => o.resolve('en')).toSet();

      expect(after, before);
      expect(shuffled.optionTexts, hasLength(original.optionTexts.length));
    });

    test('every language is permuted the same way', () {
      // If en and bn were shuffled independently, option B in Bangla would be
      // a different answer than option B in English.
      final original = buildQuestion();
      final shuffled = original.withShuffledOptions(Random(3));

      for (var i = 0; i < shuffled.optionTexts.length; i++) {
        final english = shuffled.optionsIn('en')[i];
        final originalPosition = original.optionsIn('en').indexOf(english);
        expect(shuffled.optionsIn('bn')[i],
            original.optionsIn('bn')[originalPosition]);
        expect(shuffled.optionsIn('hi')[i],
            original.optionsIn('hi')[originalPosition]);
      }
    });

    test('the answer does not sit in one place across many questions', () {
      // The point of shuffling: a student must not be able to learn "it is
      // usually B". With 200 four-option questions, no position should hold
      // more than ~40% of the answers.
      final rng = Random(42);
      final positions = <int, int>{};
      for (var i = 0; i < 200; i++) {
        final shuffled = buildQuestion().withShuffledOptions(rng);
        positions[shuffled.correctIndex] =
            (positions[shuffled.correctIndex] ?? 0) + 1;
      }

      expect(positions.keys.length, 4, reason: 'every slot should be used');
      for (final count in positions.values) {
        expect(count, lessThan(80));
        expect(count, greaterThan(20));
      }
    });

    test('a single-option question is returned untouched', () {
      final single = buildQuestion(
        options: const [
          {'en': 'Only', 'bn': 'একমাত্র', 'hi': 'केवल'},
        ],
        correctIndex: 0,
      );
      final shuffled = single.withShuffledOptions(Random(1));
      expect(shuffled.correctIndex, 0);
      expect(shuffled.optionTexts, hasLength(1));
    });

    test('shuffling does not disturb the rest of the question', () {
      final original = buildQuestion();
      final shuffled = original.withShuffledOptions(Random(11));

      expect(shuffled.id, original.id);
      expect(shuffled.questionText.resolve('bn'),
          original.questionText.resolve('bn'));
      expect(shuffled.explanationText.resolve('hi'),
          original.explanationText.resolve('hi'));
      expect(shuffled.points, original.points);
      expect(shuffled.timeLimitSec, original.timeLimitSec);
    });
  });

  group('the append guarantee', () {
    test('generating into a full chapter grows it — 40 + 10 = 50', () {
      // The failure this whole design exists to prevent: a new batch replacing
      // the chapter instead of extending it.
      final existing = List.generate(
        40,
        (i) => buildQuestion(
          id: QuestionFingerprint.buildId('math_ch1', i + 1),
          question: {
            'en': 'Existing question number ${i + 1}?',
            'bn': 'পুরোনো প্রশ্ন ${i + 1}?',
            'hi': 'पुराना प्रश्न ${i + 1}?',
          },
        ),
      );

      final nextStart =
          QuestionFingerprint.nextSequence(existing.map((q) => q.id));
      expect(nextStart, 41);

      final generated = List.generate(
        10,
        (i) => buildQuestion(
          id: QuestionFingerprint.buildId('math_ch1', nextStart + i),
          question: {
            'en': 'Newly generated question number ${i + 1}?',
            'bn': 'নতুন প্রশ্ন ${i + 1}?',
            'hi': 'नया प्रश्न ${i + 1}?',
          },
        ),
      );

      final results = QuestionValidator.validateBatch(
        generated,
        existingStems: {
          for (final q in existing) q.id: q.questionText.resolve('en'),
        },
        existingFingerprints: {
          for (final q in existing)
            QuestionFingerprint.fingerprint(q.questionText.resolve('en')),
        },
      );
      expect(results.every((r) => r.isAcceptable), isTrue,
          reason: results.map((r) => r.summary).join(' | '));

      // Appending, the way the service will: existing first, new after.
      final merged = <String, QuestionModel>{
        for (final q in existing) q.id: q,
        for (final q in generated) q.id: q,
      };

      expect(merged.length, 50);
      expect(merged.keys.toSet().length, 50, reason: 'ids must stay unique');
      for (final q in existing) {
        expect(merged.containsKey(q.id), isTrue,
            reason: '${q.id} was lost — this is the bug we must never ship');
      }
      expect(merged.containsKey('math_ch1_q041'), isTrue);
      expect(merged.containsKey('math_ch1_q050'), isTrue);
    });

    test('re-running the same batch is idempotent, not additive', () {
      final batch = List.generate(
        3,
        (i) => buildQuestion(
          id: QuestionFingerprint.buildId('math_ch1', i + 1),
          question: {
            'en': 'Question ${i + 1}?',
            'bn': 'প্রশ্ন ${i + 1}?',
            'hi': 'प्रश्न ${i + 1}?',
          },
        ),
      );

      // Writing by document id twice must not create six documents.
      final bank = <String, QuestionModel>{};
      for (final q in [...batch, ...batch]) {
        bank[q.id] = q;
      }
      expect(bank.length, 3);
    });
  });
}

// ---------------------------------------------------------------- sets -----

void _setsTests() {
  group('chapter sets', () {
    test('a chapter splits into sets of ten, last one short not dropped', () {
      expect(setCountFor(0), 0);
      expect(setCountFor(1), 1);
      expect(setCountFor(10), 1);
      expect(setCountFor(11), 2);
      expect(setCountFor(44), 5, reason: 'four leftovers are still a set');
      expect(setCountFor(200), 20);
    });

    test('set lengths add up to the chapter', () {
      const total = 47;
      final lengths = [
        for (var i = 0; i < setCountFor(total); i++)
          setLengthFor(total, i),
      ];
      expect(lengths, [10, 10, 10, 10, 7]);
      expect(lengths.fold<int>(0, (a, b) => a + b), total);
    });

    test('appending questions never moves an existing set', () {
      // The property the whole design rests on: set 1 must be the same ten
      // questions after the admin adds forty more.
      final before = List.generate(20, (i) => 'q$i');
      final after = [...before, ...List.generate(40, (i) => 'new$i')];

      List<String> slice(List<String> all, int setIndex) {
        final start = setStartIndex(setIndex);
        if (start >= all.length) return const [];
        return all.sublist(
            start, (start + kQuestionsPerSet).clamp(0, all.length));
      }

      expect(slice(after, 0), slice(before, 0));
      expect(slice(after, 1), slice(before, 1));
      expect(setCountFor(after.length), 6,
          reason: 'the new questions become new sets at the end');
    });

    test('progress keeps the better attempt and the original clear date', () {
      final first = ChapterSetProgress(
        chapterId: 'math_ch_01',
        setIndex: 0,
        bestScore: 60,
        bestCorrect: 6,
        totalQuestions: 10,
        completedAt: DateTime(2026, 1, 1),
        lastPlayedAt: DateTime(2026, 1, 1),
      );

      final better = first.merge(
        score: 90,
        correct: 9,
        total: 10,
        playedAt: DateTime(2026, 3, 1),
      );
      expect(better.bestScore, 90);
      expect(better.bestCorrect, 9);
      expect(better.attempts, 2);
      expect(better.completedAt, DateTime(2026, 1, 1),
          reason: 'a replay must not make an old set look newly cleared');
      expect(better.lastPlayedAt, DateTime(2026, 3, 1));

      final worse = better.merge(
        score: 20,
        correct: 2,
        total: 10,
        playedAt: DateTime(2026, 4, 1),
      );
      expect(worse.bestScore, 90, reason: 'a bad replay must not erase a good run');
      expect(worse.bestCorrect, 9);
      expect(worse.attempts, 3);
    });

    test('accuracy and perfect flag', () {
      ChapterSetProgress at(int correct, int total) => ChapterSetProgress(
            chapterId: 'c',
            setIndex: 0,
            bestScore: 0,
            bestCorrect: correct,
            totalQuestions: total,
            completedAt: DateTime(2026),
            lastPlayedAt: DateTime(2026),
          );

      expect(at(10, 10).isPerfect, isTrue);
      expect(at(9, 10).isPerfect, isFalse);
      expect(at(7, 10).accuracyPercent, 70);
      expect(at(0, 0).accuracy, 0, reason: 'must not divide by zero');
    });

    test('round-trips through JSON', () {
      final original = ChapterSetProgress(
        chapterId: 'math_ch_01',
        setIndex: 3,
        bestScore: 80,
        bestCorrect: 8,
        totalQuestions: 10,
        completedAt: DateTime(2026, 2, 14),
        lastPlayedAt: DateTime(2026, 2, 20),
        attempts: 4,
      );
      final restored = ChapterSetProgress.fromJson(original.toJson());

      expect(restored.key, original.key);
      expect(restored.setNumber, 4);
      expect(restored.bestCorrect, 8);
      expect(restored.attempts, 4);
      expect(restored.completedAt, original.completedAt);
    });
  });
}
