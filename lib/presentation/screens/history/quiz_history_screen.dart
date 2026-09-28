import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/quiz_result_history.dart';
import '../../../data/providers/user_provider.dart';
import '../../widgets/glass_card.dart';
import '../../../l10n/app_strings.dart';

/// Shows the player's complete quiz result history with filtering options.
class QuizHistoryScreen extends StatefulWidget {
  const QuizHistoryScreen({super.key});

  @override
  State<QuizHistoryScreen> createState() => _QuizHistoryScreenState();
}

class _QuizHistoryScreenState extends State<QuizHistoryScreen> {
  List<QuizResultHistory> _allHistory = [];
  List<QuizResultHistory> _filteredHistory = [];
  bool _isLoading = true;
  String _filter = 'all'; // 'all', 'daily', 'chapter'

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final userProvider = context.read<UserProvider>();
    final history = await userProvider.loadQuizHistory(limit: 100);
    if (mounted) {
      setState(() {
        _allHistory = history;
        _applyFilter();
        _isLoading = false;
      });
    }
  }

  void _applyFilter() {
    if (_filter == 'all') {
      _filteredHistory = _allHistory;
    } else {
      _filteredHistory = _allHistory
          .where((h) => h.quizType == _filter)
          .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          S.historyTitle,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.neonCyan),
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatsSummary(),
          _buildFilterChips(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.neonCyan),
                  )
                : _filteredHistory.isEmpty
                ? _buildEmptyState()
                : _buildHistoryList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSummary() {
    final totalQuizzes = _allHistory.length;
    final totalScore = _allHistory.fold<int>(0, (sum, h) => sum + h.score);
    final avgAccuracy = _allHistory.isEmpty
        ? 0.0
        : _allHistory.fold<double>(0, (sum, h) => sum + h.accuracy) /
              _allHistory.length;
    final totalCoins = _allHistory.fold<int>(
      0,
      (sum, h) => sum + h.coinsEarned,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: GlassCard(
        borderRadius: 20,
        borderColor: AppColors.neonCyan.withValues(alpha: 0.3),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                icon: Icons.quiz_rounded,
                value: '$totalQuizzes',
                label: S.historyQuizzes,
                color: AppColors.neonCyan,
              ),
              _buildStatItem(
                icon: Icons.stars_rounded,
                value: _formatNumber(totalScore),
                label: S.historyTotalScore,
                color: AppColors.neonGold,
              ),
              _buildStatItem(
                icon: Icons.track_changes_rounded,
                value: '${avgAccuracy.toStringAsFixed(0)}%',
                label: S.historyAvgAccuracy,
                color: AppColors.neonGreen,
              ),
              _buildStatItem(
                icon: Icons.monetization_on_rounded,
                value: _formatNumber(totalCoins),
                label: S.coins,
                color: AppColors.neonGold,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildFilterChip(S.all, 'all'),
          const SizedBox(width: 8),
          _buildFilterChip(S.historyDaily, 'daily'),
          const SizedBox(width: 8),
          _buildFilterChip(S.historyChapter, 'chapter'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _filter = value;
          _applyFilter();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.neonCyan.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppColors.neonCyan.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.neonCyan : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_rounded,
            size: 80,
            color: AppColors.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            S.historyNone,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            S.historyEmptyBody,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    return RefreshIndicator(
      color: AppColors.neonCyan,
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _filteredHistory.length,
        itemBuilder: (context, index) {
          final history = _filteredHistory[index];
          return _buildHistoryCard(history, index);
        },
      ),
    );
  }

  Widget _buildHistoryCard(QuizResultHistory history, int index) {
    final gradeColor = _gradeColor(history.grade);
    final isDaily = history.quizType == 'daily';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        borderRadius: 18,
        borderColor: gradeColor.withValues(alpha: 0.3),
        onTap: () => _showDetailSheet(history),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Grade badge
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      gradeColor.withValues(alpha: 0.3),
                      gradeColor.withValues(alpha: 0.1),
                    ],
                  ),
                  border: Border.all(color: gradeColor.withValues(alpha: 0.5)),
                ),
                child: Center(
                  child: Text(
                    history.grade,
                    style: TextStyle(
                      color: gradeColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDaily
                                ? AppColors.neonGold.withValues(alpha: 0.15)
                                : AppColors.neonPurple.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isDaily ? S.historyDailyCaps : S.historyChapterCaps,
                            style: TextStyle(
                              color: isDaily
                                  ? AppColors.neonGold
                                  : AppColors.neonPurple,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            history.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (!isDaily && history.categoryTitle != null)
                      Text(
                        history.categoryTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildMiniStat(
                          Icons.check_circle,
                          '${history.correctAnswers}',
                          AppColors.neonGreen,
                        ),
                        const SizedBox(width: 10),
                        _buildMiniStat(
                          Icons.cancel,
                          '${history.wrongAnswers}',
                          AppColors.neonRed,
                        ),
                        const SizedBox(width: 10),
                        _buildMiniStat(
                          Icons.timer,
                          history.timeFormatted,
                          AppColors.neonCyan,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Score
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${history.score}',
                    style: TextStyle(
                      color: gradeColor,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    history.accuracyLabel,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _formatDate(history.playedAt),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  void _showDetailSheet(QuizResultHistory history) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildDetailSheet(history),
    );
  }

  Widget _buildDetailSheet(QuizResultHistory history) {
    final gradeColor = _gradeColor(history.grade);

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2646),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: gradeColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            // Grade
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    gradeColor.withValues(alpha: 0.3),
                    gradeColor.withValues(alpha: 0.1),
                  ],
                ),
                border: Border.all(
                  color: gradeColor.withValues(alpha: 0.5),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: gradeColor.withValues(alpha: 0.3),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  history.grade,
                  style: TextStyle(
                    color: gradeColor,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              history.displayTitle,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (history.categoryTitle != null) ...[
              const SizedBox(height: 4),
              Text(
                history.fullSubjectPath,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
            const SizedBox(height: 24),
            // Stats grid
            Row(
              children: [
                Expanded(
                  child: _buildDetailStat(
                    S.score,
                    '${history.score}',
                    AppColors.neonGold,
                    Icons.stars_rounded,
                  ),
                ),
                Expanded(
                  child: _buildDetailStat(
                    S.accuracy,
                    history.accuracyLabel,
                    AppColors.neonCyan,
                    Icons.track_changes_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildDetailStat(
                    S.correct,
                    '${history.correctAnswers}',
                    AppColors.neonGreen,
                    Icons.check_circle_rounded,
                  ),
                ),
                Expanded(
                  child: _buildDetailStat(
                    S.wrong,
                    '${history.wrongAnswers}',
                    AppColors.neonRed,
                    Icons.cancel_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildDetailStat(
                    S.time,
                    history.timeFormatted,
                    AppColors.neonPurple,
                    Icons.timer_rounded,
                  ),
                ),
                Expanded(
                  child: _buildDetailStat(
                    S.coins,
                    '+${history.coinsEarned}',
                    AppColors.neonGold,
                    Icons.monetization_on_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              S.historyPlayedOn(date: _formatFullDate(history.playedAt)),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                child: Text(
                  S.close,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailStat(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Color _gradeColor(String grade) {
    switch (grade) {
      case 'S':
        return AppColors.neonGold;
      case 'A':
        return AppColors.neonGreen;
      case 'B':
        return AppColors.neonCyan;
      case 'C':
        return AppColors.neonPurple;
      case 'D':
        return AppColors.neonPink;
      default:
        return AppColors.neonRed;
    }
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) return S.today;
    if (diff.inDays == 1) return S.yesterday;
    if (diff.inDays < 7) return S.daysAgo(n: diff.inDays);
    return '${date.day}/${date.month}';
  }

  String _formatFullDate(DateTime date) {
    final months = S.monthsShort;
    return '${date.day} ${months[date.month - 1]} ${date.year}, ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
