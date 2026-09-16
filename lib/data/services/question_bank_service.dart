import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/question_model.dart';
import 'question_fingerprint.dart';

/// Firestore storage for admin-authored questions.
///
/// ## Why Firestore and not the JSON assets
///
/// The bundled banks under `assets/data/` are read-only at runtime, so an
/// admin on a phone cannot write to them. Admin content therefore lives here
/// and is merged with the assets by `QuizRepository`: assets are the offline
/// floor that every fresh install has, Firestore is the live layer that grows
/// without an app release.
///
/// ## The append guarantee
///
/// This service is the only thing that writes questions, and it is written so
/// that losing an existing question is not possible by accident:
///
/// * a question's **id is its document id**, and writes are `set()` on that
///   id — re-running a batch overwrites those same documents rather than
///   creating a second copy;
/// * there is **no method that deletes a collection**. [deleteQuestion] and
///   [deleteQuestions] require explicit IDs, so the admin can remove one
///   reviewed set without ever clearing a chapter by accident;
/// * new ids come from [QuestionFingerprint.nextSequence], which is `max + 1`
///   over the ids already present, never `count + 1` — after a deletion those
///   differ, and reusing a number would silently replace a live question;
/// * every write is mirrored to `admin_audit_logs` with the batch id, so a bad
///   batch can be found and undone.
///
/// Collection layout:
///
/// ```text
/// question_banks/{chapterId}                      chapter meta + counter
/// question_banks/{chapterId}/questions/{id}       one document per question
/// ```
class QuestionBankService {
  QuestionBankService({FirebaseFirestore? firestore})
      : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;

  /// Resolved lazily so constructing the service never touches Firebase.
  /// Hive is the source of truth; Firestore is only a mirror. This keeps
  /// the app (and widget tests) working with no network / no Firebase app.
  FirebaseFirestore get _db => _firestoreOverride ?? FirebaseFirestore.instance;

  static const String banksCollection = 'question_banks';
  static const String questionsSubcollection = 'questions';
  static const String auditCollection = 'admin_audit_logs';

  /// Firestore caps a batched write at 500 operations.
  static const int _maxBatchOperations = 450;

  /// How long an admin has to undo a generated batch.
  static const Duration undoWindow = Duration(hours: 24);

  DocumentReference<Map<String, dynamic>> _bank(String chapterId) =>
      _db.collection(banksCollection).doc(chapterId);

  CollectionReference<Map<String, dynamic>> _questions(String chapterId) =>
      _bank(chapterId).collection(questionsSubcollection);

  // ------------------------------------------------------------------ read --

  /// Every admin-authored question for a chapter, oldest id first.
  Future<List<QuestionModel>> fetchQuestions(String chapterId) async {
    final snapshot = await _questions(chapterId).orderBy(FieldPath.documentId).get();
    return snapshot.docs
        .map((doc) => QuestionModel.fromJson({...doc.data(), 'id': doc.id}))
        .toList();
  }

