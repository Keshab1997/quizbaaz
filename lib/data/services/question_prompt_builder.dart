import 'dart:convert';

import '../models/chapter_model.dart';

/// How hard the generated batch should be.
enum DifficultyMix {
  balanced,
  easier,
  harder;

  String get instruction {
    switch (this) {
      case DifficultyMix.easier:
        return 'Roughly 60% easy, 30% medium, 10% hard — for revision.';
      case DifficultyMix.harder:
        return 'Roughly 20% easy, 40% medium, 40% hard — for exam practice.';
      case DifficultyMix.balanced:
        return 'Roughly 40% easy, 40% medium, 20% hard.';
    }
  }

  String get label {
    switch (this) {
      case DifficultyMix.easier:
        return 'Easier';
      case DifficultyMix.harder:
        return 'Harder';
      case DifficultyMix.balanced:
        return 'Balanced';
    }
  }
}

/// Builds the prompt that produces trilingual quiz questions.
///
/// Accuracy is mostly won or lost here. Everything downstream — the validator,
/// the verification pass, the review screen — is catching what this failed to
/// prevent, and catching is more expensive than not producing the mistake.
///
/// Four things the prompt does deliberately:
///
/// 1. **States the exact audience.** "Class 10" alone gets American-textbook
///    phrasing; naming the board gets the terminology students actually see in
///    the exam.
/// 2. **Lists the stems already in the chapter.** Without this the model
///    re-invents the same three questions on every run, and a chapter that
///    should grow to 200 questions plateaus at 30 distinct ones.
/// 3. **Shows the schema by example, not by description.** Models follow a
///    concrete sample far more reliably than a prose spec.
/// 4. **Asks for the explanation to justify the marked answer.** This is a
///    cheap self-check: a model that has to explain why option B is right
///    catches its own mistake more often than one that just marks it.
class QuestionPromptBuilder {
  QuestionPromptBuilder._();

  /// Existing stems sent as "do not repeat". Capped so a 300-question chapter
  /// cannot blow the context window; the most recent are the ones a model is
  /// most likely to duplicate anyway.
  static const int maxExistingStems = 60;

  /// The board and phrasing the questions must match.
  static const String defaultSyllabus =
      'West Bengal Board (WBBSE) and CBSE Class 10';

  /// System instruction — the role, kept short so it is not diluted.
  static String systemPrompt() {
    return 'You write multiple-choice exam questions for Class 10 students in '
        'India. You are precise about facts, you never mark a wrong option as '
        'correct, and you output raw JSON only — no prose, no markdown fence.';
  }

