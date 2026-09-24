import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/chapter_model.dart';
import '../models/daily_quiz_packet.dart';
import '../models/question_model.dart';
import '../repositories/quiz_repository.dart';
import 'competition_clock.dart';
import 'hive_service.dart';

/// What the daily-quiz screen plays: either the day's published competition
/// set, or a practice set.
///
/// [ranked] is the field that matters. A ranked run is the one the backend can
/// score: same packet, same version, same question ids for everybody, and the
/// score is a comparable one. A practice run is what the app plays when the
/// packet is missing, incomplete, already closed or simply not resolvable
/// offline — it is still a real quiz (coins, stats, streak), but it is **never
/// submitted as a competition result** (R12).
class DailyQuizSet {
  final List<QuestionModel> questions;
  final bool ranked;
  final DailyQuizPacket? packet;

  /// Why a run is not ranked (for debug logging / the result screen).
  final String? unrankedReason;

  const DailyQuizSet({
    required this.questions,
    required this.ranked,
    this.packet,
    this.unrankedReason,
  });

  bool get isEmpty => questions.isEmpty;

  static const DailyQuizSet empty = DailyQuizSet(
    questions: [],
    ranked: false,
    unrankedReason: 'no questions available',
  );
}

/// Fetches and resolves the backend-published daily packet.
///
/// Collection: `daily_quiz_packets/{yyyy-MM-dd}` (competition timezone), written
/// by the trusted backend only (`allow write: if false` in `firestore.rules`).
///
/// ```text
/// {
///   date_key: '2026-09-20',
///   version: 3,
///   questions: [{chapter_id: 'bio_ch_01', question_id: 'bio_ch_01_q004'}, …],
///   count: 10,
///   deadline_ms: 1789…,          // end of the competition day, UTC
///   scoring_contract: 'v1',
///   approved: true,
///   published_at: 1789…
/// }
/// ```
class DailyQuizPacketService {
  DailyQuizPacketService({
    FirebaseFirestore? firestore,
    QuizRepository? repository,
  })  : _firestoreOverride = firestore,
        _repository = repository ?? QuizRepository();

  final FirebaseFirestore? _firestoreOverride;
  final QuizRepository _repository;

  static const String collection = 'daily_quiz_packets';

  /// A resolved set is cached for the rest of the competition day; the packet
  /// itself is re-checked when this window has passed (a re-issued packet
  /// bumps `version`, which changes the cache key anyway).
  static const Duration packetTtl = Duration(minutes: 30);

  FirebaseFirestore get _db =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  /// Cache key for the packet document of a day.
  static String packetCacheKey(String dateKey) => 'daily_quiz_packet_$dateKey';

  /// The packet for [dateKey], read from the cache first and from Firestore
  /// when the cache is stale or missing. Null when neither has one.
  Future<DailyQuizPacket?> loadPacket(
    String dateKey, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = HiveService.cacheGet(packetCacheKey(dateKey), maxAge: packetTtl);
      if (cached is Map) {
        final packet = DailyQuizPacket.fromJson(dateKey, cached);
        if (packet != null) return packet;
      }
    }

