import 'question_model.dart';

/// A display group of consecutive questions in the admin question manager.
///
/// Sets are derived from the current stable question order; they are not saved
/// separately. This lets an admin review or delete a manageable group without
/// changing question IDs or the learner-facing quiz order.
class QuestionSet {
  /// The number of questions in a normal admin set.
  static const int questionsPerSet = 10;

  /// One-based set number shown in the admin UI.
  final int number;

  /// Zero-based position of the first question in the complete chapter list.
  final int startIndex;

  /// Consecutive questions belonging to this set. The final set may be short.
  final List<QuestionModel> questions;

  const QuestionSet({
    required this.number,
    required this.startIndex,
    required this.questions,
  });

  /// Partitions [questions] into stable groups of ten, retaining input order.
  static List<QuestionSet> fromQuestions(List<QuestionModel> questions) {
    final sets = <QuestionSet>[];
    for (var start = 0; start < questions.length; start += questionsPerSet) {
      final end = (start + questionsPerSet).clamp(0, questions.length);
      sets.add(QuestionSet(
        number: sets.length + 1,
        startIndex: start,
        questions: List.unmodifiable(questions.sublist(start, end)),
      ));
    }
    return sets;
  }
}
