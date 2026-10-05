import 'dart:convert';

import '../models/localized_text.dart';
import 'bulk_chapter_importer.dart';

/// Prompt builder + answer parser for the "paste syllabus → ask ChatGPT /
/// Gemini → paste JSON → chapters appear" admin flow.
///
/// The prompt carries the subject, the first free chapter number and the
/// exact JSON schema, so whatever the model returns can be validated with
/// the same never-overwrite rules as the manual paste-a-list flow and saved
/// through [BulkChapterImporter.saveAll].
class AiSyllabusImporter {
  AiSyllabusImporter._();

  /// Builds the copy-paste prompt for an external AI chat.
  static String buildPrompt({
    required String subjectName,
    required String categoryId,
    required int startNumber,
    required String syllabusText,
  }) {
    final exampleId = BulkChapterImporter.suggestChapterId(
      categoryId,
      startNumber,
    );
    return '''
You are helping the admin of QuizBaaz, a Class-10 quiz app for Indian students (English, Bangla, Hindi).

Below is a syllabus / table-of-contents pasted from a book. Create ONE chapter entry per item, in the book's order.

Subject: $subjectName (id: $categoryId)
Number the chapters $startNumber, ${startNumber + 1}, ... in order — ignore the book's own chapter numbers and page numbers.
Chapter id format: <stem>_ch_<NN> (two digits). Your first id is $exampleId, then keep counting.

Rules:
- Return ONLY a raw JSON array — no markdown fences, no explanation, no extra text.
- Every chapter looks like this:
  {"id": "$exampleId", "number": $startNumber, "title": {"en": "Chapter title in English", "bn": "বাংলায় অধ্যায়ের নাম", "hi": "हिन्दी में अध्याय का नाम"}, "description": {"en": "One short line, or {} to skip"}}
- "title.en" is required. "bn" must be natural Bangla (West Bengal board students), "hi" natural Hindi in Devanagari script.
- "description" is one short line per language; {} is fine when there is nothing useful to say.
- Skip decorative lines, page numbers, and part headers that are not chapters (e.g. the book title itself).

Syllabus text:
"""
$syllabusText
"""''';
  }

  /// Parses the AI's JSON answer into drafts.
  ///
  /// Missing ids/numbers are auto-assigned from [startNumber]; rows that
  /// collide with [takenIds], repeat an id, or lack an English title become
  /// "skipped" drafts instead of throwing. Throws [FormatException] with an
  /// admin-readable message only when the whole text is not a JSON array.
  static List<BulkChapterDraft> parseAnswer(
    String raw, {
    required String categoryId,
    required int startNumber,
    Set<String> takenIds = const {},
  }) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(_stripFences(raw.trim()));
    } on FormatException {
      throw const FormatException(
        'Could not read JSON — paste only the [ ... ] array the AI returned.',
      );
    }
    if (decoded is! List) {
      throw const FormatException(
        'The answer must be a JSON array ([ ... ]), not an object.',
      );
    }
    if (decoded.length > 200) {
      throw FormatException(
        'Too many chapters (${decoded.length}) — split the paste into batches of 200.',
      );
    }

    final drafts = <BulkChapterDraft>[];
    final seen = <String>{};
    var number = startNumber;
    for (var i = 0; i < decoded.length; i++) {
      final row = 'Row ${i + 1}';
      final item = decoded[i];
      if (item is! Map) {
        drafts.add(
          BulkChapterDraft(
            chapterId: '',
            title: const LocalizedText.empty(),
            description: const LocalizedText.empty(),
            chapterNumber: number,
            error: '$row is not an object — skipped',
          ),
        );
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final rowNumber = (map['number'] as num?)?.toInt() ?? number;
      final rawId = (map['id'] ?? '').toString().trim();
      final id =
          rawId.isEmpty
              ? BulkChapterImporter.suggestChapterId(categoryId, rowNumber)
              : rawId;
      final title = LocalizedText.fromJson(map['title']);
      final description = LocalizedText.fromJson(map['description']);

      String? error;
      if (!title.has('en')) {
        error = '$row: English title is empty — skipped';
      } else if (!RegExp(r'^[a-z0-9_]+$').hasMatch(id)) {
        error = '$row: id "$id" has invalid characters — skipped';
      } else if (takenIds.contains(id) || seen.contains(id)) {
        error = '$row: chapter id "$id" already exists — skipped';
      }
      if (error == null) {
        seen.add(id);
        number = rowNumber + 1;
      }
      drafts.add(
        BulkChapterDraft(
          chapterId: id,
          title: title,
          description: description,
          chapterNumber: rowNumber,
          error: error,
        ),
      );
    }
    return drafts;
  }

  /// Models wrap answers in ```json fences despite being told not to.
  static String _stripFences(String text) {
    final match = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$').firstMatch(text);
    return match?.group(1)?.trim() ?? text;
  }
}
