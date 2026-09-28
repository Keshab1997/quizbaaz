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

  /// System instruction — improved for WBBSE terminology and trilingual accuracy.
  static String systemPrompt() {
    return 'You are an expert Class 10 question setter for WBBSE & CBSE in India. '
        'You write accurate, concise, exam-relevant MCQs in 3 languages (en/bn/hi) with perfect translations using textbook terminology. '
        'You never mark a wrong option as correct, you keep questions short for 30-second answering, and you output raw JSON only — no prose, no markdown fence, no explanation outside JSON.';
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

    buffer.writeln(
      'Write $count multiple-choice questions for Class 10 exam prep.',
    );
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

    final descEn = chapter.descriptionText.resolve('en');
    final descBn = chapter.descriptionText.resolve('bn');
    final descHi = chapter.descriptionText.resolve('hi');
    if (descEn.isNotEmpty) {
      buffer.writeln('Scope EN : $descEn');
    }
    if (descBn.isNotEmpty && descBn != descEn) {
      buffer.writeln('Scope BN : $descBn');
    }
    if (descHi.isNotEmpty && descHi != descEn) {
      buffer.writeln('Scope HI : $descHi');
    }
    buffer.writeln();
    buffer.writeln('OUTPUT');
    buffer.writeln(
      'Return a JSON array of exactly $count objects. Nothing '
      'else — no explanation, no markdown fence, no trailing commentary. '
      'Each object must have: id, question {en,bn,hi}, options[4] of {en,bn,hi}, correct_index (0-3), explanation {en,bn,hi}, points=10, time_limit_sec=30',
    );
    buffer.writeln();
    buffer.writeln('SCHEMA EXAMPLE (copy structure exactly):');
    buffer.writeln(_schemaExample(idPrefix, startSequence));
    buffer.writeln();

    buffer.writeln('RULES — follow strictly:');
    for (final rule in _rules(
      count,
      idPrefix,
      startSequence,
      difficulty,
      chapter.titleText.resolve('en'),
    )) {
      buffer.writeln('- $rule');
    }

    if (existingStems.isNotEmpty) {
      final recent = existingStems.length > maxExistingStems
          ? existingStems.sublist(existingStems.length - maxExistingStems)
          : existingStems;
      buffer.writeln();
      buffer.writeln(
        'ALREADY IN THIS CHAPTER — do NOT write any question that '
        'asks the same thing, even reworded or translated:',
      );
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
    String chapterTitleEn,
  ) {
    final lastSequence = startSequence + count - 1;
    return [
      'Exactly 4 options per question. Exactly one is correct. Never use "All of the above" or "None of the above".',
      '"correct_index" is 0-based (0,1,2,3) and must point at the correct option. Randomize its position across the $count questions — don\'t put all correct answers at B or C. Distribution should be roughly even.',
      'Ids run "${_id(idPrefix, startSequence)}" to "${_id(idPrefix, lastSequence)}", in order, with no gaps, no duplicates.',
      'Every field must be present in all three languages: en, bn, hi. No empty strings. Translation must be complete.',
      'TRANSLATION QUALITY: Translate meaning, not transliteration. Use WBBSE/CBSE Class 10 textbook terminology. For Bangla, use proper Bengali scientific terms (e.g., সালোকসংশ্লেষ, not ফটোসিনথেসিস; পৌষ্টিকনালী, not ডাইজেস্টিভ সিস্টেম). For Hindi, use NCERT terms. Keep technical terms like DNA, RNA, pH, H2O in English only if that is what classroom uses.',
      'Numbers, formulas, chemical symbols, units, years stay IDENTICAL across en/bn/hi (e.g., H2SO4, 96, 10m/s²).',
      'CONCISE: Question stem max 1-2 sentences, max 180 characters. Students have 30 seconds to read + answer. Avoid long paragraphs.',
      'OPTIONS: Each option max 50 characters, concise, balanced in length. Correct answer must NOT be noticeably longer than distractors.',
      'DISTRACTORS: Must be plausible mistakes a Class 10 student would make — wrong formula, off-by-one, confused definition, common misconception. Never filler, jokes, or obviously wrong options like "Banana" for a physics question.',
      'No two options may mean the same thing in any language.',
      'EXPLANATION: 1-2 sentences max, shows reasoning that leads to marked answer, in all three languages. Do not merely restate answer. Example: "Small intestine completes digestion with liver & pancreas secretions."',
      'SELF-CHECK: Before output, re-check that "correct_index" points at the option your explanation justifies. If mismatch, fix it.',
      'DIFFICULTY: ${difficulty.instruction}',
      'TIMING: Keep each question answerable in about 30 seconds. Set points=10, time_limit_sec=30 for every question.',
      'SCOPE: Questions must be strictly from chapter "$chapterTitleEn" only. No out-of-syllabus, no advanced college topics. Must be exam-relevant for WBBSE/CBSE Class 10.',
      'VARIETY: Each of the $count questions should test different sub-topic, fact, or concept within the chapter. Avoid repeating same concept with different wording.',
      'AVOID: Very similar questions, duplicate stems, or questions that are too trivial (e.g., "What is the full form of DNA?") unless chapter is about that.',
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
          'en':
              'Plants take in CO2 and release O2 during photosynthesis, using it with water to make glucose.',
          'bn':
              'সালোকসংশ্লেষে গাছ CO2 গ্রহণ করে এবং জল-সহ গ্লুকোজ তৈরি করে O2 ত্যাগ করে।',
          'hi':
              'प्रकाश संश्लेषण में पौधे CO2 लेते हैं और जल के साथ ग्लूकोज बनाकर O2 छोड़ते हैं।',
        },
        'points': 10,
        'time_limit_sec': 30,
      },
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
    buffer.writeln(
      'You are checking one exam question for $syllabus. Be strict.',
    );
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
    buffer.writeln(
      '{"verdict":"ok|wrong|unsure","correct_index":0,'
      '"reason":"one short sentence"}',
    );
    buffer.writeln();
    buffer.writeln(
      'Use "wrong" only when you are confident another option is '
      'right, and put its index in correct_index. Use "unsure" when the '
      'question is ambiguous or you cannot tell. Otherwise "ok".',
    );
    return buffer.toString();
  }

  /// Prompt for filling bn/hi from an English field in the admin forms.
  ///
  /// This is machine translation at *authoring* time, reviewed before it is
  /// saved — not the runtime translation that was removed from the app.
  static String buildFieldTranslationPrompt(String english) {
    return 'Translate this Class 10 exam text into Bangla and Hindi.\n'
        'Use WBBSE/CBSE textbook terminology in each language. '
        'For Bangla, use proper Bengali scientific terms (not English transliteration). '
        'Keep numbers, formulas, symbols and units exactly as they are. '
        'Keep a technical term in English if that is what the classroom uses.\n'
        'Reply with raw JSON only: {"bn":"...","hi":"..."}\n\n'
        'Text: $english';
  }
}
