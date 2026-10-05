import 'package:flutter_test/flutter_test.dart';
import 'package:quizbaaz/data/services/ai_syllabus_importer.dart';

void main() {
  group('AiSyllabusImporter.buildPrompt', () {
    test('carries subject, numbering, id format and the syllabus', () {
      final prompt = AiSyllabusImporter.buildPrompt(
        subjectName: 'General Science',
        categoryId: 'cat_gscience',
        startNumber: 6,
        syllabusText: 'Chapter 1\nPhysics (পদার্থবিদ্যা)',
      );

      expect(prompt, contains('General Science'));
      expect(prompt, contains('cat_gscience'));
      expect(prompt, contains('gscience_ch_06'));
      expect(prompt, contains('6, 7, ...'));
      expect(prompt, contains('Return ONLY a raw JSON array'));
      expect(prompt, contains('"title.en" is required'));
      expect(prompt, contains('Chapter 1\nPhysics (পদার্থবিদ্যা)'));
    });
  });

  group('AiSyllabusImporter.parseAnswer', () {
    test('parses a fenced JSON array into trilingual drafts', () {
      const answer =
          '```json\n'
          '[{"id": "gs_ch_06", "number": 6, '
          '"title": {"en": "Physics", "bn": "পদার্থবিদ্যা", "hi": "भौतिक विज्ञान"}, '
          '"description": {"en": "Motion, light and sound"}}]\n'
          '```';

      final drafts = AiSyllabusImporter.parseAnswer(
        answer,
        categoryId: 'cat_gscience',
        startNumber: 6,
      );

      expect(drafts, hasLength(1));
      final draft = drafts.single;
      expect(draft.isValid, isTrue);
      expect(draft.chapterId, 'gs_ch_06');
      expect(draft.chapterNumber, 6);
      expect(draft.title.resolve('bn'), 'পদার্থবিদ্যা');
      expect(draft.description.resolve('en'), 'Motion, light and sound');
    });

    test('missing ids and numbers are auto-assigned', () {
      const answer =
          '[{"title": {"en": "Physics"}}, '
          '{"title": "Chemistry"}]';

      final drafts = AiSyllabusImporter.parseAnswer(
        answer,
        categoryId: 'cat_gscience',
        startNumber: 6,
      );

      expect(drafts.map((d) => d.chapterId).toList(), [
        'gscience_ch_06',
        'gscience_ch_07',
      ]);
      expect(drafts.map((d) => d.chapterNumber).toList(), [6, 7]);
      expect(drafts.every((d) => d.isValid), isTrue);
      // A bare string title is English-only shorthand.
      expect(drafts[1].title.resolve('en'), 'Chemistry');
    });

    test('taken and duplicate ids are skipped, not overwritten', () {
      const answer =
          '[{"id": "gs_ch_06", "number": 6, '
          '"title": {"en": "Taken"}}, '
          '{"id": "gs_ch_07", "number": 7, "title": {"en": "Fresh"}}, '
          '{"id": "gs_ch_07", "number": 8, "title": {"en": "Dup"}}]';

      final drafts = AiSyllabusImporter.parseAnswer(
        answer,
        categoryId: 'cat_gscience',
        startNumber: 6,
        takenIds: {'gs_ch_06'},
      );

      expect(drafts, hasLength(3));
      expect(drafts[0].isValid, isFalse);
      expect(drafts[0].error, contains('already exists'));
      expect(drafts[1].isValid, isTrue);
      expect(drafts[2].isValid, isFalse);
      expect(drafts[2].error, contains('already exists'));
    });

    test('rows without an English title are flagged', () {
      const answer =
          '[{"id": "gs_ch_06", "number": 6, '
          '"title": {"bn": "পদার্থবিদ্যা"}}]';

      final drafts = AiSyllabusImporter.parseAnswer(
        answer,
        categoryId: 'cat_gscience',
        startNumber: 6,
      );

      expect(drafts.single.isValid, isFalse);
      expect(drafts.single.error, contains('English title is empty'));
    });

    test('non-array answers throw a readable FormatException', () {
      expect(
        () => AiSyllabusImporter.parseAnswer(
          '{"id": "gs_ch_06"}',
          categoryId: 'cat_gscience',
          startNumber: 1,
        ),
        throwsFormatException,
      );
      expect(
        () => AiSyllabusImporter.parseAnswer(
          'not json at all',
          categoryId: 'cat_gscience',
          startNumber: 1,
        ),
        throwsFormatException,
      );
    });
  });
}
