/// Prompts used by the admin's AI subject/chapter authoring flow.
///
/// The model drafts catalogue metadata only. The admin reviews the result and
/// the app assigns permanent ids before anything is written to Firestore.
class AdminCatalogPromptBuilder {
  AdminCatalogPromptBuilder._();

  static String buildNewSubjectPrompt({
    required String request,
    required int chapterCount,
    String syllabus = 'West Bengal Board (WBBSE) and CBSE Class 10',
  }) {
    return '''
You are an academic curriculum editor for a $syllabus quiz app used by Bengali-speaking students.

The admin wants to add a new subject and exactly $chapterCount chapters.
Request or topic:
${request.trim().isEmpty ? 'Choose a suitable Class 10 subject and its main syllabus chapters.' : request.trim()}

Output ONLY one JSON object, with no prose and no markdown fence:
{
  "subject": {
    "name": {"en": "...", "bn": "...", "hi": "..."},
    "icon": "assets/icons/coin_and_gem_3d.png",
    "color_hex": "#53E6FF"
  },
  "chapters": [
    {
      "title": {"en": "...", "bn": "...", "hi": "..."},
      "description": {"en": "...", "bn": "...", "hi": "..."}
    }
  ]
}

Rules:
* Return exactly $chapterCount chapters, in the normal teaching order.
* Translate subject name, chapter title and description into English, Bangla and Hindi.
* Use standard WBBSE/CBSE textbook terminology; do not transliterate technical words.
* Keep descriptions to one short sentence explaining what the chapter teaches.
* Do not include ids, question data, fake chapter numbers, or extra keys.
* The subject must be a real Class 10 academic subject, not a vague category.
''';
  }

  static String buildChaptersPrompt({
    required String subjectName,
    required String request,
    required int chapterCount,
    required List<String> existingChapterTitles,
    String syllabus = 'West Bengal Board (WBBSE) and CBSE Class 10',
  }) {
    final existing =
        existingChapterTitles.isEmpty
            ? 'None — this subject has no chapters yet.'
            : existingChapterTitles.map((title) => '- $title').join('\n');

    return '''
You are an academic curriculum editor for a $syllabus quiz app used by Bengali-speaking students.

Subject: $subjectName
Add exactly $chapterCount new chapters for this subject.
Admin request or topic:
${request.trim().isEmpty ? 'Suggest the next logical chapters in the syllabus.' : request.trim()}

Chapters already present — never repeat these:
$existing

Output ONLY one JSON object, with no prose and no markdown fence:
{
  "chapters": [
    {
      "title": {"en": "...", "bn": "...", "hi": "..."},
      "description": {"en": "...", "bn": "...", "hi": "..."}
    }
  ]
}

Rules:
* Return exactly $chapterCount chapters, in the normal teaching order.
* Translate every title and description into English, Bangla and Hindi.
* Use standard textbook terminology; do not transliterate technical words.
* Keep descriptions to one short sentence explaining what the chapter teaches.
* Do not repeat an existing chapter or include ids, question data, or extra keys.
''';
  }
}
