import 'question_model.dart';

/// A single student question + AI tutor explanation inside a [BookStudySession].
class BookChatTurn {
  final String question;
  final String answer;
  final int createdAtMs;

  const BookChatTurn({
    required this.question,
    required this.answer,
    required this.createdAtMs,
  });

  factory BookChatTurn.fromJson(Map<String, dynamic> json) {
    return BookChatTurn(
      question: (json['question'] ?? '').toString(),
      answer: (json['answer'] ?? '').toString(),
      createdAtMs: (json['created_at_ms'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'question': question,
    'answer': answer,
    'created_at_ms': createdAtMs,
  };
}

/// One scanned textbook page / study session saved locally in Hive (`qb_stats`).
///
/// Stores the compacted OCR text, AI summary/Q&A turns, and any generated
/// practice MCQs so students can re-read explanations and replay practice
/// quizzes completely offline (0 API tokens on revisit).
class BookStudySession {
  final String id;
  final String title;
  final String extractedText;
  final int ocrScore;
  final bool usedVisionFallback;
  final String tokenSavingsLabel;
  final List<BookChatTurn> turns;
  final List<QuestionModel> generatedMcqs;
  final int createdAtMs;
  final int updatedAtMs;

  const BookStudySession({
    required this.id,
    required this.title,
    required this.extractedText,
    this.ocrScore = 0,
    this.usedVisionFallback = false,
    this.tokenSavingsLabel = '',
    this.turns = const [],
    this.generatedMcqs = const [],
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  bool get hasExtractedText => extractedText.trim().isNotEmpty;
  bool get hasMcqs => generatedMcqs.isNotEmpty;

  BookStudySession copyWith({
    String? title,
    String? extractedText,
    int? ocrScore,
    bool? usedVisionFallback,
    String? tokenSavingsLabel,
    List<BookChatTurn>? turns,
    List<QuestionModel>? generatedMcqs,
    int? updatedAtMs,
  }) {
    return BookStudySession(
      id: id,
      title: title ?? this.title,
      extractedText: extractedText ?? this.extractedText,
      ocrScore: ocrScore ?? this.ocrScore,
      usedVisionFallback: usedVisionFallback ?? this.usedVisionFallback,
      tokenSavingsLabel: tokenSavingsLabel ?? this.tokenSavingsLabel,
      turns: turns ?? this.turns,
      generatedMcqs: generatedMcqs ?? this.generatedMcqs,
      createdAtMs: createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  factory BookStudySession.fromJson(Map<String, dynamic> json) {
    final rawTurns = json['turns'] as List<dynamic>? ?? const [];
    final rawMcqs = json['generated_mcqs'] as List<dynamic>? ?? const [];
    return BookStudySession(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      extractedText: (json['extracted_text'] ?? '').toString(),
      ocrScore: (json['ocr_score'] as num?)?.toInt() ?? 0,
      usedVisionFallback: json['used_vision_fallback'] == true,
      tokenSavingsLabel: (json['token_savings_label'] ?? '').toString(),
      turns:
          rawTurns
              .whereType<Map>()
              .map(
                (item) => BookChatTurn.fromJson(
                  item.map((k, v) => MapEntry(k.toString(), v)),
                ),
              )
              .toList(),
      generatedMcqs:
          rawMcqs
              .whereType<Map>()
              .map(
                (item) => QuestionModel.fromJson(
                  item.map((k, v) => MapEntry(k.toString(), v)),
                ),
              )
              .toList(),
      createdAtMs: (json['created_at_ms'] as num?)?.toInt() ?? 0,
      updatedAtMs: (json['updated_at_ms'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'extracted_text': extractedText,
    'ocr_score': ocrScore,
    'used_vision_fallback': usedVisionFallback,
    'token_savings_label': tokenSavingsLabel,
    'turns': turns.map((t) => t.toJson()).toList(),
    'generated_mcqs': generatedMcqs.map((q) => q.toJson()).toList(),
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };
}
