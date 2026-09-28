import 'dart:math';

import '../../l10n/app_strings.dart';
import 'localized_text.dart';

/// One multiple-choice question, authored in English, Bangla and Hindi.
///
/// ## JSON shape
///
/// ```json
/// {
///   "id": "c10_b1_01",
///   "question": {
///     "en": "Which enzyme in saliva breaks down starch?",
///     "bn": "লালারসে উপস্থিত কোন উৎসেচক শ্বেতসার ভাঙে?",
///     "hi": "लार में कौन सा एंजाइम स्टार्च को तोड़ता है?"
///   },
///   "options": [
///     { "en": "Pepsin",  "bn": "পেপসিন",  "hi": "पेप्सिन" },
///     { "en": "Ptyalin", "bn": "টায়ালিন", "hi": "टायलिन" }
///   ],
///   "correct_index": 1,
///   "explanation": { "en": "…", "bn": "…", "hi": "…" },
///   "points": 10,
///   "time_limit_sec": 30
/// }
/// ```
///
/// Each option keeps its three languages together rather than living in three
/// parallel arrays. That makes `correct_index` unambiguous and lets a reviewer
/// spot a bad translation without counting positions.
///
/// Validate a bank before committing it:
///
/// ```bash
/// python3 tool/validate_questions.py
/// ```
class QuestionModel {
  final String id;

  /// The question stem in every authored language.
  final LocalizedText questionText;

  /// Answer choices, in display order.
  final List<LocalizedText> optionTexts;

  final int correctIndex;

  /// Shown on the review screen after the quiz. May be empty.
  final LocalizedText explanationText;

  final int points;
  final int timeLimitSec;

  const QuestionModel({
    required this.id,
    required this.questionText,
    required this.optionTexts,
    required this.correctIndex,
    this.explanationText = const LocalizedText.empty(),
    this.points = 10,
    this.timeLimitSec = 30,
  });

  // ---------------------------------------------------- active-language API --
  //
  // The UI never picks a language itself: these getters resolve against the
  // language the user chose, so a screen just reads `question.question` and
  // gets the right string. Changing the app language rebuilds the tree, so
  // they are re-read automatically.

  /// The stem in the current UI language.
  String get question => questionText.current;

  /// Options in the current UI language, in display order.
  List<String> get options =>
      optionTexts.map((option) => option.current).toList(growable: false);

  /// The explanation in the current UI language ('' when not authored).
  String get explanation => explanationText.current;

  /// The stem in a specific language — used by the admin preview.
  String questionIn(String languageCode) => questionText.resolve(languageCode);

  /// Options in a specific language.
  List<String> optionsIn(String languageCode) => optionTexts
      .map((option) => option.resolve(languageCode))
      .toList(growable: false);

  /// The explanation in a specific language.
  String explanationIn(String languageCode) =>
      explanationText.resolve(languageCode);

  /// The correct option in the current UI language.
  String get correctAnswer =>
      correctIndex >= 0 && correctIndex < optionTexts.length
      ? optionTexts[correctIndex].current
      : '';

  /// True when every shipped language has its own copy of this question —
  /// what `tool/validate_questions.py` enforces before a bank is committed.
  bool get isFullyTranslated => kSupportedLanguageCodes.every(
    (code) =>
        questionText.has(code) &&
        optionTexts.every((option) => option.has(code)),
  );

  /// Languages this question is still missing.
  List<String> get missingLanguages => kSupportedLanguageCodes
      .where(
        (code) =>
            !questionText.has(code) ||
            optionTexts.any((option) => !option.has(code)),
      )
      .toList();

  /// A copy with the options in a random order and [correctIndex] moved to
  /// follow the answer.
  ///
  /// Authors write the correct option wherever it falls naturally — and with
  /// AI-generated batches it lands on the same position far more often than
  /// chance. A student who notices that stops reading the options and just
  /// taps B, which is the opposite of practising.
  ///
  /// Shuffled **once when the quiz loads**, never during build: re-rolling on
  /// every rebuild would make the options jump under the player's finger.
  QuestionModel withShuffledOptions([Random? random]) {
    if (optionTexts.length < 2) return this;

    final rng = random ?? Random();
    final order = List<int>.generate(optionTexts.length, (i) => i)
      ..shuffle(rng);

    return QuestionModel(
      id: id,
      questionText: questionText,
      optionTexts: [for (final index in order) optionTexts[index]],
      // Where the correct option ended up after the permutation.
      correctIndex: order.indexOf(correctIndex),
      explanationText: explanationText,
      points: points,
      timeLimitSec: timeLimitSec,
    );
  }

  // ------------------------------------------------------------------ json --

  factory QuestionModel.fromJson(Map<String, dynamic> json) {
    return QuestionModel(
      id: json['id']?.toString() ?? '',
      questionText: LocalizedText.fromJson(json['question']),
      optionTexts: (json['options'] as List? ?? const [])
          .map(LocalizedText.fromJson)
          .toList(growable: false),
      correctIndex: (json['correct_index'] as num?)?.toInt() ?? 0,
      explanationText: LocalizedText.fromJson(json['explanation']),
      points: (json['points'] as num?)?.toInt() ?? 10,
      timeLimitSec: (json['time_limit_sec'] as num?)?.toInt() ?? 30,
    );
  }

  /// Round-trips every language, not just the visible one — these maps are
  /// what gets written to the Hive cache and to Firestore.
  Map<String, dynamic> toJson() => {
    'id': id,
    'question': questionText.toJson(),
    'options': optionTexts.map((o) => o.toJson()).toList(),
    'correct_index': correctIndex,
    'explanation': explanationText.toJson(),
    'points': points,
    'time_limit_sec': timeLimitSec,
  };
}
