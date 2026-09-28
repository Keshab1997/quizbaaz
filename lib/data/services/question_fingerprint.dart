import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Duplicate detection for question banks.
///
/// A chapter is generated into over and over across months. Without this, the
/// model happily re-invents "What is the HCF of 96 and 404?" every third batch
/// and the bank fills with near-copies that make the quiz feel repetitive.
///
/// Two levels, because the failure has two shapes:
///
/// * [fingerprint] — an exact match after normalisation. Cheap, deterministic,
///   stored on the document so a duplicate can be rejected with one Firestore
///   lookup instead of reading the whole chapter.
/// * [similarity] — a near match. Catches "What is the HCF of 96 and 404?"
///   against "Find the HCF of 96 and 404." which normalisation alone misses.
///   Never auto-rejects; it flags for review, because a chapter legitimately
///   contains questions that differ only in their numbers.
class QuestionFingerprint {
  QuestionFingerprint._();

  /// Above this, two stems are treated as near-duplicates and flagged.
  static const double nearDuplicateThreshold = 0.85;

  /// Words too common to carry meaning when comparing two stems.
  static const Set<String> _stopWords = {
    'a',
    'an',
    'the',
    'is',
    'are',
    'was',
    'were',
    'be',
    'been',
    'of',
    'in',
    'on',
    'at',
    'to',
    'for',
    'from',
    'by',
    'with',
    'and',
    'or',
    'but',
    'if',
    'which',
    'what',
    'who',
    'whom',
    'whose',
    'when',
    'where',
    'why',
    'how',
    'this',
    'that',
    'these',
    'those',
    'it',
    'its',
    'as',
    'do',
    'does',
    'did',
    'following',
    'find',
    'given',
    'below',
    'above',
    'correct',
    'true',
    'false',
  };

  /// Strips everything that can differ without changing the question.
  ///
  /// Lowercases, replaces every run of non-alphanumeric characters with a
  /// single space, and trims. Deliberately keeps digits: "HCF of 96 and 404"
  /// and "HCF of 18 and 24" are different questions, and dropping the numbers
  /// would collapse a whole chapter of arithmetic into one fingerprint.
  static String normalise(String text) {
    final lowered = text.toLowerCase();
    final buffer = StringBuffer();
    var lastWasSpace = true;

    for (final rune in lowered.runes) {
      final isAlnum =
          (rune >= 0x30 && rune <= 0x39) || // 0-9
          (rune >= 0x61 && rune <= 0x7A) || // a-z
          rune > 0x7F; // keep Bangla/Devanagari/other scripts intact
      if (isAlnum) {
        buffer.writeCharCode(rune);
        lastWasSpace = false;
      } else if (!lastWasSpace) {
        buffer.write(' ');
        lastWasSpace = true;
      }
    }
    return buffer.toString().trim();
  }

  /// Stable hash of the normalised English stem.
  ///
  /// English is the anchor because it is the one language every question is
  /// required to have; hashing a translation would let the same question in
  /// with a slightly different Bangla rendering.
  static String fingerprint(String englishStem) {
    final normalised = normalise(englishStem);
    if (normalised.isEmpty) return '';
    return sha1.convert(utf8.encode(normalised)).toString();
  }

  /// Content words of a stem, for [similarity].
  static Set<String> tokens(String text) =>
      normalise(text)
          .split(' ')
          .where((w) => w.length > 1 && !_stopWords.contains(w))
          .toSet();

  /// Jaccard overlap of two stems, 0.0 (nothing shared) to 1.0 (identical).
  ///
  /// Jaccard rather than edit distance because word order varies freely between
  /// phrasings of the same question, and character-level distance would rank
  /// "Find the HCF of 96 and 404" as far from "What is the HCF of 96 and 404?"
  /// when they are the same question.
  static double similarity(String a, String b) {
    final ta = tokens(a);
    final tb = tokens(b);
    if (ta.isEmpty || tb.isEmpty) return 0.0;

    final intersection = ta.intersection(tb).length;
    final union = ta.union(tb).length;
    return union == 0 ? 0.0 : intersection / union;
  }

  /// The closest existing stem to [candidate], or null when nothing is close.
  ///
  /// [existing] maps question id to its English stem.
  static NearDuplicate? findNearDuplicate(
    String candidate,
    Map<String, String> existing, {
    double threshold = nearDuplicateThreshold,
  }) {
    NearDuplicate? best;
    for (final entry in existing.entries) {
      final score = similarity(candidate, entry.value);
      if (score >= threshold && (best == null || score > best.score)) {
        best = NearDuplicate(
          questionId: entry.key,
          stem: entry.value,
          score: score,
        );
      }
    }
    return best;
  }

  /// Next free sequence number for a chapter, given the ids already used.
  ///
  /// Ids look like `math_ch1_q007`. The next one is always `max + 1`, never
  /// `count + 1` — after a deletion those differ, and reusing a number would
  /// silently overwrite a question that is still in someone's quiz history.
  static int nextSequence(Iterable<String> existingIds) {
    var highest = 0;
    final pattern = RegExp(r'_q(\d+)$');
    for (final id in existingIds) {
      final match = pattern.firstMatch(id);
      if (match == null) continue;
      final value = int.tryParse(match.group(1)!) ?? 0;
      if (value > highest) highest = value;
    }
    return highest + 1;
  }

  /// Builds a question id such as `math_ch1_q042`.
  static String buildId(String chapterSlug, int sequence) =>
      '${chapterSlug}_q${sequence.toString().padLeft(3, '0')}';
}

/// A candidate question that closely resembles one already in the bank.
class NearDuplicate {
  final String questionId;
  final String stem;
  final double score;

  const NearDuplicate({
    required this.questionId,
    required this.stem,
    required this.score,
  });

  /// e.g. "0.91" — for the review screen badge.
  String get scoreLabel => score.toStringAsFixed(2);
}