  /// The generation request.
  static String buildGenerationPrompt({
    required ChapterModel chapter,
    required String subjectName,
    required int count,
    required String idPrefix,
    required int startSequence,
    List<String> existingStems = const [],
    DifficultyMix difficulty = DifficultyMix.balanced,
    String syllabus = defaultSyllabus,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('Write $count multiple-choice questions.');
    buffer.writeln();
    buffer.writeln('Syllabus : $syllabus');
    buffer.writeln('Subject  : $subjectName');
    buffer.writeln('Chapter  : ${chapter.titleText.resolve('en')}');

    final bn = chapter.titleText.resolve('bn');
    final hi = chapter.titleText.resolve('hi');
    if (bn.isNotEmpty && bn != chapter.titleText.resolve('en')) {
      buffer.writeln('  Bangla : $bn');
    }
    if (hi.isNotEmpty && hi != chapter.titleText.resolve('en')) {
      buffer.writeln('  Hindi  : $hi');
    }

    final description = chapter.descriptionText.resolve('en');
    if (description.isNotEmpty) {
      buffer.writeln('Scope    : $description');
    }

    buffer.writeln();
    buffer.writeln('OUTPUT');
    buffer.writeln('Return a JSON array of exactly $count objects. Nothing '
        'else — no explanation, no markdown fence, no trailing commentary.');
    buffer.writeln();
    buffer.writeln(_schemaExample(idPrefix, startSequence));
    buffer.writeln();

    buffer.writeln('RULES');
    for (final rule in _rules(count, idPrefix, startSequence, difficulty)) {
      buffer.writeln('- $rule');
    }

    if (existingStems.isNotEmpty) {
      final recent = existingStems.length > maxExistingStems
          ? existingStems.sublist(existingStems.length - maxExistingStems)
          : existingStems;
      buffer.writeln();
      buffer.writeln('ALREADY IN THIS CHAPTER — do not write any question that '
          'asks the same thing, even reworded:');
      for (final stem in recent) {
        buffer.writeln('- $stem');
      }
    }

    return buffer.toString();
  }

  static List<String> _rules(
    int count,
    String idPrefix,
    int startSequence,
    DifficultyMix difficulty,
  ) {
    final lastSequence = startSequence + count - 1;
    return [
      'Exactly 4 options per question. Exactly one is correct.',
      '"correct_index" is 0-based and must point at the correct option.',
      'Ids run "${_id(idPrefix, startSequence)}" to "${_id(idPrefix, lastSequence)}", '
          'in order, with no gaps.',
      'Every field must be present in all three languages: en, bn, hi.',
      'Translate the meaning, do not transliterate. Use the terminology the '
          'Class 10 textbook uses in that language; when a technical term is '
          'normally kept in English in the classroom, keep it in English.',
      'Numbers, formulas, chemical symbols, units and years stay identical '
          'across the three languages.',
      'Distractors must be mistakes a student would plausibly make — a wrong '
          'formula, an off-by-one, a confused definition. Never filler or joke '
          'options.',
      'No two options may mean the same thing in any language.',
      'The explanation must show the reasoning that leads to the marked '
          'answer, in one or two sentences. Do not merely restate the answer.',
      'Before you output a question, re-check that "correct_index" points at '
          'the option your explanation justifies.',
      difficulty.instruction,
      'Do not use "All of the above" or "None of the above".',
      'Keep each question answerable in about 15 seconds.',
    ];
  }

  static String _id(String prefix, int sequence) =>
      '${prefix}_q${sequence.toString().padLeft(3, '0')}';

  /// A filled-in example rather than a description — models copy structure far
  /// more reliably than they follow prose about structure.
  static String _schemaExample(String idPrefix, int startSequence) {
    final example = [
      {
        'id': _id(idPrefix, startSequence),
        'question': {
          'en': 'Which gas is absorbed by plants during photosynthesis?',
          'bn': 'সালোকসংশ্লেষের সময় গাছ কোন গ্যাস গ্রহণ করে?',
          'hi': 'प्रकाश संश्लेषण के दौरान पौधे कौन सी गैस लेते हैं?',
        },
        'options': [
          {'en': 'Oxygen', 'bn': 'অক্সিজেন', 'hi': 'ऑक्सीजन'},
          {
            'en': 'Carbon dioxide',
            'bn': 'কার্বন ডাইঅক্সাইড',
            'hi': 'कार्बन डाइऑक्साइड',
          },
          {'en': 'Nitrogen', 'bn': 'নাইট্রোজেন', 'hi': 'नाइट्रोजन'},
          {'en': 'Hydrogen', 'bn': 'হাইড্রোজেন', 'hi': 'हाइड्रोजन'},
        ],
        'correct_index': 1,
        'explanation': {
          'en': 'Plants take in carbon dioxide and release oxygen during '
              'photosynthesis, using it with water to make glucose.',
          'bn': 'সালোকসংশ্লেষে গাছ কার্বন ডাইঅক্সাইড গ্রহণ করে এবং জল-সহ '
              'গ্লুকোজ তৈরি করে অক্সিজেন ত্যাগ করে।',
          'hi': 'प्रकाश संश्लेषण में पौधे कार्बन डाइऑक्साइड लेते हैं और जल के '
              'साथ ग्लूकोज बनाकर ऑक्सीजन छोड़ते हैं।',
        },
        'points': 10,
        'time_limit_sec': 30,
      }
    ];
    return const JsonEncoder.withIndent('  ').convert(example);
  }

  /// Second-opinion prompt for the verification pass.
  ///
  /// Sent to a *different* key so it is not the same context re-agreeing with
  /// itself. Only the English text is checked: an error in the answer is an
  /// error in every language, and checking one third of the text costs one
  /// third as much.
  static String buildVerificationPrompt({
    required String questionEn,
    required List<String> optionsEn,
    required int markedIndex,
    required String explanationEn,
    String syllabus = defaultSyllabus,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('You are checking one exam question for $syllabus.');
    buffer.writeln();
    buffer.writeln('Question: $questionEn');
    for (var i = 0; i < optionsEn.length; i++) {
      final marker = i == markedIndex ? ' <-- marked correct' : '';
      buffer.writeln('  [$i] ${optionsEn[i]}$marker');
    }
    if (explanationEn.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Stated reason: $explanationEn');
    }
    buffer.writeln();
    buffer.writeln('Is the marked option correct for this syllabus?');
    buffer.writeln('Reply with raw JSON only:');
    buffer.writeln('{"verdict":"ok|wrong|unsure","correct_index":0,'
        '"reason":"one short sentence"}');
    buffer.writeln();
    buffer.writeln('Use "wrong" only when you are confident another option is '
        'right, and put its index in correct_index. Use "unsure" when the '
        'question is ambiguous or you cannot tell. Otherwise "ok".');
    return buffer.toString();
  }

  /// Prompt for filling bn/hi from an English field in the admin forms.
  ///
  /// This is machine translation at *authoring* time, reviewed before it is
  /// saved — not the runtime translation that was removed from the app.
  static String buildFieldTranslationPrompt(String english) {
    return 'Translate this Class 10 exam text into Bangla and Hindi.\n'
        'Use the terminology the Class 10 textbook uses in each language. '
        'Keep numbers, formulas, symbols and units exactly as they are. '
        'Keep a technical term in English if that is what the classroom uses.\n'
        'Reply with raw JSON only: {"bn":"...","hi":"..."}\n\n'
        'Text: $english';
  }
}
