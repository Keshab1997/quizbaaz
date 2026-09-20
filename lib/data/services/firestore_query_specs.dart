import 'package:cloud_firestore/cloud_firestore.dart';

/// The single source of truth for the Firestore queries the app runs against
/// the competitive collections.
///
/// Two things kept drifting apart before this file existed:
///
/// * the query **shape** (which fields are filtered/sorted) and
/// * the **composite index** that shape needs in `firestore.indexes.json`.
///
/// A missing index is not a cosmetic problem: Firestore answers
/// `failed-precondition` and the old matchmaking code swallowed that as
/// "nobody is online". Keeping the specs here lets `test/
/// firestore_index_contract_test.dart` check every query against the deployed
/// index file, and lets the security-rules matrix assert that each challenge
/// query is participant-scoped (R17).
class FirestoreQuerySpec {
  /// Human-readable name used in test failure messages.
  final String name;

  /// Collection the query runs against.
  final String collection;

  /// Equality filters (`field: value`).
  final Map<String, Object?> equals;

  /// `whereIn` filters — the same composite index as an equality filter.
  final Map<String, List<Object?>> whereIn;

  /// `orderBy` fields with matching directions (parallel lists).
  final List<String> orderBy;

  /// True when the field is ordered descending.
  final List<bool> descending;

  final int? limit;

  /// True when the query can only ever return documents that belong to the
  /// signed-in player. Non-participant-scoped queries against
  /// `battle_challenges` / `battle_rooms` are rejected by the rules, so this
  /// flag is a hard requirement, not documentation (see `firestore.rules`).
  final bool participantScoped;

  /// Fields that are readable only by the two players of the document.
  static const List<String> participantFields = [
    'from_uid',
    'to_uid',
    'players.a.uid',
    'players.b.uid',
  ];

  const FirestoreQuerySpec({
    required this.name,
    required this.collection,
    this.equals = const {},
    this.whereIn = const {},
    this.orderBy = const [],
    this.descending = const [],
    this.limit,
    this.participantScoped = false,
  });

  /// Equality + `whereIn` fields (both consume the index prefix).
  List<String> get equalityFields =>
      [...equals.keys, ...whereIn.keys];

  /// Applies the spec to a collection reference.
  Query<Map<String, dynamic>> apply(
    CollectionReference<Map<String, dynamic>> ref,
  ) {
    Query<Map<String, dynamic>> query = ref;
    for (final entry in equals.entries) {
      query = query.where(entry.key, isEqualTo: entry.value);
    }
    for (final entry in whereIn.entries) {
      query = query.where(entry.key, whereIn: entry.value);
    }
    for (var i = 0; i < orderBy.length; i++) {
      query = query.orderBy(
        orderBy[i],
        descending: i < descending.length ? descending[i] : false,
      );
    }
    if (limit != null) query = query.limit(limit!);
    return query;
  }

  /// True when Firestore needs a composite index for this shape (more than
  /// one equality, or an orderBy on a field that is not the single equality).
  bool get needsCompositeIndex {
    if (equalityFields.length > 1) return true;
    if (orderBy.isEmpty) return false;
    return !equalityFields.contains(orderBy.first);
  }

  /// True when every filter field belongs to the two participants of the
  /// document (so a rules-enforced participant filter can be satisfied).
  bool get isParticipantScoped =>
      (!participantScoped) ||
      equalityFields.any(participantFields.contains);
}

/// Every competitive query the client runs.
class FirestoreQuerySpecs {
  FirestoreQuerySpecs._();

  static const String challengesCollection = 'battle_challenges';
  static const String queueCollection = 'battle_queue';
  static const String roomsCollection = 'battle_rooms';

  /// Matchmaking: same difficulty, freshest entrants first.
  static const queueSearch = FirestoreQuerySpec(
    name: 'queue.search',
    collection: queueCollection,
    equals: {'difficulty': null},
    orderBy: ['created_at'],
    descending: [true],
    limit: 15,
  );

