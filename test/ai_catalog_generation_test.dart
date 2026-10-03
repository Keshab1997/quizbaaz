import 'package:flutter_test/flutter_test.dart';
import 'package:quizbaaz/data/services/admin_catalog_prompt_builder.dart';
import 'package:quizbaaz/data/services/ai_catalog_generator.dart';

const _newSubjectResponse = '''
{
  "subject": {
    "name": {"en": "Physical Science", "bn": "ভৌত বিজ্ঞান", "hi": "भौतिक विज्ञान"},
    "icon": "assets/icons/coin_and_gem_3d.png",
    "color_hex": "#112233"
  },
  "chapters": [
    {
      "title": {"en": "Chemical Reactions", "bn": "রাসায়নিক বিক্রিয়া", "hi": "रासायनिक अभिक्रियाएँ"},
      "description": {"en": "How substances change during reactions.", "bn": "বিক্রিয়ায় পদার্থের পরিবর্তন।", "hi": "अभिक्रियाओं में पदार्थों का परिवर्तन।"}
    },
    {
      "title": {"en": "Acids and Bases", "bn": "অ্যাসিড ও ক্ষার", "hi": "अम्ल और क्षार"},
      "description": {"en": "Properties and uses of acids and bases.", "bn": "অ্যাসিড ও ক্ষারের ধর্ম এবং ব্যবহার।", "hi": "अम्ल और क्षार के गुण और उपयोग।"}
    }
  ]
}
''';

void main() {
  group('AI catalogue parser', () {
    test('parses a trilingual subject and chapters', () {
      final draft = parseAiCatalogDraft(
        _newSubjectResponse,
        requireSubject: true,
        expectedCount: 2,
      );

      expect(draft.subjectName!.resolve('en'), 'Physical Science');
      expect(draft.subjectName!.resolve('bn'), 'ভৌত বিজ্ঞান');
      expect(draft.colorHex, '#112233');
      expect(draft.chapters, hasLength(2));
      expect(draft.chapters.first.title.resolve('hi'), 'रासायनिक अभिक्रियाएँ');
    });

    test('markdown fences and duplicate chapters are safe', () {
      const response = '''
```json
{
  "chapters": [
    {"title": {"en": "Existing", "bn": "আগের", "hi": "पहला"}},
    {"title": {"en": "New Chapter", "bn": "নতুন", "hi": "नया"}},
    {"title": {"en": "New Chapter", "bn": "নতুন ২", "hi": "नया २"}}
  ]
}
```
''';
      final draft = parseAiCatalogDraft(
        response,
        requireSubject: false,
        expectedCount: 2,
        existingChapterTitles: const ['Existing'],
      );

      expect(draft.chapters, hasLength(1));
      expect(draft.chapters.single.title.resolve('en'), 'New Chapter');
      expect(draft.warnings, hasLength(3));
    });

    test('missing languages are not saved', () {
      expect(
        () => parseAiCatalogDraft(
          '{"chapters":[{"title":{"en":"Only English"}}]}',
          requireSubject: false,
          expectedCount: 1,
        ),
        throwsA(isA<AiCatalogGenerationException>()),
      );
    });
  });

  group('AI catalogue prompts', () {
    test('new subject prompt asks for the exact requested count', () {
      final prompt = AdminCatalogPromptBuilder.buildNewSubjectPrompt(
        request: 'Class 10 physical science for WBBSE',
        chapterCount: 6,
      );
      expect(prompt, contains('exactly 6 chapters'));
      expect(prompt, contains('Class 10 physical science for WBBSE'));
      expect(prompt, contains('"subject"'));
      expect(prompt, contains('Bangla and Hindi'));
    });

    test('existing subject prompt includes chapters to avoid', () {
      final prompt = AdminCatalogPromptBuilder.buildChaptersPrompt(
        subjectName: 'Mathematics',
        request: 'Add geometry chapters',
        chapterCount: 2,
        existingChapterTitles: const ['Real Numbers', 'Polynomials'],
      );
      expect(prompt, contains('Real Numbers'));
      expect(prompt, contains('Polynomials'));
      expect(prompt, contains('exactly 2 new chapters'));
      expect(prompt, contains('Do not repeat an existing chapter'));
    });
  });
}
