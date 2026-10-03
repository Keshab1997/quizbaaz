import 'dart:convert';

import 'admin_catalog_prompt_builder.dart';
import '../models/localized_text.dart';
import 'ai_question_generator.dart';

/// One AI-authored chapter waiting for admin approval.
class AiCatalogChapterDraft {
  final LocalizedText title;
  final LocalizedText description;

  const AiCatalogChapterDraft({required this.title, required this.description});
}

/// A reviewable subject/chapter draft. No ids are trusted from the model.
class AiCatalogDraft {
  final LocalizedText? subjectName;
  final String icon;
  final String colorHex;
  final List<AiCatalogChapterDraft> chapters;
  final List<String> warnings;

  const AiCatalogDraft({
    required this.subjectName,
    required this.icon,
    required this.colorHex,
    required this.chapters,
    this.warnings = const [],
  });
}

class AiCatalogGenerationException implements Exception {
  final String message;
  const AiCatalogGenerationException(this.message);

  @override
  String toString() => message;
}

/// Generates trilingual subject/chapter metadata through the existing admin
/// API-key pool. It deliberately stops before Firestore: the admin reviews the
/// draft and the UI assigns ids before calling [ChapterCatalogService].
class AiCatalogGenerator {
  AiCatalogGenerator({AiQuestionGenerator? transport})
    : _transport = transport ?? AiQuestionGenerator();

  final AiQuestionGenerator _transport;

  Future<AiCatalogDraft> generateNewSubject({
    required String request,
    required int chapterCount,
    required String actorUid,
  }) async {
    final raw = await _transport.requestJson(
      AdminCatalogPromptBuilder.buildNewSubjectPrompt(
        request: request,
        chapterCount: chapterCount,
      ),
      actorUid: actorUid,
      feature: 'catalog_generation',
    );
    if (raw == null) {
      throw const AiCatalogGenerationException(
        'AI could not respond. Check Admin → API Keys and try again.',
      );
    }
    return parseAiCatalogDraft(
      raw,
      requireSubject: true,
      expectedCount: chapterCount,
    );
  }

  Future<AiCatalogDraft> generateChapters({
    required String subjectName,
    required String request,
    required int chapterCount,
    required List<String> existingChapterTitles,
    required String actorUid,
  }) async {
    final raw = await _transport.requestJson(
      AdminCatalogPromptBuilder.buildChaptersPrompt(
        subjectName: subjectName,
        request: request,
        chapterCount: chapterCount,
        existingChapterTitles: existingChapterTitles,
      ),
      actorUid: actorUid,
      feature: 'catalog_generation',
    );
    if (raw == null) {
      throw const AiCatalogGenerationException(
        'AI could not respond. Check Admin → API Keys and try again.',
      );
    }
    return parseAiCatalogDraft(
      raw,
      requireSubject: false,
      expectedCount: chapterCount,
      existingChapterTitles: existingChapterTitles,
    );
  }
}

/// Parses the object shape requested by [AdminCatalogPromptBuilder].
///
/// This is public so the model's most failure-prone boundary can be covered by
/// fast unit tests without making a network call.
AiCatalogDraft parseAiCatalogDraft(
  String raw, {
  required bool requireSubject,
  required int expectedCount,
  List<String> existingChapterTitles = const [],
}) {
  final decoded = _decodeObject(raw);
  if (decoded == null) {
    throw const AiCatalogGenerationException(
      'AI returned invalid JSON. Nothing was saved; please try again.',
    );
  }

  final warnings = <String>[];
  LocalizedText? subjectName;
  var icon = 'assets/icons/coin_and_gem_3d.png';
  var colorHex = '#53E6FF';

  if (requireSubject) {
    final subject = decoded['subject'];
    if (subject is! Map) {
      throw const AiCatalogGenerationException(
        'AI did not return a subject draft. Nothing was saved; please try again.',
      );
    }
    final subjectMap = Map<String, dynamic>.from(subject);
    subjectName = LocalizedText.fromJson(
      subjectMap['name'] ?? subjectMap['subject_name'],
    );
    if (!_hasAllLanguages(subjectName)) {
      throw const AiCatalogGenerationException(
        'AI returned an incomplete subject name. Please generate again.',
      );
    }
    final proposedIcon = subjectMap['icon']?.toString() ?? '';
    if (proposedIcon.startsWith('assets/')) icon = proposedIcon;
    final proposedColor = subjectMap['color_hex']?.toString() ?? '';
    if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(proposedColor)) {
      colorHex = proposedColor;
    }
  }

  final rawChapters = decoded['chapters'] ?? decoded['items'];
  if (rawChapters is! List) {
    throw const AiCatalogGenerationException(
      'AI did not return a chapter list. Nothing was saved; please try again.',
    );
  }

  final existingKeys = {
    for (final title in existingChapterTitles) _normalise(title),
  };
  final seenKeys = <String>{};
  final chapters = <AiCatalogChapterDraft>[];

  for (final rawChapter in rawChapters) {
    if (rawChapter is! Map) {
      warnings.add('One AI chapter was not an object and was skipped.');
      continue;
    }
    final chapter = Map<String, dynamic>.from(rawChapter);
    final title = LocalizedText.fromJson(chapter['title'] ?? chapter['name']);
    if (!_hasAllLanguages(title)) {
      warnings.add('A chapter with missing EN, BN or HI text was skipped.');
      continue;
    }

    final key = _normalise(title.resolve('en'));
    if (key.isEmpty || existingKeys.contains(key) || !seenKeys.add(key)) {
      warnings.add('A duplicate chapter was skipped: ${title.resolve('en')}.');
      continue;
    }

    chapters.add(
      AiCatalogChapterDraft(
        title: title,
        description: LocalizedText.fromJson(chapter['description']),
      ),
    );
  }

  if (chapters.isEmpty) {
    throw const AiCatalogGenerationException(
      'AI did not produce any new valid chapters. Please try again.',
    );
  }
  if (chapters.length < expectedCount) {
    warnings.add(
      'AI produced ${chapters.length} of $expectedCount valid chapters.',
    );
  }

  return AiCatalogDraft(
    subjectName: subjectName,
    icon: icon,
    colorHex: colorHex,
    chapters: chapters.take(expectedCount).toList(),
    warnings: warnings,
  );
}

bool _hasAllLanguages(LocalizedText text) => ['en', 'bn', 'hi'].every(text.has);

String _normalise(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

Map<String, dynamic>? _decodeObject(String raw) {
  var text = raw.trim();
  if (text.startsWith('```')) {
    final newline = text.indexOf('\n');
    if (newline >= 0) text = text.substring(newline + 1);
    final closing = text.lastIndexOf('```');
    if (closing >= 0) text = text.substring(0, closing);
  }
  try {
    final decoded = jsonDecode(text.trim());
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }
}
