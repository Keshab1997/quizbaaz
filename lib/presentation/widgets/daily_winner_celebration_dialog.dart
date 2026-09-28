import 'package:flutter/material.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_colors.dart';
import '../../data/providers/user_provider.dart';
import '../../data/services/haptic_service.dart';
import '../../data/services/sound_service.dart';
import 'glass_card.dart';

/// Modal dialog celebrating yesterday's Daily Quiz leaderboard rank win.
class DailyWinnerCelebrationDialog extends StatelessWidget {
  final DailyRewardResult reward;

  const DailyWinnerCelebrationDialog({super.key, required this.reward});

  static Future<void> show(BuildContext context, DailyRewardResult reward) {
    SoundService.instance.play('champion');
    Haptics.heavy();
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => DailyWinnerCelebrationDialog(reward: reward),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isChampion = reward.rank == 1;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: GlassCard(
        borderRadius: 24,
        borderColor: AppColors.neonGold.withValues(alpha: 0.6),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mascot / Trophy Header
            Image.asset(
              AppAssets.championBoy,
              height: 120,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.emoji_events_rounded,
                size: 80,
                color: AppColors.neonGold,
              ),
            ),
            const SizedBox(height: 12),

            // Rank Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.neonGold.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.neonGold.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isChampion
                        ? Icons.workspace_premium_rounded
                        : Icons.military_tech_rounded,
                    color: AppColors.neonGold,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isChampion
                        ? '🏆 DAILY CHAMPION (#1)'
                        : '🥈 TOP WINNER (#${reward.rank})',
                    style: const TextStyle(
                      color: AppColors.neonGold,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            const Text(
              'Yesterday\'s Quiz Rewards!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Congratulations! Your top performance on the Daily Leaderboard earned you shop gifts & coins!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),

            // Rewards Breakdown Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _rewardPill(
                        Icons.monetization_on_rounded,
                        '+${reward.coins} Coins',
                        AppColors.neonGold,
                      ),
                      _rewardPill(
                        Icons.diamond_rounded,
                        '+${reward.gems} Gems',
                        AppColors.neonPurple,
                      ),
                    ],
                  ),
                  if (reward.itemNames.isNotEmpty) ...[
                    const Divider(color: Colors.white12, height: 20),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '🎁 UNLOCKED SHOP ITEMS:',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: AppColors.neonCyan,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final item in reward.itemNames)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.neonGreen,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    item,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Winning Streak Milestone
            if (reward.winningStreak > 1) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.neonRed.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.neonRed.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.local_fire_department_rounded,
                      color: AppColors.neonRed,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '🔥 ${reward.winningStreak}-Day Winning Streak!',
                      style: const TextStyle(
                        color: AppColors.neonRed,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (reward.milestonePrizeTitle != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '• ${reward.milestonePrizeTitle}',
                        style: const TextStyle(
                          color: AppColors.neonGold,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Claim Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.neonGold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.shopping_bag_rounded, size: 20),
                label: const Text(
                  'Claim to Inventory & Shop',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rewardPill(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
