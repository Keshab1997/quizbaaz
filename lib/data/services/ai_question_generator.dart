import 'dart:async';
import 'dart:convert';

import 'package:admin_api_key_manager/admin_api_key_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/chapter_model.dart';
import '../models/question_model.dart';
import 'question_fingerprint.dart';
import 'question_prompt_builder.dart';
import 'question_validator.dart';

/// Where a generation run currently is, for the progress bar.
enum GenerationStage {
  starting,
  requesting,
  validating,
  retrying,
  done,
  failed,
}

/// A snapshot of progress, emitted as the run proceeds.
class GenerationProgress {
  final GenerationStage stage;
  final int requested;
  final int accepted;
  final int rejected;
  final int round;
  final String message;

  /// Populated once the run finishes.
  final List<GeneratedQuestion> results;

  const GenerationProgress({
    required this.stage,
    required this.requested,
    this.accepted = 0,
    this.rejected = 0,
    this.round = 1,
    this.message = '',
    this.results = const [],
  });

  double get fraction =>
      requested == 0 ? 0 : (accepted / requested).clamp(0.0, 1.0);

  bool get isTerminal =>
      stage == GenerationStage.done || stage == GenerationStage.failed;
}

/// A draft question plus everything the review screen needs to judge it.
class GeneratedQuestion {
  final QuestionModel question;
  final ValidationResult validation;

  /// Verdict from the second-opinion pass, when it ran.
  final VerificationVerdict? verification;

  const GeneratedQuestion({
    required this.question,
    required this.validation,
    this.verification,
  });

  /// True when nothing at all needs the admin's attention.
  bool get isClean => validation.isClean && (verification?.agrees ?? true);

  GeneratedQuestion copyWith({
    QuestionModel? question,
    ValidationResult? validation,
    VerificationVerdict? verification,
  }) {
    return GeneratedQuestion(
      question: question ?? this.question,
      validation: validation ?? this.validation,
      verification: verification ?? this.verification,
    );
  }
}

/// The second model's opinion on whether the marked answer is right.
class VerificationVerdict {
  /// `ok`, `wrong` or `unsure`.
  final String verdict;
  final int? suggestedIndex;
  final String reason;

  const VerificationVerdict({
    required this.verdict,
    this.suggestedIndex,
    this.reason = '',
  });

  bool get agrees => verdict == 'ok';
  bool get disagrees => verdict == 'wrong';
  bool get unsure => verdict == 'unsure';
}

/// Raised when generation cannot even start, with wording an admin can act on.
class GenerationException implements Exception {
  final String message;
  const GenerationException(this.message);

  @override
  String toString() => message;
}

/// Generates trilingual questions through the admin API key pool.
///
/// ## Why it is shaped like this
///
/// **Chunks of five, not one batch of ten.** A model asked for ten complete
/// trilingual questions in one response drifts near the end: the last two lose
/// their Hindi, or the JSON truncates. Two requests of five come back complete
/// far more often, and a failure costs half as much to redo.
///
/// **Rejected drafts are regenerated, not dropped.** "Generate 10" has to mean
/// ten offered. Anything the validator rejects is replaced in a follow-up
/// round, up to [maxRounds], with the rejection reasons fed back into the
/// prompt so the model does not repeat the same mistake.
///
/// **Nothing is written here.** This produces drafts for the review screen;
/// `QuestionBankService.appendQuestions` is the only thing that writes, and
/// only after the admin approves.
class AiQuestionGenerator {
  AiQuestionGenerator({ApiKeyManager? keyManager, http.Client? client})
    : _keys = keyManager ?? ApiKeyManager.instance,
      _client = client ?? http.Client();

  final ApiKeyManager _keys;
  final http.Client _client;

  /// Questions per request. See the class doc for why this is not 10.
  static const int chunkSize = 5;

  /// How many top-up rounds may run before giving up on the shortfall.
  static const int maxRounds = 3;

  static const Duration _requestTimeout = Duration(seconds: 120);

  static const String _feature = 'question_generation';