    try {
      final snap = await _db.collection(collection).doc(dateKey).get();
      if (!snap.exists) {
        debugPrint('DailyQuizPacket: no packet published for $dateKey');
        return null;
      }
      final packet = DailyQuizPacket.fromJson(dateKey, snap.data());
      if (packet == null) return null;
      await HiveService.cachePut(packetCacheKey(dateKey), packet.toJson());
      return packet;
    } catch (e) {
      debugPrint('DailyQuizPacket: fetch failed for $dateKey – $e');
      // Offline: fall back to whatever this device already stored, however
      // old it is — a stale packet still describes today's set.
      final cached = HiveService.cacheGet(
        packetCacheKey(dateKey),
        allowStale: true,
      );
      if (cached is Map) return DailyQuizPacket.fromJson(dateKey, cached);
      return null;
    }
  }

  /// Resolves the competition set for the competition day of [now].
  ///
  /// Returns a ranked [DailyQuizSet] only when the packet exists, is approved,
  /// complete, still open and every question id resolves from the merged banks.
  /// Anything else is returned as an unranked (practice) set with a reason.
  Future<DailyQuizSet> resolve({
    DateTime? now,
    bool forceRefresh = false,
  }) async {
    final moment = (now ?? DateTime.now()).toUtc();
    final dateKey = CompetitionClock.dateKey(moment);

    final packet = await loadPacket(dateKey, forceRefresh: forceRefresh);
    if (packet == null) {
      return DailyQuizSet(
        questions: const [],
        ranked: false,
        unrankedReason: 'no packet published for $dateKey',
      );
    }

    final rejection = packet.rejectionReason;
    if (rejection != null) {
      return DailyQuizSet(
        questions: const [],
        ranked: false,
        packet: packet,
        unrankedReason: rejection,
      );
    }

    if (!packet.isOpen(moment)) {
      return DailyQuizSet(
        questions: const [],
        ranked: false,
        packet: packet,
        unrankedReason: 'packet for $dateKey closed at deadline',
      );
    }

    // Both devices of the same day/version share this cache: a device that
    // played earlier (or refreshed while online) serves the identical set
    // offline.
    final cachedRows = HiveService.cacheGetList(
      packet.cacheKey,
      maxAge: const Duration(hours: 24),
    );
    if (cachedRows.isNotEmpty && !forceRefresh) {
      return DailyQuizSet(
        questions: cachedRows.map(QuestionModel.fromJson).toList(),
        ranked: true,
        packet: packet,
      );
    }

    final resolved = await _resolveQuestions(packet);
    if (resolved.length != packet.questions.length) {
      // The chapter-bank caches are served stale-first and refreshed in the
      // background (see QuizRepository._revalidateIfStale). On the FIRST run
      // of the day there is no resolved-packet cache yet, so the packet's
      // ids are resolved against yesterday's bank — and any question the
      // admin published with today's packet is still missing. Declaring the
      // run unranked here silently threw away the player's first attempt
      // (no leaderboard entry, no daily best) while the background refresh
      // quietly fixed the cache, so the SECOND attempt was ranked.
      //
      // Retry once with a blocking, forced refresh before giving up: the
      // player's first attempt must not lose its ranking to a cache race.
      debugPrint(
        'DailyQuizPacket: only ${resolved.length} of '
        '${packet.questions.length} ids resolved from cache — retrying '
        'with forced refresh',
      );
      final refreshed = await _resolveQuestions(packet, forceRefresh: true);
      if (refreshed.length != packet.questions.length) {
        return DailyQuizSet(
          questions: refreshed,
          ranked: false,
          packet: packet,
          unrankedReason:
              'only ${refreshed.length} of ${packet.questions.length} packet '
              'questions could be loaded',
        );
      }
      await HiveService.cachePut(
        packet.cacheKey,
        [for (final q in refreshed) q.toJson()],
      );
      return DailyQuizSet(
        questions: refreshed,
        ranked: true,
        packet: packet,
      );
    }

    await HiveService.cachePut(
      packet.cacheKey,
      [for (final q in resolved) q.toJson()],
    );
    return DailyQuizSet(
      questions: resolved,
      ranked: true,
      packet: packet,
    );
  }

  /// Loads the questions the packet names, **in packet order** (order is part
  /// of the competition: question 1 has to be question 1 on every device).
  ///
  /// [forceRefresh] bypasses the chapter-bank caches and merges from Firestore
  /// synchronously — used by the retry in [resolve] so a stale cache cannot
  /// cost a player their ranked first attempt of the day.
  Future<List<QuestionModel>> _resolveQuestions(
    DailyQuizPacket packet, {
    bool forceRefresh = false,
  }) async {
    final byChapter = <String, Set<String>>{};
    for (final ref in packet.questions) {
      byChapter.putIfAbsent(ref.chapterId, () => <String>{}).add(ref.questionId);
    }

    final found = <String, QuestionModel>{};
    for (final entry in byChapter.entries) {
      final chapterId = entry.key;
      final wanted = entry.value;
      try {
        final chapter = await _chapterById(
          chapterId,
          forceRefresh: forceRefresh,
        );
        if (chapter == null) {
          debugPrint('DailyQuizPacket: unknown chapter $chapterId');
          continue;
        }
        final questions = await _repository.getChapterQuestions(
          chapter.jsonFile,
          chapterId: chapterId,
          forceRefresh: forceRefresh,
        );
        for (final question in questions) {
          if (wanted.contains(question.id)) found[question.id] = question;
        }
      } catch (e) {
        debugPrint('DailyQuizPacket: chapter $chapterId failed – $e');
      }
    }

    return [
      for (final ref in packet.questions)
        if (found[ref.questionId] != null) found[ref.questionId]!,
    ];
  }

  Future<ChapterModel?> _chapterById(
    String chapterId, {
    bool forceRefresh = false,
  }) async {
    final categories = await _repository.getCategoriesAndChapters(
      forceRefresh: forceRefresh,
    );
    for (final category in categories) {
      for (final chapter in category.chapters) {
        if (chapter.chapterId == chapterId) return chapter;
      }
    }
    return null;
  }
}
