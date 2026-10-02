import '../models/localized_text.dart';
import '../models/question_model.dart';
import '../../l10n/app_strings.dart';
import 'question_fingerprint.dart';

/// How serious a validation finding is.
///
/// The distinction matters because the generator acts on it: a [rejection] is
/// thrown away and regenerated, a [warning] is shown to the admin who decides.
enum IssueLevel { rejection, warning }

/// One problem found in a candidate question.
class ValidationIssue {
  final IssueLevel level;
  final String field;
  final String message;

  const ValidationIssue(this.level, this.field, this.message);

  bool get isRejection => level == IssueLevel.rejection;

  @override
  String toString() => '$field: $message';
}

/// The outcome of validating a single question.
class ValidationResult {
  final List<ValidationIssue> issues;

  /// Set when the question closely resembles one already in the bank.
  final NearDuplicate? nearDuplicate;

  const ValidationResult(this.issues, {this.nearDuplicate});

  const ValidationResult.ok() : issues = const [], nearDuplicate = null;

  List<ValidationIssue> get rejections =>
      issues.where((i) => i.isRejection).toList();

  List<ValidationIssue> get warnings =>
      issues.where((i) => !i.isRejection).toList();

  /// True when nothing blocks this question from being saved.
  bool get isAcceptable => rejections.isEmpty;

  /// True when it is clean enough to save without a second look.
  bool get isClean => issues.isEmpty && nearDuplicate == null;

  /// One-line summary for the review screen.
  String get summary {
    if (isClean) return 'OK';
    if (rejections.isNotEmpty) return rejections.first.toString();
    if (nearDuplicate != null) {
      return 'Near-duplicate of ${nearDuplicate!.questionId} '
          '(${nearDuplicate!.scoreLabel})';
    }
    return warnings.first.toString();
  }
}

/// Validates questions before they are written to the bank.
///
/// This is the Dart twin of `tool/validate_questions.py` and the two must stay
/// in step — the Python one gates what is committed to `assets/`, this one
/// gates what an admin writes to Firestore. A rule that exists on only one side
/// means content that passes review and then fails the build, or the reverse.
///
/// Every rule here exists because a model actually produced it: option lists
/// that lose a language halfway, a `correct_index` of 4 on a four-option
/// question, Hindi that is a verbatim copy of the English.
class QuestionValidator {
  QuestionValidator._();

  static const int minOptions = 2;
  static const int maxOptions = 6;
  static const int expectedOptions = 4;
  static const int minExplanationLength = 20;

  /// Validates one question.
  ///
  /// [existingStems] maps question id to English stem for the chapter being
  /// written to, and enables duplicate detection. [existingFingerprints] is the
  /// cheap exact-match set.
  static ValidationResult validate(
    QuestionModel question, {
    Map<String, String> existingStems = const {},
    Set<String> existingFingerprints = const {},
  }) {
    final issues = <ValidationIssue>[];

    // ------------------------------------------------------------ identity --
    if (question.id.trim().isEmpty) {
      issues.add(const ValidationIssue(IssueLevel.rejection, 'id', 'missing'));
    }

    // ------------------------------------------------------------ the stem --
    _checkLocalized(issues, 'question', question.questionText, required: true);

    // ------------------------------------------------------------- options --
    final options = question.optionTexts;
    if (options.length < minOptions || options.length > maxOptions) {
      issues.add(
        ValidationIssue(
          IssueLevel.rejection,
          'options',
          '${options.length} options — expected $minOptions-$maxOptions',
        ),
      );
    } else if (options.length != expectedOptions) {
      issues.add(
        ValidationIssue(
          IssueLevel.warning,
          'options',
          '${options.length} options — the app is designed around $expectedOptions',
        ),
      );
    }

    for (var i = 0; i < options.length; i++) {
      _checkLocalized(issues, 'options[$i]', options[i], required: true);
    }

    // Two options that read the same make the question unanswerable, and it
    // only shows up in one language when a translation collapses a distinction.
    for (final language in kSupportedLanguageCodes) {
      final seen = <String, int>{};
      for (var i = 0; i < options.length; i++) {
        final text = options[i].resolve(language).trim().toLowerCase();
        if (text.isEmpty) continue;
        final previous = seen[text];
        if (previous != null) {
          issues.add(
            ValidationIssue(
              IssueLevel.rejection,
              'options',
              'options $previous and $i are identical in "$language"',
            ),
          );
        } else {
          seen[text] = i;
        }
      }
    }

    // -------------------------------------------------------- correct index --
    if (question.correctIndex < 0 || question.correctIndex >= options.length) {
      issues.add(
        ValidationIssue(
          IssueLevel.rejection,
          'correct_index',
          '${question.correctIndex} is outside 0..${options.length - 1}',
        ),
      );
    }

    // --------------------------------------------------------- explanation --
    if (question.explanationText.isEmpty) {
      issues.add(
        const ValidationIssue(
          IssueLevel.warning,
          'explanation',
          'empty — students see nothing on the review screen',
        ),
      );
    } else {
      _checkLocalized(
        issues,
        'explanation',
        question.explanationText,
        required: false,
      );
      final english = question.explanationText.resolve('en');
      if (english.length < minExplanationLength) {
        issues.add(
          ValidationIssue(
            IssueLevel.warning,
            'explanation',
            'only ${english.length} characters — does it show the reasoning?',
          ),
        );
      }
    }

    // ------------------------------------------------------------- numbers --
    if (question.points < 1 || question.points > 1000) {
      issues.add(
        ValidationIssue(
          IssueLevel.rejection,
          'points',
          '${question.points} is outside 1..1000',
        ),
      );
    }
    if (question.timeLimitSec < 5 || question.timeLimitSec > 300) {
      issues.add(
        ValidationIssue(
          IssueLevel.rejection,
          'time_limit_sec',
          '${question.timeLimitSec} is outside 5..300',
        ),
      );
    }

    // ------------------------------------------------------------ duplicate --
    final stem = question.questionText.resolve('en');
    final fingerprint = QuestionFingerprint.fingerprint(stem);
    if (fingerprint.isNotEmpty && existingFingerprints.contains(fingerprint)) {
      issues.add(
        const ValidationIssue(
          IssueLevel.rejection,
          'question',
          'this exact question is already in the chapter',
        ),
      );
    }

    final near =
        existingStems.isEmpty
            ? null
            : QuestionFingerprint.findNearDuplicate(stem, existingStems);

    return ValidationResult(issues, nearDuplicate: near);
  }

