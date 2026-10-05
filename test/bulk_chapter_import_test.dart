import 'package:flutter_test/flutter_test.dart';
import 'package:quizbaaz/data/services/bulk_chapter_importer.dart';

void main() {
  group('BulkChapterImporter.parse', () {
    test('three-part line gets auto id and trilingual title', () {
      // Held in variables so input and expectation are the *same* code
      // points — Bengali conjuncts can differ byte-wise when retyped.
      const en = 'Real Numbers';
      const bn = 'বাস্তব সংখ্যা';
      const hi = 'वास्तविक संख्याएँ';
      final drafts = BulkChapterImporter.parse(
        '$en | $bn | $hi',
        categoryId: 'cat_math',
        startNumber: 15,
      );

      expect(drafts, hasLength(1));
      final draft = drafts.single;
      expect(draft.isValid, isTrue);
      expect(draft.chapterId, 'math_ch_15');
      expect(draft.chapterNumber, 15);
      expect(draft.title.resolve('en'), en);
      expect(draft.title.resolve('bn'), bn);
      expect(draft.title.resolve('hi'), hi);
    });

    test('four-part line with explicit id keeps the id', () {
      final drafts = BulkChapterImporter.parse(
        'math_ch_03 | Pair of Linear Equations | x | y',
        categoryId: 'cat_math',
        startNumber: 1,
      );

      expect(drafts.single.isValid, isTrue);
      expect(drafts.single.chapterId, 'math_ch_03');
      expect(drafts.single.title.resolve('en'), 'Pair of Linear Equations');
      expect(drafts.single.title.resolve('bn'), 'x');
      expect(drafts.single.title.resolve('hi'), 'y');
    });

    test('blank lines and # comments are ignored', () {
      final drafts = BulkChapterImporter.parse(
        '# syllabus note\n\n   \nCh1 | bn | hi',
        categoryId: 'cat_math',
        startNumber: 1,
      );

      expect(drafts, hasLength(1));
      expect(drafts.single.chapterId, 'math_ch_01');
    });

    test('duplicate ids inside the paste are skipped, not overwritten', () {
      final drafts = BulkChapterImporter.parse(
        'A | bn | hi\nmath_ch_01 | Dup | bn2 | hi2',
        categoryId: 'cat_math',
        startNumber: 1,
      );

      expect(drafts, hasLength(2));
      expect(drafts[0].isValid, isTrue);
      expect(drafts[0].chapterId, 'math_ch_01');
      expect(drafts[1].isValid, isFalse);
      expect(drafts[1].error, contains('already exists'));
    });

    test('ids already taken are skipped', () {
      final drafts = BulkChapterImporter.parse(
        'math_ch_01 | Taken | bn | hi',
        categoryId: 'cat_math',
        startNumber: 1,
        takenIds: {'math_ch_01'},
      );

      expect(drafts.single.isValid, isFalse);
      expect(drafts.single.error, contains('already exists'));
    });

    test('line with fewer than three parts is flagged', () {
      final drafts = BulkChapterImporter.parse(
        'Only English',
        categoryId: 'cat_math',
        startNumber: 1,
      );

      expect(drafts.single.isValid, isFalse);
      expect(drafts.single.error, contains('Title EN'));
    });

    test('trailing (description) splits out an English description', () {
      final drafts = BulkChapterImporter.parse(
        'Real Numbers (Euclid division, HCF/LCM) | bn | hi',
        categoryId: 'cat_math',
        startNumber: 1,
      );

      final draft = drafts.single;
      expect(draft.isValid, isTrue);
      expect(draft.title.resolve('en'), 'Real Numbers');
      expect(draft.description.resolve('en'), 'Euclid division, HCF/LCM');
    });

    test('auto ids increment without colliding within one paste', () {
      final drafts = BulkChapterImporter.parse(
        'A | bn | hi\nB | bn | hi\nC | bn | hi',
        categoryId: 'cat_math',
        startNumber: 1,
      );

      expect(drafts.map((d) => d.chapterId).toList(), [
        'math_ch_01',
        'math_ch_02',
        'math_ch_03',
      ]);
    });

    test('suggestChapterId matches the ids parse() generates', () {
      expect(BulkChapterImporter.suggestChapterId('cat_math', 7), 'math_ch_07');
      final drafts = BulkChapterImporter.parse(
        'A | bn | hi',
        categoryId: 'cat_math',
        startNumber: 7,
      );
      expect(drafts.single.chapterId, 'math_ch_07');
    });
  });
}
