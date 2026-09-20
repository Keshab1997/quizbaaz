import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizbaaz/data/services/firestore_query_specs.dart';

/// R17 — every competitive query the app runs must have a composite index in
/// `firestore.indexes.json`, and every challenge/room query must be
/// participant-scoped (the rules deny the rest).
///
/// This is the part of the "staging query matrix" that can be checked without
/// a live project: the shapes are declared once in [FirestoreQuerySpecs], the
/// services build their queries by binding those specs (a field-name mismatch
/// throws), and this test proves each shape is actually deployable.
void main() {
  late Map<String, dynamic> indexesFile;

  setUpAll(() {
    final raw = File('firestore.indexes.json').readAsStringSync();
    indexesFile = jsonDecode(raw) as Map<String, dynamic>;
  });

  List<Map<String, dynamic>> indexes() =>
      (indexesFile['indexes'] as List).cast<Map<String, dynamic>>();

  /// A query needs a composite index when it combines several equality filters
  /// or an equality filter with an orderBy on another field. Single-field
  /// queries are covered by Firestore's automatic indexes.
  bool indexCovers(FirestoreQuerySpec spec, Map<String, dynamic> index) {
    if (index['collectionGroup'] != spec.collection &&
        index['collectionId'] != spec.collection) {
      return false;
    }
    final fields = (index['fields'] as List).cast<Map<String, dynamic>>();
    final names = [for (final f in fields) f['fieldPath'] as String];

    // Equality filters may appear in any order at the front of the index.
    final equalities = spec.equalityFields.toSet();
    if (equalities.isEmpty) return false;
    var next = 0;
    while (next < names.length && equalities.contains(names[next])) {
      next++;
    }
    if (next < equalities.length) return false;

    // Then the orderBy fields, in order, with matching directions.
    for (var i = 0; i < spec.orderBy.length; i++) {
      if (next + i >= names.length) return false;
      if (names[next + i] != spec.orderBy[i]) return false;
      final direction = fields[next + i]['order'] as String? ?? 'ASCENDING';
      final wantsDescending =
          i < spec.descending.length ? spec.descending[i] : false;
      if (wantsDescending && direction != 'DESCENDING') return false;
    }
    return true;
  }

  test('every spec is well formed', () {
    for (final spec in FirestoreQuerySpecs.all) {
      expect(spec.collection, isNotEmpty, reason: spec.name);
      expect(spec.orderBy.length, spec.descending.length, reason: spec.name);
      expect(spec.name, isNotEmpty);
    }
    // Names are unique — a duplicate would silently shadow a query shape.
    final names = FirestoreQuerySpecs.all.map((s) => s.name).toList();
    expect(names.toSet().length, names.length);
  });

  test('each query shape has a deployable index (or needs none)', () {
    final missing = <String>[];
    for (final spec in FirestoreQuerySpecs.all) {
      if (!spec.needsCompositeIndex) continue;
      final covered = indexes().any((index) => indexCovers(spec, index));
      if (!covered) missing.add(spec.name);
    }
    expect(
      missing,
      isEmpty,
      reason: 'these queries would fail with failed-precondition: $missing',
    );
  });

  test('every declared index is one of the app\'s query shapes', () {
    // A stale index is not dangerous, but it usually means a query was
    // changed without the index following it.
    final names = FirestoreQuerySpecs.all.map((s) => s.name).join(', ');
    for (final index in indexes()) {
      final collection =
          index['collectionGroup'] ?? index['collectionId'] ?? '';
      if (collection == 'questions' ||
          collection == 'admin_audit_logs' ||
          collection == 'scores') {
        continue; // content admin + leaderboard indexes, not battle queries
      }
      expect(
        FirestoreQuerySpecs.all.any((spec) => spec.collection == collection),
        isTrue,
        reason: 'index for $collection matches no spec ($names)',
      );
    }
  });

  test('challenge and room queries are participant-scoped', () {
    final shared = FirestoreQuerySpecs.all.where(
      (spec) =>
          spec.collection == FirestoreQuerySpecs.challengesCollection ||
          spec.collection == FirestoreQuerySpecs.roomsCollection,
    );
    expect(shared, isNotEmpty);
    for (final spec in shared) {
      expect(
        spec.isParticipantScoped,
        isTrue,
        reason:
            '${spec.name} filters on ${spec.equalityFields} — the rules only '
            'allow participant-scoped reads on ${spec.collection}',
      );
      expect(
        spec.equalityFields
            .any((field) => FirestoreQuerySpec.participantFields.contains(field)),
        isTrue,
        reason: '${spec.name} must filter by a participant field',
      );
    }
  });

  test('binding a spec with the wrong fields fails loudly', () {
    expect(
      () => FirestoreQuerySpecs.challengesIncoming.bind(
        equals: {'to_uid': 'uid-a'}, // missing 'status'
      ),
      throwsArgumentError,
    );
    expect(
      () => FirestoreQuerySpecs.queueSearch.bind(
        equals: {'difficulty_nope': 'normal'},
      ),
      throwsArgumentError,
    );
    // The correct binding is accepted.
    final bound = FirestoreQuerySpecs.challengesIncoming
        .bind(equals: {'to_uid': 'uid-a', 'status': 'pending'});
    expect(bound.equalityFields, containsAll(['to_uid', 'status']));
    expect(bound.orderBy, ['created_at']);
    expect(bound.descending, [true]);
  });

  test('challenge expiry is a TTL policy, not a client sweep', () {
    final overrides =
        (indexesFile['fieldOverrides'] as List).cast<Map<String, dynamic>>();
    final ttl = overrides.where(
      (o) =>
          o['collectionGroup'] == 'battle_challenges' &&
          o.containsKey('ttlConfig'),
    );
    expect(
      ttl,
      isNotEmpty,
      reason: 'battle_challenges needs a TTL policy on expires_at_ts',
    );
    expect(ttl.first['fieldPath'], 'expires_at_ts');
  });
}
