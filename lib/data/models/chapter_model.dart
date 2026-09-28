import '../../l10n/app_strings.dart';
import 'localized_text.dart';

/// A subject in the chapter bank (Mathematics, Life Science, …).
class CategoryModel {
  final String categoryId;
  final LocalizedText nameText;
  final String categoryIcon;
  final String colorHex;
  final int totalChapters;
  final List<ChapterModel> chapters;

  const CategoryModel({
    required this.categoryId,
    required this.nameText,
    required this.categoryIcon,
    required this.colorHex,
    required this.totalChapters,
    required this.chapters,
  });

  /// Subject name in the current UI language.
  String get categoryName => nameText.current;

  CategoryModel copyWith({List<ChapterModel>? chapters}) {
    final resolved = chapters ?? this.chapters;
    return CategoryModel(
      categoryId: categoryId,
      nameText: nameText,
      categoryIcon: categoryIcon,
      colorHex: colorHex,
      totalChapters: resolved.length,
      chapters: resolved,
    );
  }

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      categoryId: json['category_id'] ?? '',
      nameText: LocalizedText.fromJson(json['category_name']),
      categoryIcon: json['category_icon'] ?? '',
      colorHex: json['color_hex'] ?? '#3B82F6',
      totalChapters: (json['total_chapters'] as num?)?.toInt() ?? 0,
      chapters: (json['chapters'] as List? ?? const [])
          .whereType<Map>()
          .map((c) => ChapterModel.fromJson(Map<String, dynamic>.from(c)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'category_id': categoryId,
        'category_name': nameText.toJson(),
        'category_icon': categoryIcon,
        'color_hex': colorHex,
        'total_chapters': totalChapters,
        'chapters': chapters.map((c) => c.toJson()).toList(),
      };
}

/// One chapter inside a subject, pointing at its question bank file.
class ChapterModel {
  final String chapterId;
  final int chapterNumber;
  final LocalizedText titleText;
  final LocalizedText descriptionText;
  final int totalQuestions;
  final String jsonFile;
  final bool isUnlocked;

  /// Whether this chapter is visible to students. This is deliberately
  /// independent of [isUnlocked]: a visible chapter can still require prior
  /// progress, while a disabled chapter is omitted from student surfaces.
  final bool isEnabled;
  final int stars;
  final int bestScore;

  const ChapterModel({
    required this.chapterId,
    required this.chapterNumber,
    required this.titleText,
    required this.descriptionText,
    required this.totalQuestions,
    required this.jsonFile,
    required this.isUnlocked,
    this.isEnabled = true,
    required this.stars,
    required this.bestScore,
  });

  /// Chapter title in the current UI language.
  String get title => titleText.current;

  /// Chapter description in the current UI language.
  String get description => descriptionText.current;

  /// The English title, kept alongside the translated one on the chapter card
  /// because board students revise in English terminology too.
  String get titleEnglish => titleText.resolve('en');

  /// The secondary line to show under [title], or null when it would just
  /// repeat it (English UI, or no English variant authored).
  String? get titleSecondary {
    if (S.code == 'en') return null;
    final english = titleEnglish;
    return english.isEmpty || english == title ? null : english;
  }

  ChapterModel copyWith({int? totalQuestions, bool? isEnabled}) {
    return ChapterModel(
      chapterId: chapterId,
      chapterNumber: chapterNumber,
      titleText: titleText,
      descriptionText: descriptionText,
      totalQuestions: totalQuestions ?? this.totalQuestions,
      jsonFile: jsonFile,
      isUnlocked: isUnlocked,
      isEnabled: isEnabled ?? this.isEnabled,
      stars: stars,
      bestScore: bestScore,
    );
  }

  factory ChapterModel.fromJson(Map<String, dynamic> json) {
    return ChapterModel(
      chapterId: json['chapter_id'] ?? '',
      chapterNumber: (json['chapter_number'] as num?)?.toInt() ?? 1,
      titleText: LocalizedText.fromJson(json['title']),
      descriptionText: LocalizedText.fromJson(json['description']),
      totalQuestions: (json['total_questions'] as num?)?.toInt() ?? 0,
      jsonFile: json['json_file'] ?? '',
      isUnlocked: json['is_unlocked'] ?? true,
      // Existing bundled files and older Firestore documents did not have
      // this field, so they remain visible after the feature ships.
      isEnabled: json['is_enabled'] is bool ? json['is_enabled'] as bool : true,
      stars: (json['stars'] as num?)?.toInt() ?? 0,
      bestScore: (json['best_score'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'chapter_id': chapterId,
        'chapter_number': chapterNumber,
        'title': titleText.toJson(),
        'description': descriptionText.toJson(),
        'total_questions': totalQuestions,
        'json_file': jsonFile,
        'is_unlocked': isUnlocked,
        'is_enabled': isEnabled,
        'stars': stars,
        'best_score': bestScore,
      };
}
