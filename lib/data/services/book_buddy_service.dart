import 'package:admin_api_key_manager/admin_api_key_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:smart_ocr_ai_bridge/smart_ocr_ai_bridge.dart';

import '../models/localized_text.dart';
import '../models/question_model.dart';

/// Result of scanning and explaining a textbook page via [BookBuddyService].
class BookPageAnalysis {
  final String title;
  final String explanation;
  final String extractedText;
  final int ocrScore;
  final bool usedVisionFallback;
  final String tokenSavingsLabel;

  const BookPageAnalysis({
    required this.title,
    required this.explanation,
    required this.extractedText,
    required this.ocrScore,
    required this.usedVisionFallback,
    required this.tokenSavingsLabel,
  });
}

/// Student-facing AI tutor & practice MCQ generator powered by
/// `SmartOcrAiBridge` + `ApiKeyManager`.
///
/// Design guarantees:
/// * **~90% token savings on readable pages:** `OcrRoutingMode.hybridAuto`
///   extracts text on-device via ML Kit and sends compacted text-only when
///   `ocrScore >= 20`, falling back to multimodal vision bytes automatically
///   for handwriting, diagrams, or non-Latin scripts without ML Kit coverage.
/// * **0-token follow-up reuse:** Once a page has compacted OCR text, follow-up
///   Q&A and MCQ generation reuse `analyzeExtractedText` / `analyzeExtractedTextAsJson`
///   instead of re-uploading image bytes.
class BookBuddyService {
  BookBuddyService({SmartOcrAiBridge? bridge, ApiKeyManager? keyManager})
    : _bridge = bridge ?? SmartOcrAiBridge.instance,
      _keyManager = keyManager;

  final SmartOcrAiBridge _bridge;
  final ApiKeyManager? _keyManager;

  static String _languageName(String languageCode) => switch (languageCode) {
    'bn' => 'Bengali (বাংলা)',
    'hi' => 'Hindi (हिन्दी)',
    _ => 'English',
  };

  Future<void> _ensureKeyPoolReady() async {
    final manager = _keyManager;
    if (manager == null) return;
    try {
      if (manager.peekFirstKey() == null) {
        await manager.ensureReady().timeout(const Duration(seconds: 4));
      }
      _bridge.bindApiKeyManager(manager);
    } catch (e) {
      debugPrint('BookBuddyService: key pool warmup skipped – $e');
    }
  }

  /// Scans [imageBytes] with `SmartOcrAiBridge` (`hybridAuto`) and returns a
  /// clear student-friendly topic title + explanation in [languageCode].
  Future<BookPageAnalysis> scanAndExplainPage({
    required Uint8List imageBytes,
    required String languageCode,
    String? customQuestion,
    String userId = 'student',
  }) async {
    await _ensureKeyPoolReady();
    final lang = _languageName(languageCode);
    final taskLine =
        (customQuestion != null && customQuestion.trim().isNotEmpty)
            ? 'Student question: ${customQuestion.trim()}'
            : 'Explain the key concepts on this textbook page clearly in simple '
                'step-by-step points with examples suitable for school students.';

    final result = await _bridge.analyzeImage(
      imageBytes: imageBytes,
      routingMode: OcrRoutingMode.hybridAuto,
      systemPrompt:
          'You are QuizBaaz AI Book Buddy, a friendly and accurate school tutor. '
          'Always reply in $lang. Start your first line with "TITLE: <short topic title>" '
          'followed by a blank line, then give a clear, structured explanation.',
      userPrompt: taskLine,
      featureTag: 'book_buddy_scan',
      userId: userId,
    );

    final parsed = _splitTitleAndBody(result.aiResponse);
    return BookPageAnalysis(
      title: parsed.$1,
      explanation: parsed.$2,
      extractedText:
          result.compactedOcrText.isNotEmpty
              ? result.compactedOcrText
              : result.extractedText,
      ocrScore: result.ocrScore,
      usedVisionFallback: result.usedVisionFallback,
      tokenSavingsLabel: result.tokenSavings.summaryLabel,
    );
  }

  /// Answers a follow-up student question about the current page.
  ///
  /// Uses compacted [extractedText] when available (saving ~90% tokens), or
  /// falls back to [fallbackImageBytes] when the page was a pure diagram/photo.
  Future<String> askFollowUp({
    required String question,
    required String extractedText,
    Uint8List? fallbackImageBytes,
    required String languageCode,
    String userId = 'student',
  }) async {
    await _ensureKeyPoolReady();
    final lang = _languageName(languageCode);
    final systemPrompt =
        'You are QuizBaaz AI Book Buddy, a helpful school tutor. '
        'Answer the student accurately based on their textbook page in $lang. '
        'Keep the tone encouraging, clear, and easy to understand.';

    if (extractedText.trim().isNotEmpty) {
      final result = await _bridge.analyzeExtractedText(
        extractedText: extractedText,
        systemPrompt: systemPrompt,
        userPrompt: question.trim(),
        featureTag: 'book_buddy_qa',
        userId: userId,
      );
      return result.aiResponse.trim();
    }

    if (fallbackImageBytes != null && fallbackImageBytes.isNotEmpty) {
      final result = await _bridge.analyzeImage(
        imageBytes: fallbackImageBytes,
        routingMode: OcrRoutingMode.visionOnly,
        systemPrompt: systemPrompt,
        userPrompt: question.trim(),
        featureTag: 'book_buddy_qa_vision',
        userId: userId,
      );
      return result.aiResponse.trim();
    }

    throw const SmartOcrAiBridgeException(
      'No textbook page text or image available to answer this question.',
    );
  }

