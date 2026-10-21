import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/chapter_model.dart';
import '../../../data/providers/quiz_provider.dart';
import '../../../data/repositories/quiz_repository.dart';
import '../../../data/services/haptic_service.dart';
import '../../../data/services/sound_service.dart';
import '../../../l10n/app_strings.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/neon_button.dart';
import '../daily_quiz/daily_quiz_screen.dart';

/// Free Practice hub: pick a subject (or all of them) and play an unlimited
/// number of rounds of random questions.
///
/// Every round is a fresh draw from the question bank, and every round is
/// practice — nothing is counted, so the section can never be used to farm
/// coins, gems or leaderboard credit. That freedom is the feature: a student
/// revises as much as they want without a lock, a ticket or a cost.
class PracticeQuizScreen extends StatefulWidget {
  const PracticeQuizScreen({super.key});

  @override
  State<PracticeQuizScreen> createState() => _PracticeQuizScreenState();
}

class _PracticeQuizScreenState extends State<PracticeQuizScreen> {
  final QuizRepository _repository = QuizRepository();
  List<CategoryModel> _categories = [];
  int _selectedCategoryIndex = 0; // 0 = all subjects
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    final list = await _repository.getCategoriesAndChapters();
    if (!mounted) return;
    setState(() {
      _categories = list;
      _isLoading = false;
    });
  }

  /// Null means "all subjects" — the pool is then the whole mixed bank.
  String? get _selectedCategoryId =>
      _selectedCategoryIndex == 0
          ? null
          : _categories[_selectedCategoryIndex - 1].categoryId;

  Future<void> _startPractice() async {
    SoundService.instance.play('ui_whoosh');
    Haptics.tap();
    final quiz = context.read<QuizProvider>();
    final navigator = Navigator.of(context);
    await quiz.startFreePractice(categoryId: _selectedCategoryId);
    if (!mounted) return;
    // The shared quiz player renders whatever the provider holds — the
    // chapter/daily screens are just other entry points to the same run.
    await navigator.push(
      MaterialPageRoute(builder: (_) => const DailyQuizScreen()),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          S.practiceTitle,
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
              : _categories.isEmpty
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: GlassCard(
                    borderRadius: 20,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.inbox_rounded,
                          size: 44,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          S.practiceEmpty,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              : ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                physics: const BouncingScrollPhysics(),
                children: [
                  // What this section is — and the one rule that keeps the
                  // economy safe: nothing here is counted.
                  GlassCard(
                    borderRadius: 20,
                    borderColor: AppColors.neonCyan.withValues(alpha: 0.35),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.neonCyan.withValues(alpha: 0.2),
                            border: Border.all(
                              color: AppColors.neonCyan.withValues(alpha: 0.5),
                            ),
                          ),
                          child: const Icon(
                            Icons.shuffle_rounded,
                            color: AppColors.neonCyan,
                            size: 23,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                S.practiceInfoBody,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                S.setsPracticeNote,
                                style: const TextStyle(
                                  color: AppColors.neonGold,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildSubjectFilterPills(),
                  const SizedBox(height: 14),
                  NeonButton(
                    text: S.practiceStart,
                    icon: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                    ),
                    gradient: AppColors.primaryGradient,
                    onPressed: _startPractice,
                  ),
                  const SizedBox(height: 20),
                ],
              ),
    );
  }

  /// Subject pills — the same interaction the chapter bank uses, so the two
  /// screens feel like one app. Labels come from the catalogue (localized),
  /// never from hardcoded strings.
  Widget _buildSubjectFilterPills() {
    final filterOptions = [
      S.allSubjects,
      ..._categories.map((c) => c.categoryName),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
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
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w500,
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
}
