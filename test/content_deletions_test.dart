import 'package:flutter_test/flutter_test.dart';
import 'package:quizbaaz/data/models/chapter_model.dart';
import 'package:quizbaaz/data/models/content_deletions.dart';
import 'package:quizbaaz/data/models/localized_text.dart';
import 'package:quizbaaz/data/repositories/quiz_repository.dart';
import 'package:quizbaaz/data/services/chapter_catalog_service.dart';

/// Deleting content must actually delete it.
///
/// A bundled chapter lives in the app's asset bundle, which an installed app
/// cannot rewrite, so the delete travels through the `config/content_deletions`
/// registry instead: every device drops the id at merge time, and
/// `tool/apply_content_deletions.py` removes the shipped JSON before the next
/// build. This file pins the two halves that keep that honest:
///
/// * the registry itself (round-trip, junk tolerance, and clearing an id when
///   the admin re-creates it);
/// * the merge filter, applied to *both* layers — a deleted chapter must go
///   whether it came from the bundle or from Firestore, and a deleted subject
///   must take its chapters with it.
void main() {
  CategoryModel category(String id, List<ChapterModel> chapters) =>
      CategoryModel(
        categoryId: id,
        nameText: LocalizedText({'en': id}),
        categoryIcon: 'assets/icons/test.png',
        colorHex: '#FFFFFF',
        totalChapters: chapters.length,
        chapters: chapters,
      );

  ChapterModel chapter(String id, {int number = 1, int questions = 5}) =>
      ChapterModel(
        chapterId: id,
        chapterNumber: number,
        titleText: LocalizedText({'en': id}),
        descriptionText: const LocalizedText({'en': 'test'}),
        totalQuestions: questions,
        jsonFile: 'assets/data/questions/$id.json',
        isUnlocked: true,
        stars: 0,
        bestScore: 0,
      );

  group('ContentDeletions', () {
    test('round-trips through JSON', () {
      const deletions = ContentDeletions(
        chapterIds: {'math_ch_01', 'sci_ch_02'},
        categoryIds: {'cat_hist'},
      );

      final restored = ContentDeletions.fromJson(deletions.toJson());

      expect(restored.chapterIds, {'math_ch_01', 'sci_ch_02'});
      expect(restored.categoryIds, {'cat_hist'});
      expect(restored.length, 3);
      expect(restored.isEmpty, isFalse);
    });

    test('tolerates a missing or messy document', () {
      final deletions = ContentDeletions.fromJson(const {
        'deleted_chapter_ids': ['a', '', '   ', 7],
      });

      expect(deletions.chapterIds, {'a', '7'});
      expect(deletions.categoryIds, isEmpty);
      expect(ContentDeletions.none.isEmpty, isTrue);
    });

    test('without() clears ids so a re-created chapter is visible', () {
      const deletions = ContentDeletions(
        chapterIds: {'a', 'b'},
        categoryIds: {'c'},
      );

      final cleared = deletions.without(chapters: ['a'], categories: ['c']);

      expect(cleared.chapterIds, {'b'});
      expect(cleared.categoryIds, isEmpty);
      // The original is untouched — the registry is rebuilt, not mutated.
      expect(deletions.chapterIds, {'a', 'b'});
    });
  });

  group('mergeWithAssets + deletions', () {
    test('drops a deleted chapter and corrects the count', () {
      final assets = [
        category('cat_math', [chapter('math_ch_01'), chapter('math_ch_02')]),
        category('cat_sci', [chapter('sci_ch_01')]),
      ];

      final merged = ChapterCatalogService.mergeWithAssets(
        assets,
        const [],
        removals: const ContentDeletions(chapterIds: {'math_ch_01'}),
      );

      final math = merged.firstWhere((c) => c.categoryId == 'cat_math');
      expect(math.chapters.map((c) => c.chapterId), ['math_ch_02']);
      expect(math.totalChapters, 1);
      // Other subjects are untouched.
      expect(merged.map((c) => c.categoryId), ['cat_math', 'cat_sci']);
    });

    test('a deleted subject takes its chapters with it', () {
      final merged = ChapterCatalogService.mergeWithAssets(
        [
          category('cat_math', [chapter('math_ch_01')]),
          category('cat_sci', [chapter('sci_ch_01')]),
        ],
        const [],
        removals: const ContentDeletions(categoryIds: {'cat_math'}),
      );

      expect(merged.map((c) => c.categoryId), ['cat_sci']);
    });

    test('a deletion also beats a Firestore override of the same id', () {
      // An override left behind by an older build must not resurrect the
      // chapter: the registry is applied after both layers are merged.
      final merged = ChapterCatalogService.mergeWithAssets(
        [
          category('cat_math', [chapter('math_ch_01')]),
        ],
        [
          category('cat_math', [chapter('math_ch_01', questions: 40)]),
        ],
        removals: const ContentDeletions(chapterIds: {'math_ch_01'}),
      );

      expect(merged.single.chapters, isEmpty);
      expect(merged.single.totalChapters, 0);
    });

    test('an empty registry changes nothing', () {
      final assets = [
        category('cat_math', [chapter('math_ch_01')]),
      ];

      final merged = ChapterCatalogService.mergeWithAssets(assets, const []);

      expect(merged.single.chapters.single.chapterId, 'math_ch_01');
      expect(merged.single.totalChapters, 1);
    });

    test(
      'mergeQuestionsById drops deleted question IDs from bundled and remote banks',
      () {
        final bundled = [
          {'id': 'q1', 'question': 'Bundled 1'},
          {'id': 'q2', 'question': 'Bundled 2'},
        ];
        final remote = [
          {'id': 'q2', 'question': 'Edited 2'},
          {'id': 'q3', 'question': 'Remote 3'},
        ];

        final merged = QuizRepository.mergeQuestionsById(
          bundled,
          remote,
          deletedIds: const {'q1', 'q3'},
        );

        expect(merged.map((q) => q['id']), ['q2']);
        expect(merged.single['question'], 'Edited 2');
      },
    );
  });
}
