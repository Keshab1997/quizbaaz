import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/question_model.dart';
import 'question_fingerprint.dart';

/// Firestore storage for admin-authored questions.
class QuestionBankService {
  QuestionBankService({FirebaseFirestore? firestore})
      : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;

  /// Resolved lazily so constructing the service never touches Firebase if unconfigured.
  FirebaseFirestore? get _db {
    if (_firestoreOverride != null) return _firestoreOverride;
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  static const String banksCollection = 'question_banks';
  static const String questionsSubcollection = 'questions';
  static const String auditCollection = 'admin_audit_logs';

  /// Firestore caps a batched write at 500 operations.
  static const int _maxBatchOperations = 450;

  /// How long an admin has to undo a generated batch.
  static const Duration undoWindow = Duration(hours: 24);

  DocumentReference<Map<String, dynamic>>? _bank(String chapterId) =>
      _db?.collection(banksCollection).doc(chapterId);

  CollectionReference<Map<String, dynamic>>? _questions(String chapterId) =>
      _bank(chapterId)?.collection(questionsSubcollection);

  // ------------------------------------------------------------------ read --

  /// Every admin-authored question for a chapter, oldest id first.
  Future<List<QuestionModel>> fetchQuestions(String chapterId) async {
    final col = _questions(chapterId);
    if (col == null) return const [];
    try {
      final snapshot = await col.orderBy(FieldPath.documentId).get();
      return snapshot.docs
          .map((doc) => QuestionModel.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
    } catch (e) {
      debugPrint('QuestionBankService: fetchQuestions failed — $e');
      return const [];
    }
  }

  /// Live view of a chapter, for the admin question list.
  Stream<List<QuestionModel>> watchQuestions(String chapterId) {
    final col = _questions(chapterId);
    if (col == null) return Stream.value(const []);
    return col
        .orderBy(FieldPath.documentId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => QuestionModel.fromJson({...doc.data(), 'id': doc.id}))
            .toList());
  }

  /// Everything the generator needs to avoid repeating itself, in one read.
  Future<ChapterWriteContext> loadWriteContext(String chapterId) async {
    final col = _questions(chapterId);
    if (col == null) return ChapterWriteContext.empty(chapterId);
    try {
      final snapshot = await col.get();

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
    } catch (e) {
      debugPrint('QuestionBankService: loadWriteContext failed — $e');
      return ChapterWriteContext.empty(chapterId);
    }
  }

  /// Question count for one chapter, without downloading the questions.
  Future<int> countQuestions(String chapterId) async {
    final col = _questions(chapterId);
    if (col == null) return 0;
    try {
      final aggregate = await col.count().get();
      return aggregate.count ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Question counts for **every** chapter, in a single read.
  Future<Map<String, int>> fetchQuestionCounts() async {
    final db = _db;
    if (db == null) return const {};
    try {
      final snapshot = await db.collection(banksCollection).get();
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
  Future<AppendResult> appendQuestions({
    required String chapterId,
    required List<QuestionModel> questions,
    required String actorUid,
    String source = 'manual',
    String? model,
    String? batchId,
  }) async {
    final db = _db;
    final col = _questions(chapterId);
    if (db == null || col == null) {
      return AppendResult(
        chapterId: chapterId,
        batchId: batchId ?? '',
        writtenIds: const [],
        countBefore: 0,
        countAfter: 0,
      );
    }

    if (questions.isEmpty) {
      final count = await countQuestions(chapterId);
      return AppendResult(
        chapterId: chapterId,
        batchId: batchId ?? '',
        writtenIds: const [],
        countBefore: count,
        countAfter: count,
      );
    }

    final resolvedBatchId = batchId ??
        'batch_${DateTime.now().toUtc().millisecondsSinceEpoch}';
    final countBefore = await countQuestions(chapterId);
    final now = DateTime.now().toUtc();
    final written = <String>[];

    for (var start = 0; start < questions.length; start += _maxBatchOperations) {
      final end = (start + _maxBatchOperations).clamp(0, questions.length);
      final batch = db.batch();

      for (final question in questions.sublist(start, end)) {
        final stem = question.questionText.resolve('en');
        batch.set(col.doc(question.id), {
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

    final bankDoc = _bank(chapterId);
    if (bankDoc != null) {
      await bankDoc.set({
        'chapter_id': chapterId,
        'question_count': countAfter,
        'updated_at': FieldValue.serverTimestamp(),
        'updated_by': actorUid,
      }, SetOptions(merge: true));
    }

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
    final col = _questions(chapterId);
    if (col == null) return;
    final stem = question.questionText.resolve('en');
    await col.doc(question.id).set({
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
  Future<DeleteQuestionsResult> deleteQuestions({
    required String chapterId,
    required List<String> questionIds,
    required String actorUid,
    String auditAction = 'questions_deleted',
  }) async {
    final db = _db;
    final col = _questions(chapterId);
    final countBefore = await countQuestions(chapterId);

    if (db == null || col == null) {
      return DeleteQuestionsResult(
        deletedIds: const [],
        countBefore: countBefore,
        countAfter: countBefore,
      );
    }

    final ids = questionIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (ids.isEmpty) {
      return DeleteQuestionsResult(
        deletedIds: const [],
        countBefore: countBefore,
        countAfter: countBefore,
      );
    }

    for (var start = 0; start < ids.length; start += _maxBatchOperations) {
      final end = (start + _maxBatchOperations).clamp(0, ids.length);
      final batch = db.batch();
      for (final id in ids.sublist(start, end)) {
        batch.delete(col.doc(id));
      }
      await batch.commit();
    }

    final countAfter = await countQuestions(chapterId);
    final bankDoc = _bank(chapterId);
    if (bankDoc != null) {
      await bankDoc.set({
        'question_count': countAfter,
        'updated_at': FieldValue.serverTimestamp(),
        'updated_by': actorUid,
      }, SetOptions(merge: true));
    }

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
  Future<int> undoBatch({
    required String chapterId,
    required String batchId,
    required String actorUid,
  }) async {
    final db = _db;
    final col = _questions(chapterId);
    if (db == null || col == null) return 0;

    final snapshot = await col
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

    final batch = db.batch();
    for (final doc in removable) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    final bankDoc = _bank(chapterId);
    if (bankDoc != null) {
      await bankDoc.set({
        'question_count': await countQuestions(chapterId),
        'updated_at': FieldValue.serverTimestamp(),
        'updated_by': actorUid,
      }, SetOptions(merge: true));
    }

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
    final db = _db;
    if (db == null) return;
    try {
      await db.collection(auditCollection).add({
        'action': action,
        'chapter_id': chapterId,
        'actor_uid': actorUid,
        'details': details,
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
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
