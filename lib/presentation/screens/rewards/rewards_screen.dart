import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_assets.dart';
import '../../../data/models/quiz_result_history.dart';
import '../../../data/providers/user_provider.dart';
import '../../widgets/glass_card.dart';
import '../../../l10n/app_strings.dart';

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  List<QuizResultHistory> _dailyQuizHistory = [];
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _loadDailyHistory();
  }

  Future<void> _loadDailyHistory() async {
    final userProvider = context.read<UserProvider>();
    final history = await userProvider.loadQuizHistory();
    if (mounted) {
      setState(() {
        _dailyQuizHistory =
            history
                .where(
                  (h) =>
                      h.quizType == 'daily' ||
                      h.coinsEarned > 0 ||
                      h.gemsEarned > 0,
                )
                .toList();
        _loadingHistory = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          S.rewardsTitle,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          // Banner
          GlassCard(
            borderRadius: 20,
            borderColor: AppColors.neonGold.withValues(alpha: 0.4),
            backgroundColor: const Color(0x33281E48),
            child: Row(
              children: [
                Image.asset(
                  AppAssets.rewardGirl,
                  width: 84,
                  height: 84,
                  fit: BoxFit.contain,
                  errorBuilder:
                      (_, __, ___) =>
                          Image.asset(AppAssets.giftBox, width: 70, height: 70),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.rewardsWinDaily,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.neonGold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        S.rewardsWinDailyBody,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 🏆 Daily Quiz Winnings Section
          Row(
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: AppColors.neonGold,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '🏆 DAILY QUIZ WINNINGS',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textSecondary,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              if (!_loadingHistory)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.neonGold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_dailyQuizHistory.length} quizzes',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.neonGold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Coins, gems & shop items earned from daily quiz performances:',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),

          if (_loadingHistory)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: AppColors.neonGold),
                    SizedBox(height: 16),
                    Text(
                      'Loading your winnings...',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_dailyQuizHistory.isEmpty)
            GlassCard(
              borderRadius: 18,
              padding: const EdgeInsets.all(24),
              borderColor: AppColors.neonGold.withValues(alpha: 0.2),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.neonGold.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: AppColors.neonGold,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No winnings yet!',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Play today\'s Daily Live Quiz to win\ncoins, gems & shop prizes!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppColors.fireGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'START QUIZ',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else ...[
            // Summary Card
            GlassCard(
              borderRadius: 16,
              padding: const EdgeInsets.all(16),
              borderColor: AppColors.neonGold.withValues(alpha: 0.3),
              child: Row(
                children: [
                  Expanded(
                    child: _StatItem(
                      icon: Icons.emoji_events_rounded,
                      value: '${_dailyQuizHistory.length}',
                      label: 'Quizzes',
                      color: AppColors.neonGold,
                    ),
                  ),
                  Container(width: 1, height: 40, color: Colors.white12),
                  Expanded(
                    child: _StatItem(
                      icon: Icons.monetization_on_rounded,
                      value:
                          '${_dailyQuizHistory.fold(0, (sum, h) => sum + h.coinsEarned)}',
                      label: 'Coins',
                      color: AppColors.neonOrange,
                    ),
                  ),
                  Container(width: 1, height: 40, color: Colors.white12),
                  Expanded(
                    child: _StatItem(
                      icon: Icons.diamond_rounded,
                      value:
                          '${_dailyQuizHistory.fold(0, (sum, h) => sum + h.gemsEarned)}',
                      label: 'Gems',
                      color: AppColors.neonPurple,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // History List
            ..._dailyQuizHistory
                .take(10)
                .map(
                  (history) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      borderRadius: 16,
                      padding: const EdgeInsets.all(14),
                      borderColor: AppColors.neonGold.withValues(alpha: 0.25),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              gradient: AppColors.goldGradient,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.emoji_events_rounded,
                              color: Color(0xFF7C4DFF),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  history.displayTitle.isNotEmpty
                                      ? history.displayTitle
                                      : 'Daily Live Quiz',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    _MiniStat(
                                      icon: Icons.stars_rounded,
                                      value: '${history.score}',
                                      color: AppColors.neonGold,
                                    ),
                                    const SizedBox(width: 12),
                                    _MiniStat(
                                      icon: Icons.speed_rounded,
                                      value:
                                          '${history.accuracy.toStringAsFixed(0)}%',
                                      color: AppColors.neonCyan,
                                    ),
                                    const SizedBox(width: 12),
                                    _MiniStat(
                                      icon: Icons.bolt_rounded,
                                      value:
                                          '${history.timeSeconds.toStringAsFixed(0)}s',
                                      color: AppColors.neonPurple,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (history.coinsEarned > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.neonOrange.withValues(
                                      alpha: 0.2,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '+${history.coinsEarned}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.neonOrange,
                                    ),
                                  ),
                                ),
                              if (history.gemsEarned > 0) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.neonPurple.withValues(
                                      alpha: 0.2,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '+${history.gemsEarned}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.neonPurple,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _MiniStat({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