  /// Generates [count] questions for [chapter], emitting progress as it goes.
  ///
  /// Never throws for a per-request failure — those are reported through the
  /// stream. Throws [GenerationException] only when there is no usable key,
  /// which is a setup problem the admin must fix.
  Stream<GenerationProgress> generate({
    required ChapterModel chapter,
    required String subjectName,
    required String idPrefix,
    required int startSequence,
    int count = 10,
    List<String> existingStems = const [],
    Set<String> existingFingerprints = const {},
    DifficultyMix difficulty = DifficultyMix.balanced,
    bool verify = false,
    String actorUid = 'admin',
  }) async* {
    yield GenerationProgress(
      stage: GenerationStage.starting,
      requested: count,
      message: 'Preparing…',
    );

    if (_keys.peekFirstKey() == null) {
      await _keys.ensureReady();
    }
    if (_keys.peekFirstKey() == null) {
      yield GenerationProgress(
        stage: GenerationStage.failed,
        requested: count,
        message: 'No usable API key. Add one in Admin → API Keys.',
      );
      return;
    }

    final accepted = <GeneratedQuestion>[];
    final rejectedReasons = <String>[];

    // Duplicate state grows as the run proceeds, so a later chunk cannot
    // repeat something an earlier chunk already produced.
    final stems = <String, String>{
      for (var i = 0; i < existingStems.length; i++)
        'existing_$i': existingStems[i],
    };
    final fingerprints = Set<String>.from(existingFingerprints);

    var rejectedCount = 0;
    var sequence = startSequence;

    for (var round = 1; round <= maxRounds; round++) {
      final shortfall = count - accepted.length;
      if (shortfall <= 0) break;

      if (round > 1) {
        yield GenerationProgress(
          stage: GenerationStage.retrying,
          requested: count,
          accepted: accepted.length,
          rejected: rejectedCount,
          round: round,
          message: 'Replacing $shortfall rejected…',
        );
      }

      for (var offset = 0; offset < shortfall; offset += chunkSize) {
        final want = (shortfall - offset).clamp(1, chunkSize);

        yield GenerationProgress(
          stage: GenerationStage.requesting,
          requested: count,
          accepted: accepted.length,
          rejected: rejectedCount,
          round: round,
          message:
              'Writing ${accepted.length + 1}–'
              '${(accepted.length + want).clamp(1, count)} of $count…',
        );

        final prompt = QuestionPromptBuilder.buildGenerationPrompt(
          chapter: chapter,
          subjectName: subjectName,
          count: want,
          idPrefix: idPrefix,
          startSequence: sequence,
          existingStems: [
            ...stems.values,
            // Feed back what was just rejected so the same mistake is not
            // simply reproduced in the replacement round.
            ...rejectedReasons.take(5),
          ],
          difficulty: difficulty,
        );

        final raw = await _callModel(prompt, actorUid: actorUid);
        if (raw == null) {
          yield GenerationProgress(
            stage: GenerationStage.failed,
            requested: count,
            accepted: accepted.length,
            rejected: rejectedCount,
            round: round,
            message: 'Every key failed. Check Admin → API Keys.',
            results: accepted,
          );
          return;
        }

        final parsed = _parseQuestions(raw);
        if (parsed.isEmpty) {
          rejectedCount += want;
          rejectedReasons.add('previous response was not valid JSON');
          continue;
        }

        yield GenerationProgress(
          stage: GenerationStage.validating,
          requested: count,
          accepted: accepted.length,
          rejected: rejectedCount,
          round: round,
          message: 'Checking ${parsed.length}…',
        );

        for (final question in parsed) {
          if (accepted.length >= count) break;

          // Ids are assigned here rather than trusted from the model: it
          // routinely restarts numbering, and a clashing id would overwrite a
          // question that already exists.
          final renumbered = _withId(
            question,
            QuestionFingerprint.buildId(idPrefix, sequence),
          );

          final result = QuestionValidator.validate(
            renumbered,
            existingStems: stems,
            existingFingerprints: fingerprints,
          );

          if (!result.isAcceptable) {
            rejectedCount++;
            rejectedReasons.add(renumbered.questionText.resolve('en'));
            continue;
          }

          sequence++;
          final stem = renumbered.questionText.resolve('en');
          stems[renumbered.id] = stem;
          final fingerprint = QuestionFingerprint.fingerprint(stem);
          if (fingerprint.isNotEmpty) fingerprints.add(fingerprint);

          accepted.add(
            GeneratedQuestion(question: renumbered, validation: result),
          );
        }
      }
    }

    // ------------------------------------------------------- verification --
    var results = accepted;
    if (verify && accepted.isNotEmpty) {
      final verified = <GeneratedQuestion>[];
      for (var i = 0; i < accepted.length; i++) {
        yield GenerationProgress(
          stage: GenerationStage.validating,
          requested: count,
          accepted: accepted.length,
          rejected: rejectedCount,
          message: 'Double-checking answer ${i + 1} of ${accepted.length}…',
        );
        verified.add(
          accepted[i].copyWith(
            verification: await _verify(accepted[i].question, actorUid),
          ),
        );
      }
      results = verified;
    }

    yield GenerationProgress(
      stage: GenerationStage.done,
      requested: count,
      accepted: results.length,
      rejected: rejectedCount,
      message:
          results.length < count
              ? 'Produced ${results.length} of $count — '
                  '$rejectedCount draft(s) did not pass the checks.'
              : 'Ready for review.',
      results: results,
    );
  }

