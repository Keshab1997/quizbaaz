import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/localized_text.dart';
import 'admin_access_service.dart';

/// One chapter row parsed from the admin's pasted list.
class BulkChapterDraft {
  final String chapterId;
  final LocalizedText title;
  final LocalizedText description;
  final int chapterNumber;

  /// Empty when the row looks fine; otherwise the reason it will be skipped.
  final String? error;

  const BulkChapterDraft({
    required this.chapterId,
    required this.title,
    required this.description,
    required this.chapterNumber,
    this.error,
  });

  bool get isValid => error == null;
}

/// Parses + saves many chapters at once, for the "ami chapter suchipatro
/// debo, AI add kore debe" flow.
///
/// Input format — one chapter per line, flexible separators:
///
/// ```text
/// Real Numbers | বাস্তব সংখ্যা | वास्तविक संख्याएँ
/// Polynomials | বহুপদী রাশি | बहुपद
/// math_ch_03 | Pair of Linear Equations | দুই চলকের রৈখিক সমীকরণ | दो चरों वाले रैखिक समीकरण
/// ```
///
/// * 3 parts → auto chapter id (`<category>_ch_<n>`), title en/bn/hi.
/// * 4 parts → explicit id + title en/bn/hi.
/// * `#` lines and blank lines are ignored.
class BulkChapterImporter {
  BulkChapterImporter._();

  /// Parses [raw] into drafts, flagging bad rows instead of throwing.
  static List<BulkChapterDraft> parse(
    String raw, {
    required String categoryId,
    required int startNumber,
    Set<String> takenIds = const {},
  }) {
    final drafts = <BulkChapterDraft>[];
    final seen = <String>{};
    var number = startNumber;
    final idStem = _idStem(categoryId);

    for (final rawLine in raw.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final parts =
          line
              .split('|')
              .map((p) => p.trim())
              .where((p) => p.isNotEmpty)
              .toList();
      if (parts.length < 3) {
        drafts.add(
          BulkChapterDraft(
            chapterId: '',
            title: const LocalizedText.empty(),
            description: const LocalizedText.empty(),
            chapterNumber: number,
            error: 'Need at least "Title EN | Title BN | Title HI"',
          ),
        );
        continue;
      }

      String id;
      LocalizedText title;
      if (parts.length >= 4 && _looksLikeId(parts[0])) {
        id = parts[0];
        title = _splitTitle(parts.sublist(1));
      } else {
        id = '${idStem}_ch_${number.toString().padLeft(2, '0')}';
        title = _splitTitle(parts);
      }
      final description = _splitDescription(title.resolve('en'));
      if (description.isNotEmpty) {
        final rest = Map<String, String>.from(title.toJson())..remove('en');
        title = LocalizedText({
          'en': _stripBracket(title.resolve('en')),
          ...rest,
        });
      }

      if (!title.has('en')) {
        drafts.add(
          BulkChapterDraft(
            chapterId: id,
            title: title,
            description: description,
            chapterNumber: number,
            error: 'English title is empty',
          ),
        );
        continue;
      }
      if (takenIds.contains(id) || seen.contains(id)) {
        drafts.add(
          BulkChapterDraft(
            chapterId: id,
            title: title,
            description: description,
            chapterNumber: number,
            error: 'Chapter id "$id" already exists — skipped',
          ),
        );
        continue;
      }

      seen.add(id);
      drafts.add(
        BulkChapterDraft(
          chapterId: id,
          title: title,
          description: description,
          chapterNumber: number,
        ),
      );
      number++;
    }
    return drafts;
  }

  /// Saves every valid draft. Never overwrites: existing ids were filtered.
  static Future<BulkChapterResult> saveAll({
    required FirebaseFirestore db,
    required String categoryId,
    required List<BulkChapterDraft> drafts,
    required String actorUid,
  }) async {
    final valid = drafts.where((d) => d.isValid).toList();
    if (valid.isEmpty) {
      return const BulkChapterResult(created: 0, skipped: 0, createdIds: []);
    }
    final batch = db.batch();
    for (final draft in valid) {
      batch.set(
        db
            .collection('question_categories')
            .doc(categoryId)
            .collection('chapters')
            .doc(draft.chapterId),
        {
          'chapter_id': draft.chapterId,
          'title': draft.title.toJson(),
          'description': draft.description.toJson(),
          'chapter_number': draft.chapterNumber,
          'is_unlocked': true,
          'is_enabled': true,
          'json_file': 'assets/data/questions/${draft.chapterId}.json',
          'updated_at': FieldValue.serverTimestamp(),
          'updated_by': actorUid,
        },
        SetOptions(merge: true),
      );
    }
    try {
      await batch.commit();
    } catch (e) {
      throw Exception(AdminAccessService.explainWriteError(e));
    }
    try {
      await db.collection('admin_audit_logs').add({
        'action': 'chapters_bulk_added',
        'actor_uid': actorUid,
        'details': {
          'category_id': categoryId,
          'chapter_ids': [for (final d in valid) d.chapterId],
        },
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('BulkChapterImporter: audit failed — $e');
    }
    return BulkChapterResult(
      created: valid.length,
      skipped: drafts.length - valid.length,
      createdIds: [for (final d in valid) d.chapterId],
    );
  }

  static LocalizedText _splitTitle(List<String> parts) {
    final map = <String, String>{};
    // The trailing "(description)" is split off by the caller, so the raw
    // English title must keep its brackets until then.
    if (parts.isNotEmpty && parts[0].trim().isNotEmpty) {
      map['en'] = parts[0].trim();
    }
    if (parts.length > 1 && parts[1].trim().isNotEmpty) {
      map['bn'] = parts[1].trim();
    }
    if (parts.length > 2 && parts[2].trim().isNotEmpty) {
      map['hi'] = parts[2].trim();
    }
    return LocalizedText(map);
  }

  static LocalizedText _splitDescription(String english) {
    final match = RegExp(r'^(.*)\(([^()]*)\)\s*$').firstMatch(english);
    if (match == null) return const LocalizedText.empty();
    final desc = match.group(2)!.trim();
    if (desc.isEmpty) return const LocalizedText.empty();
    return LocalizedText({'en': desc});
  }

  static String _stripBracket(String english) {
    final match = RegExp(r'^(.*)\(([^()]*)\)\s*$').firstMatch(english);
    if (match == null) return english;
    final stem = match.group(1)!.trim();
    return stem.isEmpty ? english : stem;
  }

  static bool _looksLikeId(String part) =>
      RegExp(r'^[a-z0-9_]+$').hasMatch(part) && part.contains('_');

  static String _idStem(String categoryId) {
    final clean = categoryId
        .replaceFirst(RegExp(r'^cat_'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return clean.isEmpty ? 'chapter' : clean;
  }
}

/// Result of a bulk chapter save.
class BulkChapterResult {
  final int created;
  final int skipped;
  final List<String> createdIds;

  const BulkChapterResult({
    required this.created,
    required this.skipped,
    required this.createdIds,
  });
}
