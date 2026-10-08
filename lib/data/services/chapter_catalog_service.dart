import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/chapter_model.dart';
import '../models/content_deletions.dart';
import '../models/localized_text.dart';
import 'hive_service.dart';

/// Firestore storage for the subject → chapter catalogue.
///
/// The bundled `assets/data/chapters_list.json` holds the 12 subjects and 56
/// chapters the app ships with. This service holds anything the admin adds or
/// edits afterwards, and [mergeWithAssets] combines the two the same way
/// `QuizRepository` merges questions: assets are the offline floor, Firestore
/// is the live layer, Firestore wins on a clash.
///
/// Overriding by id is what makes editing a *bundled* chapter possible — the
/// admin cannot rewrite the asset file, but a Firestore document with the same
/// `chapter_id` shadows it.
///
/// ```text
/// question_categories/{categoryId}
/// question_categories/{categoryId}/chapters/{chapterId}
/// ```
class ChapterCatalogService {
  ChapterCatalogService({FirebaseFirestore? firestore})
    : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;

  /// Resolved lazily so constructing the service never touches Firebase.
  /// Callers fail soft to the bundled assets when Firestore is unreachable.
  FirebaseFirestore get _db => _firestoreOverride ?? FirebaseFirestore.instance;

  static const String categoriesCollection = 'question_categories';
  static const String chaptersSubcollection = 'chapters';
  static const String auditCollection = 'admin_audit_logs';

  /// Where the deletion registry lives.
  ///
  /// `config` rather than a collection of its own on purpose: the deployed
  /// rules already allow "read for any signed-in player, write for an admin"
  /// on every `config/{doc}`, so a delete keeps working on devices that have
  /// the current rules — no rules deploy needed to ship this.
  static const String configCollection = 'config';
  static const String deletionsDocId = 'content_deletions';

  CollectionReference<Map<String, dynamic>> get _categories =>
      _db.collection(categoriesCollection);

  CollectionReference<Map<String, dynamic>> _chapters(String categoryId) =>
      _categories.doc(categoryId).collection(chaptersSubcollection);

  // ------------------------------------------------------------------ read --

  /// Admin-authored subjects with their chapters.
  ///
  /// Returns an empty list rather than throwing when Firestore is unreachable:
  /// the caller then simply shows the bundled catalogue.
  ///
  /// Chapter overrides are also picked up through a `collectionGroup` query.
  /// A bundled subject usually has no Firestore document of its own, so hiding
  /// (or adding) one of its chapters would otherwise leave an orphan document
  /// under a missing parent — written successfully, but never returned by the
  /// parent-driven loop above, so an admin reload would "restore" the chapter.
  Future<List<CategoryModel>> fetchCategories() async {
    try {
      final categorySnapshot = await _categories.orderBy('priority').get();

      final byId = <String, CategoryModel>{};
      final order = <String>[];
      final knownChapterIds = <String, Set<String>>{};

      for (final doc in categorySnapshot.docs) {
        final chapterSnapshot =
            await _chapters(doc.id).orderBy('chapter_number').get();

        final chapters =
            chapterSnapshot.docs
                .map(
                  (c) =>
                      ChapterModel.fromJson({...c.data(), 'chapter_id': c.id}),
                )
                .toList();
        knownChapterIds[doc.id] = {for (final c in chapters) c.chapterId};
        byId[doc.id] = CategoryModel.fromJson({
          ...doc.data(),
          'category_id': doc.id,
          'chapters':
              chapterSnapshot.docs
                  .map((c) => {...c.data(), 'chapter_id': c.id})
                  .toList(),
        });
        order.add(doc.id);
      }

      // Orphan pickup: chapters whose parent subject has no Firestore document
      // (the normal case for a bundled subject). Without this, a visibility
      // toggle on such a chapter is silently lost on the next read.
      try {
        final groupSnapshot =
            await _db.collectionGroup(chaptersSubcollection).get();
        for (final doc in groupSnapshot.docs) {
          final categoryId = doc.reference.parent.parent?.id ?? '';
          if (categoryId.isEmpty) continue;
          if (knownChapterIds[categoryId]?.contains(doc.id) ?? false) continue;

          final chapter = ChapterModel.fromJson({
            ...doc.data(),
            'chapter_id': doc.id,
          });
          final existing = byId[categoryId];
          if (existing == null) {
            // Shell only: name/icon/colour come from the bundled catalogue at
            // merge time (`_mergeCategory` keeps the base for empty fields).
            byId[categoryId] = CategoryModel(
              categoryId: categoryId,
              nameText: const LocalizedText.empty(),
              categoryIcon: '',
              colorHex: '',
              totalChapters: 1,
              chapters: [chapter],
            );
            order.add(categoryId);
            knownChapterIds[categoryId] = {doc.id};
          } else {
            knownChapterIds[categoryId]!.add(doc.id);
            byId[categoryId] = CategoryModel(
              categoryId: existing.categoryId,
              nameText: existing.nameText,
              categoryIcon: existing.categoryIcon,
              colorHex: existing.colorHex,
              totalChapters: existing.chapters.length + 1,
              chapters: [...existing.chapters, chapter],
              priority: existing.priority,
            );
          }
        }
      } catch (e) {
        // The parent-driven result above is still usable — orphans just stay
        // hidden until the next successful read.
        debugPrint('ChapterCatalogService: orphan chapter scan skipped — $e');
      }

      return [for (final id in order) byId[id]!];
    } catch (e) {
      debugPrint('ChapterCatalogService: catalogue unavailable — $e');
      return const [];
    }
  }