  /// Validates a whole batch, threading each accepted question's fingerprint
  /// into the next one's check so a batch cannot duplicate *itself*.
  static List<ValidationResult> validateBatch(
    List<QuestionModel> questions, {
    Map<String, String> existingStems = const {},
    Set<String> existingFingerprints = const {},
  }) {
    final stems = Map<String, String>.from(existingStems);
    final fingerprints = Set<String>.from(existingFingerprints);
    final results = <ValidationResult>[];

    for (final question in questions) {
      final result = validate(
        question,
        existingStems: stems,
        existingFingerprints: fingerprints,
      );
      results.add(result);

      if (result.isAcceptable) {
        final stem = question.questionText.resolve('en');
        stems[question.id] = stem;
        final fingerprint = QuestionFingerprint.fingerprint(stem);
        if (fingerprint.isNotEmpty) fingerprints.add(fingerprint);
      }
    }
    return results;
  }

  // ------------------------------------------------------------- internals --

  /// Checks that a translatable field carries every shipped language, and that
  /// the translations are not just the English pasted back.
  static void _checkLocalized(
    List<ValidationIssue> issues,
    String field,
    LocalizedText text, {
    required bool required,
  }) {
    if (text.isEmpty) {
      if (required) {
        issues.add(ValidationIssue(IssueLevel.rejection, field, 'empty'));
      }
      return;
    }

    final english = text.resolve('en');
    if (!text.has('en')) {
      issues.add(
        ValidationIssue(
          IssueLevel.rejection,
          field,
          'no English text — it is the fallback for every other language',
        ),
      );
    }

    for (final language in kSupportedLanguageCodes) {
      if (language == 'en') continue;
      if (!text.has(language)) {
        issues.add(
          ValidationIssue(IssueLevel.rejection, field, 'missing "$language"'),
        );
        continue;
      }
      // A model that skipped translating echoes the English straight back.
      if (text.resolve(language) == english && _looksUntranslated(english)) {
        issues.add(
          ValidationIssue(
            IssueLevel.rejection,
            field,
            '"$language" is identical to English — translation was skipped',
          ),
        );
      }
    }
  }

  /// True when English text repeated verbatim in another language really does
  /// mean the translation step was skipped.
  ///
  /// Three things legitimately read the same in all three languages and must
  /// not be flagged:
  ///
  /// * symbols, formulas and numbers — `H2O`, `NaCl`, `1947`, `45°`;
  /// * single technical terms the classroom itself keeps in English —
  ///   `Router`, `Spreadsheet`. The authoring guide explicitly allows this;
  /// * ratios, measurements and formulas that contain spaces — `1 : 2`,
  ///   `50 Hz`, `H = I² · R · t` (see [_isLanguageNeutral]).
  ///
  /// The first two are single tokens. Natural-language copy that was supposed
  /// to be translated is not, so requiring a space is a cheap and accurate
  /// split; the third is the exception to that split.
  static bool _looksUntranslated(String text) {
    final trimmed = text.trim();
    if (!trimmed.contains(' ')) return false;

    var hasLatinLetter = false;
    for (final rune in trimmed.runes) {
      if (rune > 0x024F) return false; // Bangla, Devanagari, CJK, …
      if ((rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A)) {
        hasLatinLetter = true;
      }
    }
    return hasLatinLetter && !_isLanguageNeutral(trimmed);
  }

  /// True for text whose only Latin letters are symbols or units: every run of
  /// letters is at most two characters (`cm`, `Hz`, `pH`, `D`) or a known
  /// longer unit symbol. It must also contain a digit or an operator, so two
  /// short words (`It is`) still count as prose. Mirrors `is_language_neutral`
  /// in tool/validate_questions.py — keep the two in step.
  static bool _isLanguageNeutral(String text) {
    if (!_formulaChars.hasMatch(text)) return false;
    for (final run in _latinRun.allMatches(text)) {
      final word = run.group(0)!;
      if (word.length > 2 && !_unitSymbols.contains(word)) return false;
    }
    return true;
  }

  static final RegExp _formulaChars = RegExp(r'[0-9=+−×÷·/:^²³°%<>-]');
  static final RegExp _latinRun = RegExp(r'[A-Za-z]+');
  static const Set<String> _unitSymbols = {
    'kPa',
    'MPa',
    'GPa',
    'kHz',
    'MHz',
    'GHz',
    'kWh',
    'mol',
    'atm',
    'rpm',
    'ppm',
  };
}
