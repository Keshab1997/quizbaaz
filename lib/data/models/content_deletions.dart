/// What the admin has deleted, as one registry.
///
/// A bundled chapter or subject lives inside the app's asset bundle, and no
/// installed app can rewrite its own bundle — so a delete cannot remove those
/// bytes at runtime. Instead the delete records the id here, in Firestore
/// (`config/content_deletions`):
///
/// * every running app drops the id when it merges the bundled catalogue with
///   the Firestore layer, so deleted content disappears for players too;
/// * `tool/apply_content_deletions.py` reads the same list and removes the
///   JSON from `assets/data/` in the repo, so the next build does not ship it
///   either.
///
/// One record, two effects — and a device that is offline keeps the last
/// registry it saw (`ChapterCatalogService.cachedDeletions`), so a failed
/// refresh can never resurrect content the admin deleted.
class ContentDeletions {
  final Set<String> chapterIds;
  final Set<String> categoryIds;

  const ContentDeletions({
    this.chapterIds = const <String>{},
    this.categoryIds = const <String>{},
  });

  /// Nothing has been deleted.
  static const ContentDeletions none = ContentDeletions();

  bool get isEmpty => chapterIds.isEmpty && categoryIds.isEmpty;

  int get length => chapterIds.length + categoryIds.length;

  /// Whether the registry hides this chapter. A deleted subject hides every
  /// chapter under it without listing each one.
  bool hidesChapter(String categoryId, String chapterId) =>
      categoryIds.contains(categoryId) || chapterIds.contains(chapterId);

  ContentDeletions withChapter(String id) =>
      chapterIds.contains(id)
          ? this
          : ContentDeletions(
            chapterIds: {...chapterIds, id},
            categoryIds: categoryIds,
          );

  ContentDeletions withCategory(String id) =>
      categoryIds.contains(id)
          ? this
          : ContentDeletions(
            chapterIds: chapterIds,
            categoryIds: {...categoryIds, id},
          );

  /// The registry without [chapters] / [categories] — the save paths use this
  /// so re-creating an id makes it visible again.
  ContentDeletions without({
    Iterable<String> chapters = const [],
    Iterable<String> categories = const [],
  }) => ContentDeletions(
    chapterIds: {...chapterIds}..removeAll(chapters),
    categoryIds: {...categoryIds}..removeAll(categories),
  );

  factory ContentDeletions.fromJson(Map<String, dynamic> json) =>
      ContentDeletions(
        chapterIds: _ids(json['deleted_chapter_ids']),
        categoryIds: _ids(json['deleted_category_ids']),
      );

  Map<String, dynamic> toJson() => {
    'deleted_chapter_ids': chapterIds.toList()..sort(),
    'deleted_category_ids': categoryIds.toList()..sort(),
  };

  static Set<String> _ids(Object? raw) => {
    if (raw is List)
      for (final id in raw)
        if (id.toString().trim().isNotEmpty) id.toString().trim(),
  };
}