  /// Combines the bundled catalogue with admin edits.
  ///
  /// Subjects and chapters are matched on id. A Firestore document replaces
  /// the bundled one entirely rather than merging field by field — a partial
  /// merge would leave an admin unable to *clear* a field they had set.
  ///
  /// [removals] is the deletion registry, applied last so a deleted chapter
  /// disappears whether it came from the bundle or from Firestore (see
  /// [ContentDeletions]).
  static List<CategoryModel> mergeWithAssets(
    List<CategoryModel> assets,
    List<CategoryModel> remote, {
    ContentDeletions removals = ContentDeletions.none,
  }) {
    final byId = <String, CategoryModel>{};
    final order = <String>[];

    void put(CategoryModel category) {
      if (!byId.containsKey(category.categoryId)) {
        order.add(category.categoryId);
      }
      final existing = byId[category.categoryId];
      byId[category.categoryId] =
          existing == null ? category : _mergeCategory(existing, category);
    }

    assets.forEach(put);
    remote.forEach(put);

    final merged = [for (final id in order) byId[id]!];
    if (removals.isEmpty) return merged;

    return [
      for (final category in merged)
        if (!removals.categoryIds.contains(category.categoryId))
          _withoutDeletedChapters(category, removals),
    ];
  }

  /// Drops the chapters the registry deletes, along with the subject's stale
  /// chapter count.
  static CategoryModel _withoutDeletedChapters(
    CategoryModel category,
    ContentDeletions removals,
  ) {
    final kept = [
      for (final chapter in category.chapters)
        if (!removals.chapterIds.contains(chapter.chapterId)) chapter,
    ];
    if (kept.length == category.chapters.length) return category;
    return category.copyWith(chapters: kept);
  }

  /// Chapters are merged within a subject so an admin can add a chapter to a
  /// bundled subject without redefining the whole subject.
  static CategoryModel _mergeCategory(
    CategoryModel base,
    CategoryModel override,
  ) {
    final chapters = <String, ChapterModel>{};
    final order = <String>[];

    for (final chapter in [...base.chapters, ...override.chapters]) {
      if (!chapters.containsKey(chapter.chapterId)) {
        order.add(chapter.chapterId);
      }
      chapters[chapter.chapterId] = chapter;
    }

    final merged = [for (final id in order) chapters[id]!]
      ..sort((a, b) => a.chapterNumber.compareTo(b.chapterNumber));

    return CategoryModel(
      categoryId: base.categoryId,
      nameText: override.nameText.isEmpty ? base.nameText : override.nameText,
      categoryIcon:
          override.categoryIcon.isEmpty
              ? base.categoryIcon
              : override.categoryIcon,
      colorHex: override.colorHex.isEmpty ? base.colorHex : override.colorHex,
      totalChapters: merged.length,
      chapters: merged,
      priority: override.priority != 0 ? override.priority : base.priority,
    );
  }

  // ----------------------------------------------------------------- write --

