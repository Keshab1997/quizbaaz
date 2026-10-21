import 'package:flutter_test/flutter_test.dart';
import 'package:quizbaaz/data/models/localized_text.dart';
import 'package:quizbaaz/data/models/question_model.dart';
import 'package:quizbaaz/presentation/screens/chapter_quiz/chapter_revision_screen.dart';

QuestionModel _question(String id) => QuestionModel(
  id: id,
  questionText: LocalizedText({'en': 'Question $id'}),
  optionTexts: const [
    LocalizedText({'en': 'First'}),
    LocalizedText({'en': 'Second'}),
  ],
  correctIndex: 0,
);

List<QuestionModel> _bank(int count) => [
  for (var i = 0; i < count; i++) _question('q$i'),
];

void main() {
  group('revisionSlice', () {
    test('no set index revises the whole chapter', () {
      final all = _bank(25);
      expect(revisionSlice(all, setIndex: null), same(all));
    });

    test('a set index revises exactly that set', () {
      final all = _bank(25);
      expect(revisionSlice(all, setIndex: 1).map((q) => q.id), [
        'q10',
        'q11',
        'q12',
        'q13',
        'q14',
        'q15',
        'q16',
        'q17',
        'q18',
        'q19',
      ]);
    });

    test('the last partial set shows its remaining questions', () {
      final all = _bank(25);
      expect(revisionSlice(all, setIndex: 2).map((q) => q.id), [
        'q20',
        'q21',
        'q22',
        'q23',
        'q24',
      ]);
    });

    test('a set beyond the bank is empty, never invented', () {
      expect(revisionSlice(_bank(25), setIndex: 5), isEmpty);
    });
  });
}