  /// Duplicate-prevention check before sending a challenge, in both
  /// directions — participant-scoped by construction.
  static const challengesPendingFromTo = FirestoreQuerySpec(
    name: 'challenges.pendingFromTo',
    collection: challengesCollection,
    equals: {'from_uid': null, 'to_uid': null, 'status': null},
    limit: 2,
    participantScoped: true,
  );

  /// Incoming pending challenge for the receiver (notification banner).
  static const challengesIncoming = FirestoreQuerySpec(
    name: 'challenges.incoming',
    collection: challengesCollection,
    equals: {'to_uid': null, 'status': null},
    orderBy: ['created_at'],
    descending: [true],
    limit: 1,
    participantScoped: true,
  );

  /// Outgoing pending/accepted challenge for the sender (waiting dialog).
  static const challengesOutgoing = FirestoreQuerySpec(
    name: 'challenges.outgoing',
    collection: challengesCollection,
    equals: {'from_uid': null},
    whereIn: {
      'status': ['pending', 'accepted'],
    },
    orderBy: ['created_at'],
    descending: [true],
    limit: 1,
    participantScoped: true,
  );

  /// Every pending challenge *sent by* this player — used when they go
  /// offline so the opponent is not left waiting.
  static const challengesPendingSent = FirestoreQuerySpec(
    name: 'challenges.pendingSent',
    collection: challengesCollection,
    equals: {'from_uid': null, 'status': null},
    participantScoped: true,
  );

  /// Every pending challenge *received by* this player.
  static const challengesPendingReceived = FirestoreQuerySpec(
    name: 'challenges.pendingReceived',
    collection: challengesCollection,
    equals: {'to_uid': null, 'status': null},
    participantScoped: true,
  );

  /// Challenge documents of a leaving account (account deletion sweep).
  static const challengesBySender = FirestoreQuerySpec(
    name: 'challenges.bySender',
    collection: challengesCollection,
    equals: {'from_uid': null},
    participantScoped: true,
  );

  static const challengesByReceiver = FirestoreQuerySpec(
    name: 'challenges.byReceiver',
    collection: challengesCollection,
    equals: {'to_uid': null},
    participantScoped: true,
  );

  /// Rooms a leaving account played in (account deletion sweep).
  static const roomsByPlayerA = FirestoreQuerySpec(
    name: 'rooms.byPlayerA',
    collection: roomsCollection,
    equals: {'players.a.uid': null},
    participantScoped: true,
  );

  static const roomsByPlayerB = FirestoreQuerySpec(
    name: 'rooms.byPlayerB',
    collection: roomsCollection,
    equals: {'players.b.uid': null},
    participantScoped: true,
  );

  /// All specs — the index contract test walks this list.
  static const List<FirestoreQuerySpec> all = [
    queueSearch,
    challengesPendingFromTo,
    challengesIncoming,
    challengesOutgoing,
    challengesPendingSent,
    challengesPendingReceived,
    challengesBySender,
    challengesByReceiver,
    roomsByPlayerA,
    roomsByPlayerB,
  ];
}

/// Helper: builds a runnable query from a spec, with the real filter values.
extension FirestoreQuerySpecBinding on FirestoreQuerySpec {
  /// Returns a runnable copy of this spec with the placeholders replaced.
  ///
  /// The bound filter fields must match the spec's fields exactly — that is
  /// what keeps the deployable index file and the queries actually sent to
  /// Firestore from drifting apart. A mismatch throws here rather than
  /// failing at runtime with `failed-precondition`.
  FirestoreQuerySpec bind({
    required Map<String, Object?> equals,
    Map<String, List<Object?>> whereIn = const {},
  }) {
    final expected = {...this.equals.keys, ...this.whereIn.keys};
    final provided = {...equals.keys, ...whereIn.keys};
    if (expected.length != provided.length ||
        !expected.every(provided.contains)) {
      throw ArgumentError(
        '$name: bound filters $provided do not match the spec filters $expected',
      );
    }
    return FirestoreQuerySpec(
      name: name,
      collection: collection,
      equals: equals,
      whereIn: whereIn,
      orderBy: orderBy,
      descending: descending,
      limit: limit,
      participantScoped: participantScoped,
    );
  }
}
