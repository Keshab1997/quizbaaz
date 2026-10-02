import '../models/chapter_model.dart';

/// Builds the copy-paste prompts the admin sends to ChatGPT / Gemini.
///
/// Two jobs, kept separate on purpose:
///
/// 1. **Question batch prompt** ([buildQuestionBatchPrompt]) — the model
///    returns the exact JSON the Question Manager's "Paste JSON" import
///    accepts, so the admin never hand-converts anything.
/// 2. **Plain-to-JSON formatter prompt** ([buildPlainToJsonPrompt]) — the
///    admin already has normal Q&A text (from ChatGPT/Gemini or a book);
///    the model reshapes it into the same JSON shape. The admin pastes
///    their questions into [plainQuestions] and copies the whole prompt.
class AdminAiPromptBuilder {
  AdminAiPromptBuilder._();

  /// Prompt that asks the model to WRITE fresh questions for [chapter].
  ///
  /// The output contract matches `_parseCustomJsonQuestions` in
  /// `question_manager_screen.dart`: either shape of `question`, either
  /// shape of `options`, `correct_index` 0-based, optional `explanation`
  /// / `points` / `time_limit_sec`.
  static String buildQuestionBatchPrompt({
    required ChapterModel chapter,
    required String subjectName,
    int count = 10,
    String syllabus = 'West Bengal Board (WBBSE) and CBSE Class 10',
  }) {
    final chapterEn = chapter.titleText.resolve('en');
    final idPrefix = _idPrefix(chapter.chapterId);
    return '''
You are writing multiple-choice questions for a $syllabus exam-prep app used by Bengali-speaking students.

Chapter: $chapterEn — $subjectName
Write $count questions.

Output ONLY a JSON array, no prose, no markdown fence. Each element:

{
  "question": { "en": "...", "bn": "...", "hi": "..." },
  "options": [
    { "en": "...", "bn": "...", "hi": "..." },
    { "en": "...", "bn": "...", "hi": "..." },
    { "en": "...", "bn": "...", "hi": "..." },
    { "en": "...", "bn": "...", "hi": "..." }
  ],
  "correct_index": 0,
  "explanation": { "en": "...", "bn": "...", "hi": "..." },
  "points": 10,
  "time_limit_sec": 30
}

Rules:
* Exactly 4 options. Only one is correct. correct_index is 0-based.
* Suggested question ids (optional in output): ${idPrefix}_q001, ${idPrefix}_q002, ... with no gaps — the app assigns ids on import anyway.
* All three languages for every field. Translate the meaning, do not transliterate. Keep standard board terminology — in Bangla and Hindi, a technical term may stay in English if that is what the textbook uses.
* Numbers, formulas, chemical symbols and units stay as they are.
* Distractors must be plausible mistakes a student would actually make, not obviously silly.
* Explanations: one or two sentences, showing the reasoning, not just the answer.
* Mix difficulty: roughly 40% easy, 40% medium, 20% hard.
* Short questions — answerable in 30 seconds.
''';
  }

  /// Prompt that asks the model to REFORMAT the admin's existing plain
  /// questions into the import-ready JSON shape.
  ///
  /// The admin pastes normal text (e.g. "1. What is ...? A) ... B) ... Answer:
  /// B") as [plainQuestions]; the model returns only the JSON array.
  static String buildPlainToJsonPrompt({
    required ChapterModel chapter,
    required String plainQuestions,
  }) {
    final chapterEn = chapter.titleText.resolve('en');
    final idPrefix = _idPrefix(chapter.chapterId);
    final text = plainQuestions.trim();
    return '''
Convert the following Class 10 questions ($chapterEn) into the EXACT JSON shape below. Translate every field into Bangla (bn) and Hindi (hi) using WBBSE/CBSE textbook terminology. Keep numbers, formulas, symbols and units unchanged.

Output ONLY a JSON array, no prose, no markdown fence. Each element:

{
  "question": { "en": "...", "bn": "...", "hi": "..." },
  "options": [
    { "en": "...", "bn": "...", "hi": "..." },
    { "en": "...", "bn": "...", "hi": "..." },
    { "en": "...", "bn": "...", "hi": "..." },
    { "en": "...", "bn": "...", "hi": "..." }
  ],
  "correct_index": 0,
  "explanation": { "en": "...", "bn": "...", "hi": "..." },
  "points": 10,
  "time_limit_sec": 30
}

Rules:
* Exactly 4 options per question. If the input has fewer, add one plausible distractor. If the input has no marked answer, pick the correct one yourself and set correct_index (0-based).
* Suggested question ids (optional in output): ${idPrefix}_q001, ... — the app assigns ids on import anyway.
* If the input already has an explanation, translate it; otherwise write one short sentence.

QUESTIONS TO CONVERT:
$text
''';
  }

  /// Suggested id stem for a chapter, e.g. `math_ch_01` -> `math_ch_01`.
  static String _idPrefix(String chapterId) =>
      chapterId.trim().isEmpty ? 'chapter' : chapterId.trim();
}
