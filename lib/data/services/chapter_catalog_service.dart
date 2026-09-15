import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/chapter_model.dart';
import '../models/localized_text.dart';

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
  FirebaseFirestore get _db =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  static const String categoriesCollection = 'question_categories';
  static const String chaptersSubcollection = 'chapters';
  static const String auditCollection = 'admin_audit_logs';

  CollectionReference<Map<String, dynamic>> get _categories =>
      _db.collection(categoriesCollection);

  CollectionReference<Map<String, dynamic>> _chapters(String categoryId) =>
      _categories.doc(categoryId).collection(chaptersSubcollection);

  // ------------------------------------------------------------------ read --

  /// Admin-authored subjects with their chapters.
  ///
  /// Returns an empty list rather than throwing when Firestore is unreachable:
  /// the caller then simply shows the bundled catalogue.
  Future<List<CategoryModel>> fetchCategories() async {
    try {
      final categorySnapshot =
          await _categories.orderBy('priority').get();

      final categories = <CategoryModel>[];
      for (final doc in categorySnapshot.docs) {
        final chapterSnapshot =
            await _chapters(doc.id).orderBy('chapter_number').get();

        categories.add(CategoryModel.fromJson({
          ...doc.data(),
          'category_id': doc.id,
          'chapters': chapterSnapshot.docs
              .map((c) => {...c.data(), 'chapter_id': c.id})
              .toList(),
        }));
      }
      return categories;
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
  static List<CategoryModel> mergeWithAssets(
    List<CategoryModel> assets,
    List<CategoryModel> remote,
  ) {
    final byId = <String, CategoryModel>{};
    final order = <String>[];

    void put(CategoryModel category) {
      if (!byId.containsKey(category.categoryId)) {
        order.add(category.categoryId);
      }
      final existing = byId[category.categoryId];
      byId[category.categoryId] = existing == null
          ? category
          : _mergeCategory(existing, category);
    }

    assets.forEach(put);
    remote.forEach(put);

    return [for (final id in order) byId[id]!];
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
          override.categoryIcon.isEmpty ? base.categoryIcon : override.categoryIcon,
      colorHex: override.colorHex.isEmpty ? base.colorHex : override.colorHex,
      totalChapters: merged.length,
      chapters: merged,
    );
  }

  // ----------------------------------------------------------------- write --

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
    required String actorUid,
    String? jsonFile,
  }) async {
    await _chapters(categoryId).doc(chapterId).set({
      'chapter_id': chapterId,
      'title': title.toJson(),
      'description': description.toJson(),
      'chapter_number': chapterNumber,
      'is_unlocked': isUnlocked,
      'json_file': jsonFile ?? 'assets/data/questions/$chapterId.json',
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': actorUid,
    }, SetOptions(merge: true));

    await _audit('chapter_saved', actorUid, {
      'category_id': categoryId,
      'chapter_id': chapterId,
    });
  }

  /// Writes a new order in one batch, so the list cannot end up half-reordered.
  Future<void> reorderChapters({
    required String categoryId,
    required List<String> orderedChapterIds,
    required String actorUid,
  }) async {
    final batch = _db.batch();
    for (var i = 0; i < orderedChapterIds.length; i++) {
      batch.set(
        _chapters(categoryId).doc(orderedChapterIds[i]),
        {'chapter_number': i + 1},
        SetOptions(merge: true),
      );
    }
    await batch.commit();

    await _audit('chapters_reordered', actorUid, {
      'category_id': categoryId,
      'order': orderedChapterIds,
    });
  }

  /// Removes an admin-created chapter.
  ///
  /// A **bundled** chapter cannot be removed this way — deleting the override
  /// document just restores the asset version, which is the right behaviour:
  /// the app must keep working for someone who never syncs. Its questions in
  /// `question_banks/{chapterId}` are deliberately left alone.
  Future<void> deleteChapter({
    required String categoryId,
    required String chapterId,
    required String actorUid,
  }) async {
    await _chapters(categoryId).doc(chapterId).delete();
    await _audit('chapter_deleted', actorUid, {
      'category_id': categoryId,
      'chapter_id': chapterId,
      'note': 'questions retained in question_banks',
    });
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