  /// Saves a reviewed AI draft in one batch so a new subject cannot be left
  /// half-created if one chapter write fails.
  Future<void> saveCategoryWithChapters({
    required String categoryId,
    required LocalizedText name,
    required String icon,
    required String colorHex,
    required int priority,
    required List<ChapterModel> chapters,
    required String actorUid,
    bool generatedByAi = false,
  }) async {
    final batch = _db.batch();
    batch.set(_categories.doc(categoryId), {
      'category_id': categoryId,
      'category_name': name.toJson(),
      'category_icon': icon,
      'color_hex': colorHex,
      'priority': priority,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': actorUid,
    }, SetOptions(merge: true));

    for (final chapter in chapters) {
      batch.set(_chapters(categoryId).doc(chapter.chapterId), {
        'chapter_id': chapter.chapterId,
        'title': chapter.titleText.toJson(),
        'description': chapter.descriptionText.toJson(),
        'chapter_number': chapter.chapterNumber,
        'is_unlocked': chapter.isUnlocked,
        'is_enabled': chapter.isEnabled,
        'json_file': chapter.jsonFile,
        'updated_at': FieldValue.serverTimestamp(),
        'updated_by': actorUid,
      }, SetOptions(merge: true));
    }

    await batch.commit();
    await _audit(
      generatedByAi ? 'ai_catalog_saved' : 'catalog_saved',
      actorUid,
      {
        'category_id': categoryId,
        'chapter_ids': [for (final chapter in chapters) chapter.chapterId],
        'generated_by_ai': generatedByAi,
      },
    );
    // A subject (or chapter) that was deleted and is saved again must come
    // back — otherwise the registry would keep hiding it forever.
    await clearDeletions(
      chapterIds: [for (final chapter in chapters) chapter.chapterId],
      categoryIds: [categoryId],
      actorUid: actorUid,
    );
    await _invalidateCatalogueCache();
  }

  /// Creates or updates a subject.
  Future<void> saveCategory({
    required String categoryId,
    required LocalizedText name,
    required String icon,
    required String colorHex,
    required int priority,
    required String actorUid,
  }) async {
    await _categories.doc(categoryId).set({
      'category_id': categoryId,
      'category_name': name.toJson(),
      'category_icon': icon,
      'color_hex': colorHex,
      'priority': priority,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': actorUid,
    }, SetOptions(merge: true));

    await _audit('category_saved', actorUid, {'category_id': categoryId});
    await clearDeletions(
      chapterIds: const [],
      categoryIds: [categoryId],
      actorUid: actorUid,
    );
    await _invalidateCatalogueCache();
  }