  /// Translates one field into bn and hi, for the admin forms.
  Future<Map<String, String>?> translateField(String english) async {
    final raw = await _callModel(
      QuestionPromptBuilder.buildFieldTranslationPrompt(english),
      actorUid: 'admin',
    );
    if (raw == null) return null;

    final decoded = _decodeJsonObject(raw);
    if (decoded == null) return null;

    return {
      for (final code in ['bn', 'hi'])
        if (decoded[code] is String &&
            (decoded[code] as String).trim().isNotEmpty)
          code: (decoded[code] as String).trim(),
    };
  }

  // ------------------------------------------------------------ transport --

  /// One model call, tried against every healthy key in turn.
  ///
  /// Returns null only when the pool is exhausted. Success and failure are
  /// reported back to [ApiKeyManager] so cooldowns, failover and the admin's
  /// error stats all stay accurate.
  Future<String?> _callModel(String prompt, {required String actorUid}) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      final key = _keys.getNextKey();
      if (key == null) return null;

      try {
        final response = await _request(key, prompt);

        if (response.statusCode == 200) {
          _keys.reportSuccess(key);
          final text = _extractText(key.provider, response.bodyBytes);
          if (text != null && text.trim().isNotEmpty) return text;

          // A 200 with nothing usable in it is still a failure of this key.
          _keys.reportFailure(key, 200, _feature, actorUid);
          continue;
        }

        _keys.reportFailure(key, response.statusCode, _feature, actorUid);
      } catch (e) {
        debugPrint('AiQuestionGenerator: ${key.name} failed — $e');
        _keys.reportFailure(key, 0, _feature, actorUid);
      }
    }
    return null;
  }

  Future<http.Response> _request(AdminApiKey key, String prompt) {
    if (key.provider == 'google') {
      // Gemini: the key goes in the query string and there is no system role,
      // so the instruction is prepended to the user turn.
      final uri = Uri.parse(
        '${key.baseUrl}/models/${key.model}:generateContent?key=${key.key}',
      );
      return _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {
                      'text':
                          '${QuestionPromptBuilder.systemPrompt()}\n\n$prompt',
                    },
                  ],
                },
              ],
              'generationConfig': {
                'temperature': 0.7,
                'maxOutputTokens': 8192,
                // Gemini can be told to emit JSON, which removes a whole class
                // of parse failures.
                'responseMimeType': 'application/json',
              },
            }),
          )
          .timeout(_requestTimeout);
    }

    return _client
        .post(
          Uri.parse('${key.baseUrl}/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${key.key}',
          },
          body: jsonEncode({
            'model': resolveOpenRouterModel(key.baseUrl, key.model),
            'messages': [
              {
                'role': 'system',
                'content': QuestionPromptBuilder.systemPrompt(),
              },
              {'role': 'user', 'content': prompt},
            ],
            'temperature': 0.7,
            'max_tokens': 8192,
          }),
        )
        .timeout(_requestTimeout);
  }

  /// Pulls the assistant's text out of whichever response shape came back.
  static String? _extractText(String provider, List<int> bodyBytes) {
    try {
      final body = jsonDecode(utf8.decode(bodyBytes));
      if (body is! Map) return null;

      if (provider == 'google') {
        final candidates = body['candidates'];
        if (candidates is! List || candidates.isEmpty) return null;
        final parts = candidates.first?['content']?['parts'];
        if (parts is! List || parts.isEmpty) return null;
        return parts.first?['text'] as String?;
      }

      final choices = body['choices'];
      if (choices is! List || choices.isEmpty) return null;
      return choices.first?['message']?['content'] as String?;
    } catch (e) {
      debugPrint('AiQuestionGenerator: could not read response — $e');
      return null;
    }
  }

  // --------------------------------------------------------------- parsing --

  /// Extracts a JSON array of questions from a model response.
  ///
  /// Tolerant on purpose: models wrap JSON in ```json fences, prepend "Here
  /// are your questions:", or return a single object instead of an array.
  /// None of that is worth burning a retry on.
  ///
  /// Private, with the top-level [parseGeneratedQuestions] as the tested
  /// entry point — `@visibleForTesting` is meaningless on a private member.
  static List<QuestionModel> _parseQuestions(String raw) {
    final cleaned = _stripFence(raw);

    dynamic decoded;
    try {
      decoded = jsonDecode(cleaned);
    } catch (_) {
      final slice = _sliceArray(cleaned);
      if (slice == null) return const [];
      try {
        decoded = jsonDecode(slice);
      } catch (_) {
        return const [];
      }
    }

    // A single object is a valid answer to "write 1 question".
    final list = decoded is List ? decoded : [decoded];

    final questions = <QuestionModel>[];
    for (final entry in list) {
      if (entry is! Map) continue;
      try {
        questions.add(QuestionModel.fromJson(Map<String, dynamic>.from(entry)));
      } catch (e) {
        debugPrint('AiQuestionGenerator: skipped malformed question — $e');
      }
    }
    return questions;
  }

  static Map<String, dynamic>? _decodeJsonObject(String raw) {
    final cleaned = _stripFence(raw);
    try {
      final decoded = jsonDecode(cleaned);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      final start = cleaned.indexOf('{');
      final end = cleaned.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      try {
        final decoded = jsonDecode(cleaned.substring(start, end + 1));
        return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
      } catch (_) {
        return null;
      }
    }
  }

  static String _stripFence(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      final firstNewline = text.indexOf('\n');
      if (firstNewline > 0) text = text.substring(firstNewline + 1);
      final closing = text.lastIndexOf('```');
      if (closing >= 0) text = text.substring(0, closing);
    }
    return text.trim();
  }

  /// Finds the outermost `[ … ]` in text that has prose around it.
  static String? _sliceArray(String text) {
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start < 0 || end <= start) return null;
    return text.substring(start, end + 1);
  }

  static QuestionModel _withId(QuestionModel question, String id) {
    return QuestionModel(
      id: id,
      questionText: question.questionText,
      optionTexts: question.optionTexts,
      correctIndex: question.correctIndex,
      explanationText: question.explanationText,
      points: question.points,
      timeLimitSec: question.timeLimitSec,
    );
  }

  // ---------------------------------------------------------- verification --

  Future<VerificationVerdict?> _verify(
    QuestionModel question,
    String actorUid,
  ) async {
    final raw = await _callModel(
      QuestionPromptBuilder.buildVerificationPrompt(
        questionEn: question.questionText.resolve('en'),
        optionsEn: question.optionsIn('en'),
        markedIndex: question.correctIndex,
        explanationEn: question.explanationText.resolve('en'),
      ),
      actorUid: actorUid,
    );
    if (raw == null) return null;

    final decoded = _decodeJsonObject(raw);
    if (decoded == null) return null;

    final verdict = (decoded['verdict'] as String?)?.toLowerCase().trim();
    if (verdict == null) return null;

    return VerificationVerdict(
      verdict:
          const {'ok', 'wrong', 'unsure'}.contains(verdict)
              ? verdict
              : 'unsure',
      suggestedIndex: (decoded['correct_index'] as num?)?.toInt(),
      reason: (decoded['reason'] as String?)?.trim() ?? '',
    );
  }
}

/// Exposed for tests: parsing is the part most likely to break when a provider
/// changes how it wraps its output.
@visibleForTesting
List<QuestionModel> parseGeneratedQuestions(String raw) =>
    AiQuestionGenerator._parseQuestions(raw);