  /// Live view of a chapter, for the admin question list.
  Stream<List<QuestionModel>> watchQuestions(String chapterId) {
    return _questions(chapterId)
        .orderBy(FieldPath.documentId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => QuestionModel.fromJson({...doc.data(), 'id': doc.id}))
            .toList());
  }

  /// Everything the generator needs to avoid repeating itself, in one read.
  ///
  /// Returned together because they are always wanted together, and a chapter
  /// with 300 questions should be read once per generation, not three times.
  Future<ChapterWriteContext> loadWriteContext(String chapterId) async {
    final snapshot = await _questions(chapterId).get();

    final ids = <String>[];
    final stems = <String, String>{};
    final fingerprints = <String>{};

    for (final doc in snapshot.docs) {
      ids.add(doc.id);
      final data = doc.data();

      final stored = data['fingerprint'];
      final question = QuestionModel.fromJson({...data, 'id': doc.id});
      final stem = question.questionText.resolve('en');

      if (stem.isNotEmpty) stems[doc.id] = stem;
      fingerprints.add(stored is String && stored.isNotEmpty
          ? stored
          : QuestionFingerprint.fingerprint(stem));
    }

    return ChapterWriteContext(
      chapterId: chapterId,
      existingIds: ids,
      existingStems: stems,
      existingFingerprints: fingerprints..remove(''),
    );
  }

  /// Question count for one chapter, without downloading the questions.
  Future<int> countQuestions(String chapterId) async {
    final aggregate = await _questions(chapterId).count().get();
    return aggregate.count ?? 0;
  }

  /// Question counts for **every** chapter, in a single read.
  ///
  /// Reads the `question_banks` documents rather than counting each
  /// subcollection: the chapter list needs 56 numbers at once, and 56
  /// aggregate queries is both slow and needlessly expensive. The counter on
  /// each document is maintained by [appendQuestions], [deleteQuestion] and
  /// [undoBatch].
  ///
  /// Returns an empty map when Firestore is unreachable, so the caller falls
  /// back to the counts bundled in the assets.
  Future<Map<String, int>> fetchQuestionCounts() async {
    try {
      final snapshot = await _db.collection(banksCollection).get();
      return {
        for (final doc in snapshot.docs)
          doc.id: (doc.data()['question_count'] as num?)?.toInt() ?? 0,
      };
    } catch (e) {
      debugPrint('QuestionBankService: counts unavailable — $e');
      return const {};
    }
  }

  // ----------------------------------------------------------------- write --

  /// Appends [questions] to a chapter. Never removes anything.
  ///
  /// Returns the ids written. Callers get the before/after counts through
  /// [AppendResult] so the UI can show "47 → 55" rather than a bare success.
  Future<AppendResult> appendQuestions({
    required String chapterId,
    required List<QuestionModel> questions,
    required String actorUid,
    String source = 'manual',
    String? model,
    String? batchId,
  }) async {
    if (questions.isEmpty) {
      return AppendResult(
        chapterId: chapterId,
        batchId: batchId ?? '',
        writtenIds: const [],
        countBefore: await countQuestions(chapterId),
        countAfter: await countQuestions(chapterId),
      );
    }

    final resolvedBatchId = batchId ??
        'batch_${DateTime.now().toUtc().millisecondsSinceEpoch}';
    final countBefore = await countQuestions(chapterId);
    final now = DateTime.now().toUtc();
    final written = <String>[];

    // Chunked so a large import cannot exceed Firestore's per-batch limit.
    for (var start = 0; start < questions.length; start += _maxBatchOperations) {
      final end = (start + _maxBatchOperations).clamp(0, questions.length);
      final batch = _db.batch();

      for (final question in questions.sublist(start, end)) {
        final stem = question.questionText.resolve('en');
        // set() on an explicit id: idempotent, and structurally incapable of
        // touching any other document in the chapter.
        batch.set(_questions(chapterId).doc(question.id), {
          ...question.toJson(),
          'fingerprint': QuestionFingerprint.fingerprint(stem),
          'source': source,
          if (model != null) 'model': model,
          'batch_id': resolvedBatchId,
          'created_by': actorUid,
          'created_at': Timestamp.fromDate(now),
          'reviewed': true,
        });
        written.add(question.id);
      }

      await batch.commit();
    }

    final countAfter = await countQuestions(chapterId);

    await _bank(chapterId).set({
      'chapter_id': chapterId,
      'question_count': countAfter,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': actorUid,
    }, SetOptions(merge: true));

    await _writeAudit(
      action: 'questions_appended',
      chapterId: chapterId,
      actorUid: actorUid,
      details: {
        'batch_id': resolvedBatchId,
        'source': source,
        if (model != null) 'model': model,
        'question_ids': written,
        'count_before': countBefore,
        'count_after': countAfter,
      },
    );

    return AppendResult(
      chapterId: chapterId,
      batchId: resolvedBatchId,
      writtenIds: written,
      countBefore: countBefore,
      countAfter: countAfter,
    );
  }

  /// Updates one existing question in place.
  Future<void> updateQuestion({
    required String chapterId,
    required QuestionModel question,
    required String actorUid,
  }) async {
    final stem = question.questionText.resolve('en');
    await _questions(chapterId).doc(question.id).set({
      ...question.toJson(),
      'fingerprint': QuestionFingerprint.fingerprint(stem),
      'updated_by': actorUid,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _writeAudit(
      action: 'question_updated',
      chapterId: chapterId,
      actorUid: actorUid,
      details: {'question_id': question.id},
    );
  }

  /// Deletes exactly one question.
  Future<void> deleteQuestion({
    required String chapterId,
    required String questionId,
    required String actorUid,
  }) async {
    await deleteQuestions(
      chapterId: chapterId,
      questionIds: [questionId],
      actorUid: actorUid,
      auditAction: 'question_deleted',
    );
  }

  /// Permanently deletes only the explicitly named questions.
  ///
  /// The IDs are de-duplicated before writes and chunked below Firestore's
  /// batch limit. There is intentionally no variant that accepts a chapter ID
  /// alone, so this cannot become a "clear all questions" operation.
  Future<DeleteQuestionsResult> deleteQuestions({
    required String chapterId,
    required List<String> questionIds,
    required String actorUid,
    String auditAction = 'questions_deleted',
  }) async {
    final ids = questionIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final countBefore = await countQuestions(chapterId);

    if (ids.isEmpty) {
      return DeleteQuestionsResult(
        deletedIds: const [],
        countBefore: countBefore,
        countAfter: countBefore,
      );
    }

    for (var start = 0; start < ids.length; start += _maxBatchOperations) {
      final end = (start + _maxBatchOperations).clamp(0, ids.length);
      final batch = _db.batch();
      for (final id in ids.sublist(start, end)) {
        batch.delete(_questions(chapterId).doc(id));
      }
      await batch.commit();
    }

    final countAfter = await countQuestions(chapterId);
    await _bank(chapterId).set({
      'question_count': countAfter,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': actorUid,
    }, SetOptions(merge: true));

    await _writeAudit(
      action: auditAction,
      chapterId: chapterId,
      actorUid: actorUid,
      details: {
        'question_ids': ids,
        if (ids.length == 1) 'question_id': ids.single,
        'requested_count': ids.length,
        'count_before': countBefore,
        'count_after': countAfter,
      },
    );

    return DeleteQuestionsResult(
      deletedIds: ids,
      countBefore: countBefore,
      countAfter: countAfter,
    );
  }

  /// Removes only the questions written by [batchId], within [undoWindow].
  ///
  /// The escape hatch for "that batch was rubbish". It is scoped to the ids of
  /// one generation run, so questions added before or after are untouched.
  Future<int> undoBatch({
    required String chapterId,
    required String batchId,
    required String actorUid,
  }) async {
    final snapshot = await _questions(chapterId)
        .where('batch_id', isEqualTo: batchId)
        .get();

    if (snapshot.docs.isEmpty) return 0;

    final cutoff = DateTime.now().toUtc().subtract(undoWindow);
    final removable = snapshot.docs.where((doc) {
      final created = doc.data()['created_at'];
      if (created is! Timestamp) return false;
      return created.toDate().isAfter(cutoff);
    }).toList();

    if (removable.isEmpty) return 0;

    final batch = _db.batch();
    for (final doc in removable) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    await _bank(chapterId).set({
      'question_count': await countQuestions(chapterId),
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': actorUid,
    }, SetOptions(merge: true));

    await _writeAudit(
      action: 'batch_undone',
      chapterId: chapterId,
      actorUid: actorUid,
      details: {
        'batch_id': batchId,
        'removed': removable.map((d) => d.id).toList(),
      },
    );

    return removable.length;
  }

  // ------------------------------------------------------------------ audit --

  Future<void> _writeAudit({
    required String action,
    required String chapterId,
    required String actorUid,
    required Map<String, dynamic> details,
  }) async {
    try {
      await _db.collection(auditCollection).add({
        'action': action,
        'chapter_id': chapterId,
        'actor_uid': actorUid,
        'details': details,
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // An audit failure must never lose the content write that preceded it.
      debugPrint('QuestionBankService: audit write failed — $e');
    }
  }
}

/// Result of permanently removing explicitly selected questions.
class DeleteQuestionsResult {
  final List<String> deletedIds;
  final int countBefore;
  final int countAfter;

  const DeleteQuestionsResult({
    required this.deletedIds,
    required this.countBefore,
    required this.countAfter,
  });

  int get deletedCount => deletedIds.length;
}

/// Everything needed to append to a chapter without repeating or overwriting.
class ChapterWriteContext {
  final String chapterId;
  final List<String> existingIds;

  /// Question id → English stem, for near-duplicate detection.
  final Map<String, String> existingStems;

  /// Exact-match hashes of the stems already present.
  final Set<String> existingFingerprints;

  const ChapterWriteContext({
    required this.chapterId,
    required this.existingIds,
    required this.existingStems,
    required this.existingFingerprints,
  });

  const ChapterWriteContext.empty(this.chapterId)
      : existingIds = const [],
        existingStems = const {},
        existingFingerprints = const {};

  int get questionCount => existingIds.length;

  /// The next free sequence number for this chapter.
  int get nextSequence => QuestionFingerprint.nextSequence(existingIds);
}

/// Outcome of an append, carrying the counts the UI reports back to the admin.
class AppendResult {
  final String chapterId;
  final String batchId;
  final List<String> writtenIds;
  final int countBefore;
  final int countAfter;

  const AppendResult({
    required this.chapterId,
    required this.batchId,
    required this.writtenIds,
    required this.countBefore,
    required this.countAfter,
  });

  int get added => countAfter - countBefore;

  /// e.g. "47 → 55 questions" — the confirmation that nothing was lost.
  String get countLabel => '$countBefore → $countAfter questions';
}