  /// Creates the parent subject shell when it does not exist yet.
  ///
  /// Bundled subjects live only in `assets/data/chapters_list.json`, so the
  /// first admin edit of one of their chapters would otherwise create an
  /// orphan document that older readers (parent-driven only) can never see.
  Future<void> _ensureParentCategory(String categoryId, String actorUid) async {
    try {
      final parent = await _categories.doc(categoryId).get();
      if (!parent.exists) {
        await _categories.doc(categoryId).set({
          'category_id': categoryId,
          'updated_at': FieldValue.serverTimestamp(),
          'updated_by': actorUid,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('ChapterCatalogService: parent ensure skipped — $e');
    }
  }

  /// Drops the merged catalogue cache so the next student-side read picks up
  /// the edit instead of serving the 15-minute TTL copy.
  Future<void> _invalidateCatalogueCache() async {
    try {
      if (HiveService.isInitialized) {
        await HiveService.cacheRemove(HiveService.cacheChapters);
      }
    } catch (e) {
      debugPrint('ChapterCatalogService: cache invalidate skipped — $e');
    }
  }

  /// Creates or updates a chapter inside a subject.
  ///
  /// [jsonFile] stays on the document even for admin-created chapters: it is
  /// the cache key `QuizRepository` uses, and pointing a new chapter at a path
  /// that does not exist as an asset is harmless — the asset read fails soft
  /// and only the Firestore questions are returned.
  Future<void> saveChapter({
    required String categoryId,
    required String chapterId,
    required LocalizedText title,
    required LocalizedText description,
    required int chapterNumber,
    required bool isUnlocked,
    required bool isEnabled,
    required String actorUid,
    String? jsonFile,
  }) async {
    await _ensureParentCategory(categoryId, actorUid);
    await _chapters(categoryId).doc(chapterId).set({
      'chapter_id': chapterId,
      'title': title.toJson(),
      'description': description.toJson(),
      'chapter_number': chapterNumber,
      'is_unlocked': isUnlocked,
      'is_enabled': isEnabled,
      'json_file': jsonFile ?? 'assets/data/questions/$chapterId.json',
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': actorUid,
    }, SetOptions(merge: true));

    await _audit('chapter_saved', actorUid, {
      'category_id': categoryId,
      'chapter_id': chapterId,
    });
    await clearDeletions(
      chapterIds: [chapterId],
      categoryIds: const [],
      actorUid: actorUid,
    );
    await _invalidateCatalogueCache();
  }

  /// Changes whether a chapter is visible to students without changing its
  /// learning lock. A full override is stored so toggling a bundled chapter
  /// does not erase its title, description, order, or asset mapping.
  Future<void> setChapterEnabled({
    required String categoryId,
    required ChapterModel chapter,
    required bool isEnabled,
    required String actorUid,
  }) async {
    await _ensureParentCategory(categoryId, actorUid);
    await _chapters(categoryId).doc(chapter.chapterId).set({
      'chapter_id': chapter.chapterId,
      'title': chapter.titleText.toJson(),
      'description': chapter.descriptionText.toJson(),
      'chapter_number': chapter.chapterNumber,
      'is_unlocked': chapter.isUnlocked,
      'is_enabled': isEnabled,
      'json_file': chapter.jsonFile,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': actorUid,
    }, SetOptions(merge: true));

    await _audit('chapter_visibility_changed', actorUid, {
      'category_id': categoryId,
      'chapter_id': chapter.chapterId,
      'is_enabled': isEnabled,
    });
    await _invalidateCatalogueCache();
  }

  /// Writes a new order in one batch, so the list cannot end up half-reordered.
  Future<void> reorderChapters({
    required String categoryId,
    required List<String> orderedChapterIds,
    required String actorUid,
  }) async {
    final batch = _db.batch();
    for (var i = 0; i < orderedChapterIds.length; i++) {
      batch.set(_chapters(categoryId).doc(orderedChapterIds[i]), {
        'chapter_number': i + 1,
      }, SetOptions(merge: true));
    }
    await batch.commit();

    await _audit('chapters_reordered', actorUid, {
      'category_id': categoryId,
      'order': orderedChapterIds,
    });
    await _invalidateCatalogueCache();
  }

  /// Removes a chapter's catalogue documents.
  ///
  /// A **bundled** chapter has no documents of its own, so this is a no-op for
  /// it; deleting one works through the deletion registry instead
  /// ([recordChapterDeletion]) — its JSON lives in the app bundle, which no
  /// installed app can rewrite. The chapter's question bank is deleted by the
  /// caller (`QuestionBankService.deleteChapterBank`) alongside this call, so
  /// admin-authored questions never outlive their chapter.
  Future<void> deleteChapter({
    required String categoryId,
    required String chapterId,
    required String actorUid,
  }) async {
    await _chapters(categoryId).doc(chapterId).delete();
    await _audit('chapter_deleted', actorUid, {
      'category_id': categoryId,
      'chapter_id': chapterId,
    });
    await _invalidateCatalogueCache();
  }

  // -------------------------------------------------- deletion registry --

  /// The admin's deletion registry, cached in Hive.
  ///
  /// Callers apply this in [mergeWithAssets]. When Firestore is unreachable
  /// the last registry this device saw is returned — an offline refresh must
  /// not put a deleted chapter back.
  Future<ContentDeletions> fetchDeletions() async {
    try {
      final snapshot =
          await _db.collection(configCollection).doc(deletionsDocId).get();
      final parsed =
          snapshot.exists
              ? ContentDeletions.fromJson(snapshot.data() ?? const {})
              : ContentDeletions.none;
      await HiveService.cachePut(
        HiveService.cacheContentDeletions,
        parsed.toJson(),
      );
      return parsed;
    } catch (e) {
      debugPrint('ChapterCatalogService: deletion registry unavailable — $e');
      return cachedDeletions();
    }
  }

  /// The last registry this device saw, or nothing when it has never read one.
  static ContentDeletions cachedDeletions() {
    final raw = HiveService.cacheGet(
      HiveService.cacheContentDeletions,
      allowStale: true,
    );
    if (raw is! Map) return ContentDeletions.none;
    return ContentDeletions.fromJson(Map<String, dynamic>.from(raw));
  }

  /// Records that a chapter is deleted. Works for bundled chapters too —
  /// that is the point: their JSON cannot be removed from an installed
  /// bundle, so every device learns about the removal from here.
  Future<void> recordChapterDeletion({
    required String chapterId,
    required String actorUid,
  }) => _recordDeletions(
    chapterIds: [chapterId],
    categoryIds: const [],
    actorUid: actorUid,
  );

  /// Records that a subject and its chapters are deleted, so re-creating the
  /// subject later starts empty instead of pulling its old bundled chapters
  /// back in.
  Future<void> recordCategoryDeletion({
    required String categoryId,
    required Iterable<String> chapterIds,
    required String actorUid,
  }) => _recordDeletions(
    chapterIds: chapterIds,
    categoryIds: [categoryId],
    actorUid: actorUid,
  );

  /// Drops ids from the registry — the save paths call this so a chapter or
  /// subject re-created with the same id becomes visible again.
  Future<void> clearDeletions({
    required Iterable<String> chapterIds,
    required Iterable<String> categoryIds,
    required String actorUid,
  }) async {
    final chapterList = chapterIds.where((id) => id.trim().isNotEmpty).toList();
    final categoryList =
        categoryIds.where((id) => id.trim().isNotEmpty).toList();
    if (chapterList.isEmpty && categoryList.isEmpty) return;

    var next = ContentDeletions.none;
    var changed = false;
    try {
      await _db.runTransaction((transaction) async {
        final ref = _db.collection(configCollection).doc(deletionsDocId);
        final snapshot = await transaction.get(ref);
        final current =
            snapshot.exists
                ? ContentDeletions.fromJson(snapshot.data() ?? const {})
                : ContentDeletions.none;
        next = current.without(chapters: chapterList, categories: categoryList);
        changed = next.length != current.length;
        if (!changed) return; // nothing to clear — leave the document alone
        transaction.set(ref, {
          ...next.toJson(),
          'updated_at': FieldValue.serverTimestamp(),
          'updated_by': actorUid,
        }, SetOptions(merge: true));
      });
    } catch (e) {
      debugPrint('ChapterCatalogService: deletion registry clear skipped — $e');
      return;
    }
    if (changed) {
      await HiveService.cachePut(
        HiveService.cacheContentDeletions,
        next.toJson(),
      );
    }
  }

  /// Adds ids to the registry in a transaction, so two admins deleting at the
  /// same moment cannot drop each other's entry.
  Future<void> _recordDeletions({
    required Iterable<String> chapterIds,
    required Iterable<String> categoryIds,
    required String actorUid,
  }) async {
    var next = ContentDeletions.none;
    try {
      await _db.runTransaction((transaction) async {
        final ref = _db.collection(configCollection).doc(deletionsDocId);
        final snapshot = await transaction.get(ref);
        next =
            snapshot.exists
                ? ContentDeletions.fromJson(snapshot.data() ?? const {})
                : ContentDeletions.none;
        for (final id in chapterIds) {
          if (id.trim().isNotEmpty) next = next.withChapter(id.trim());
        }
        for (final id in categoryIds) {
          if (id.trim().isNotEmpty) next = next.withCategory(id.trim());
        }
        transaction.set(ref, {
          ...next.toJson(),
          'updated_at': FieldValue.serverTimestamp(),
          'updated_by': actorUid,
        }, SetOptions(merge: true));
      });
    } catch (e) {
      // Rethrown: the caller must know the deletion did not take effect,
      // otherwise it reports a delete that a later refresh silently undoes.
      debugPrint('ChapterCatalogService: deletion registry write failed — $e');
      rethrow;
    }

    // Keep this device's copy current, so the list it reloads next is already
    // filtered without waiting for a round trip.
    await HiveService.cachePut(
      HiveService.cacheContentDeletions,
      next.toJson(),
    );
    await _invalidateCatalogueCache();
  }

  /// Removes an admin-created subject with all its chapters in one batch.
  ///
  /// A **bundled** subject has no documents of its own — nothing to remove
  /// here. Deleting one works through the deletion registry
  /// ([recordCategoryDeletion]); the caller deletes each chapter's question
  /// bank alongside this, so shipped questions (in assets) stay in the repo
  /// until `tool/apply_content_deletions.py` drops them from the bundle.
  Future<void> deleteCategory({
    required String categoryId,
    required String actorUid,
  }) async {
    final chapters = await _chapters(categoryId).get();
    if (chapters.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final doc in chapters.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(_categories.doc(categoryId));
      await batch.commit();
    } else {
      // Purely bundled: the parent document may not exist either, and a plain
      // delete of a missing document is a no-op (a batch with zero writes is
      // not always accepted, so this path stays a single delete).
      await _categories.doc(categoryId).delete();
    }

    await _audit('category_deleted', actorUid, {
      'category_id': categoryId,
      'chapter_ids': [for (final doc in chapters.docs) doc.id],
    });
    await _invalidateCatalogueCache();
  }

  Future<void> _audit(
    String action,
    String actorUid,
    Map<String, dynamic> details,
  ) async {
    try {
      await _db.collection(auditCollection).add({
        'action': action,
        'actor_uid': actorUid,
        'details': details,
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('ChapterCatalogService: audit write failed — $e');
    }
  }
}