  /// Generates [count] multiple-choice practice questions (`QuestionModel`)
  /// from the scanned page in [languageCode].
  Future<List<QuestionModel>> generatePracticeMcqs({
    required String extractedText,
    Uint8List? fallbackImageBytes,
    required String languageCode,
    int count = 5,
    String userId = 'student',
  }) async {
    await _ensureKeyPoolReady();
    final targetCount = count.clamp(3, 10);
    final lang = _languageName(languageCode);

    final schemaExample = <String, dynamic>{
      'questions': [
        {
          'question': 'Clear exam-style question in $lang?',
          'options': ['Option A', 'Option B', 'Option C', 'Option D'],
          'correct_index': 0,
          'explanation': 'One-sentence reason why this option is correct.',
        },
      ],
    };

    final prompt =
        'Create exactly $targetCount multiple-choice questions (4 options each) '
        'strictly from this textbook content in $lang. '
        'Make all 4 options plausible, set correct_index (0 to 3) accurately, '
        'and include a short explanation in $lang.';

    Map<String, dynamic> jsonMap;
    if (extractedText.trim().isNotEmpty) {
      jsonMap = await _bridge.analyzeExtractedTextAsJson(
        extractedText: extractedText,
        userPrompt: prompt,
        schemaHint: schemaExample,
        useCache: true,
        featureTag: 'book_buddy_mcq',
        userId: userId,
      );
    } else if (fallbackImageBytes != null && fallbackImageBytes.isNotEmpty) {
      jsonMap = await _bridge.analyzeImageAsJson(
        imageBytes: fallbackImageBytes,
        routingMode: OcrRoutingMode.visionOnly,
        userPrompt: prompt,
        schemaHint: schemaExample,
        useCache: false,
        featureTag: 'book_buddy_mcq_vision',
        userId: userId,
      );
    } else {
      throw const SmartOcrAiBridgeException(
        'Scan a textbook page first before generating MCQs.',
      );
    }

    return parseGeneratedMcqs(
      jsonMap,
      languageCode: languageCode,
      idPrefix: 'bb_${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  /// Parses raw decoded JSON from the LLM into validated [QuestionModel] items.
  @visibleForTesting
  static List<QuestionModel> parseGeneratedMcqs(
    Map<String, dynamic> jsonMap, {
    required String languageCode,
    String idPrefix = 'bb',
  }) {
    final rawList =
        (jsonMap['questions'] ?? jsonMap['items'] ?? jsonMap['mcqs'])
            as List<dynamic>? ??
        const [];

    final questions = <QuestionModel>[];
    for (var i = 0; i < rawList.length; i++) {
      final item = rawList[i];
      if (item is! Map) continue;
      final map = item.map((k, v) => MapEntry(k.toString(), v));

      final stem = _extractLocalized(map['question'], languageCode);
      if (stem.resolve(languageCode).trim().isEmpty) continue;

      final rawOptions = map['options'] as List<dynamic>? ?? const [];
      final options =
          rawOptions
              .map((opt) => _extractLocalized(opt, languageCode))
              .where((opt) => opt.resolve(languageCode).trim().isNotEmpty)
              .take(4)
              .toList();
      if (options.length < 2) continue;

      final rawCorrect = (map['correct_index'] as num?)?.toInt() ?? 0;
      final safeCorrect = rawCorrect.clamp(0, options.length - 1);
      final explanation = _extractLocalized(map['explanation'], languageCode);

      questions.add(
        QuestionModel(
          id: '${idPrefix}_${i + 1}',
          questionText: stem,
          optionTexts: options,
          correctIndex: safeCorrect,
          explanationText: explanation,
          points: 10,
          timeLimitSec: 30,
        ),
      );
    }
    return questions;
  }

  static LocalizedText _extractLocalized(Object? raw, String lang) {
    if (raw is Map) {
      final parsed = LocalizedText.fromJson(raw);
      if (parsed.isNotEmpty) return parsed;
    }
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return const LocalizedText.empty();
    return LocalizedText({lang: text, 'en': text});
  }

  static (String, String) _splitTitleAndBody(String rawResponse) {
    final trimmed = rawResponse.trim();
    if (trimmed.isEmpty) return ('', '');
    final lines = trimmed.split('\n');
    final first = lines.first.trim();
    final prefixMatch = RegExp(
      r'^(?:\*\*|#+\s*)?TITLE\s*[:\-–]\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(first);

    if (prefixMatch != null) {
      final cleanTitle =
          (prefixMatch.group(1) ?? '')
              .replaceAll('*', '')
              .replaceAll('#', '')
              .trim();
      final body = lines.skip(1).join('\n').trim();
      return (cleanTitle, body.isNotEmpty ? body : trimmed);
    }

    final fallbackTitle =
        first
            .replaceAll(RegExp(r'^[#*>\-\d.\s]+'), '')
            .replaceAll('*', '')
            .trim();
    final clipped =
        fallbackTitle.length > 48
            ? '${fallbackTitle.substring(0, 48).trim()}…'
            : fallbackTitle;
    return (clipped, trimmed);
  }
}
