import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/chapter_model.dart';
import '../../../data/repositories/quiz_repository.dart';
import '../../../data/services/haptic_service.dart';
import '../../../data/services/sound_service.dart';
import '../../widgets/glass_card.dart';
import 'chapter_sets_screen.dart';
import '../../../l10n/app_strings.dart';

class ChapterListScreen extends StatefulWidget {
  const ChapterListScreen({super.key});

  @override
  State<ChapterListScreen> createState() => _ChapterListScreenState();
}

class _ChapterListScreenState extends State<ChapterListScreen> {
  final QuizRepository _repository = QuizRepository();
  List<CategoryModel> _categories = [];
  int _selectedCategoryIndex = 0; // 0 = All Subjects
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChapters();
  }

  Future<void> _loadChapters() async {
    final list = await _repository.getCategoriesAndChapters();
    setState(() {
      _categories = list;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayedCategories =
        _selectedCategoryIndex == 0
            ? _categories
            : [_categories[_selectedCategoryIndex - 1]];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          S.chapterBankTitle,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(color: AppColors.neonCyan),
              )
              : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Subject Filter Pills
                  _buildSubjectFilterPills(),
                  const SizedBox(height: 10),

                  // 2. Chapters List
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      physics: const BouncingScrollPhysics(),
                      itemCount: displayedCategories.length,
                      itemBuilder: (context, catIndex) {
                        final category = displayedCategories[catIndex];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 8.0,
                                bottom: 8.0,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: _parseColor(category.colorHex),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      category.categoryName,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        color: _parseColor(category.colorHex),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    S.chapterCount(n: category.chapters.length),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ...category.chapters.map(
                              (ch) => _buildChapterCard(
                                context,
                                ch,
                                category.colorHex,
                                category.categoryName,
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
    );
  }

  Widget _buildSubjectFilterPills() {
    final filterOptions = [
      'All Subjects',
      ..._categories.map((c) => c.categoryName.split('(').first.trim()),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      physics: const BouncingScrollPhysics(),
      child: Row(
        children:
            filterOptions.asMap().entries.map((entry) {
              final idx = entry.key;
              final label = entry.value;
              final isSelected = _selectedCategoryIndex == idx;

              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: GestureDetector(
                  onTap: () {
                    SoundService.instance.play('ui_click');
                    Haptics.tap();
                    setState(() {
                      _selectedCategoryIndex = idx;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isSelected
                              ? AppColors.neonPurple
                              : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color:
                            isSelected
                                ? AppColors.neonPurple
                                : Colors.white.withValues(alpha: 0.12),
                      ),
                      boxShadow:
                          isSelected
                              ? [
                                BoxShadow(
                                  color: AppColors.neonPurple.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                              : null,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w900 : FontWeight.w600,
                        color:
                            isSelected ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildChapterCard(
    BuildContext context,
    ChapterModel chapter,
    String colorHex,
    String categoryName,
  ) {
    final isLocked = !chapter.isUnlocked;
    final catColor = _parseColor(colorHex);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: GlassCard(
        borderRadius: 20,
        borderColor:
            isLocked ? Colors.white10 : catColor.withValues(alpha: 0.35),
        backgroundColor:
            isLocked ? const Color(0x221E293B) : const Color(0x331E1B4B),
        onTap:
            isLocked
                ? () {
                  SoundService.instance.play('ui_deny');
                  Haptics.error();
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(S.chapterLockedMsg)));
                }
                // Opens the set list rather than launching the whole bank at
                // once: a chapter keeps growing, and where the student left off is
                // the first thing they need to see.
                : () {
                  SoundService.instance.play('ui_click');
                  Haptics.tap();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) => ChapterSetsScreen(
                            chapter: chapter,
                            categoryTitle: categoryName,
                            accent: catColor,
                          ),
                    ),
                  );
                },
        child: Row(
          children: [
            // Chapter Number Badge or Lock
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color:
                    isLocked
                        ? Colors.white.withValues(alpha: 0.05)
                        : catColor.withValues(alpha: 0.2),
                border: Border.all(
                  color:
                      isLocked
                          ? Colors.white12
                          : catColor.withValues(alpha: 0.5),
                ),
              ),
              child: Center(
                child:
                    isLocked
                        ? const Icon(
                          Icons.lock,
                          color: AppColors.textMuted,
                          size: 22,
                        )
                        : Text(
                          S.chapterShort(n: chapter.chapterNumber),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: catColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
              ),
            ),
            const SizedBox(width: 14),

            // Chapter Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chapter.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color:
                          isLocked
                              ? AppColors.textMuted
                              : AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (chapter.titleSecondary != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      chapter.titleSecondary!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color:
                            isLocked
                                ? AppColors.textMuted
                                : AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      // Question Count
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          S.chapterQuestionCount(n: chapter.totalQuestions),
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Stars
                      if (!isLocked)
                        Text(
                          '⭐' * chapter.stars + '☆' * (3 - chapter.stars),
                          style: const TextStyle(fontSize: 10),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Action Arrow
            if (!isLocked)
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: catColor.withValues(alpha: 0.15),
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: catColor,
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      final buffer = StringBuffer();
      if (hex.length == 6 || hex.length == 7) buffer.write('ff');
      buffer.write(hex.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (e) {
      return AppColors.neonPurple;
    }
  }
}
