import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_colors.dart';
import '../../data/providers/user_provider.dart';
import '../../data/services/haptic_service.dart';
import '../../data/services/sound_service.dart';
import '../widgets/glass_card.dart';

/// Motivational dialog to encourage user to maintain their streak and view
/// upcoming streak milestone rewards.
class StreakMotivationDialog extends StatefulWidget {
  final int currentStreak;
  final int streakGoal;
  final bool hasShield;
  final StreakMilestoneReward? unlockedReward;

  const StreakMotivationDialog({
    super.key,
    required this.currentStreak,
    required this.streakGoal,
    this.hasShield = false,
    this.unlockedReward,
  });

  static Future<void> show(
    BuildContext context, {
    required int currentStreak,
    required int streakGoal,
    bool hasShield = false,
    StreakMilestoneReward? unlockedReward,
  }) {
    SoundService.instance.play('fire');
    Haptics.medium();
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (_) => StreakMotivationDialog(
            currentStreak: currentStreak,
            streakGoal: streakGoal,
            hasShield: hasShield,
            unlockedReward: unlockedReward,
          ),
    );
  }

  @override
  State<StreakMotivationDialog> createState() => _StreakMotivationDialogState();
}

class _StreakMotivationDialogState extends State<StreakMotivationDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fireAnimation;
  Timer? _repeatTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));

    _fireAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.forward();

    _repeatTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        _controller.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  int get _effectiveGoal =>
      StreakMilestoneReward.nextGoalFor(widget.currentStreak);

  String _getMotivationalMessage() {
    final streak = widget.currentStreak;
    if (streak == 0) {
      return 'Start your journey today! Play Daily Quiz or Battle Arena 💪';
    } else if (streak < 3) {
      final rem = 3 - streak;
      return 'Great start! Just $rem more day${rem == 1 ? '' : 's'} for your 3-Day Bonus 🔥';
    } else if (streak < 7) {
      final remaining = (7 - streak).clamp(1, 7);
      return 'You\'re on fire! Just $remaining more day${remaining == 1 ? '' : 's'} to the 7-Day Reward! 🔥';
    } else if (streak < 14) {
      return 'Amazing consistency! $streak days strong — 14-Day Shield ahead! 🏆';
    } else if (streak < 30) {
      return 'Incredible! You\'re a streak master aiming for Day 30! 👑';
    } else {
      return 'Legendary! $streak days - you\'re unstoppable! 🌟';
    }
  }

  Widget _buildMilestoneTier({
    required int days,
    required String rewardText,
    required String emoji,
  }) {
    final isUnlocked = widget.currentStreak >= days;
    final isNext = !isUnlocked && _effectiveGoal == days;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color:
            isUnlocked
                ? AppColors.neonGreen.withValues(alpha: 0.14)
                : (isNext
                    ? AppColors.neonGold.withValues(alpha: 0.14)
                    : Colors.white.withValues(alpha: 0.05)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              isUnlocked
                  ? AppColors.neonGreen.withValues(alpha: 0.6)
                  : (isNext
                      ? AppColors.neonGold.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.1)),
          width: isNext ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$days-Day Streak',
                  style: TextStyle(
                    color:
                        isUnlocked
                            ? AppColors.neonGreen
                            : (isNext ? AppColors.neonGold : Colors.white),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  rewardText,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (isUnlocked)
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.neonGreen,
              size: 18,
            )
          else if (isNext)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.neonGold.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'NEXT',
                style: TextStyle(
                  color: AppColors.neonGold,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final targetGoal = _effectiveGoal;
    final daysRemaining = (targetGoal - widget.currentStreak).clamp(
      0,
      targetGoal,
    );
    final progress = targetGoal > 0 ? widget.currentStreak / targetGoal : 0.0;
    final unlocked = widget.unlockedReward;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: SingleChildScrollView(
              child: GlassCard(
                borderRadius: 28,
                borderColor: AppColors.neonGold.withValues(alpha: 0.5),
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated Fire Icon
                    Transform.scale(
                      scale: _fireAnimation.value,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  AppColors.neonGold.withValues(alpha: 0.3),
                                  AppColors.neonOrange.withValues(alpha: 0.1),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                          if (widget.hasShield)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppColors.neonGreen,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.neonGreen.withValues(
                                        alpha: 0.5,
                                      ),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: Image.asset(
                                  AppAssets.streakShield3d,
                                  width: 22,
                                  height: 22,
                                  errorBuilder:
                                      (_, __, ___) => const Icon(
                                        Icons.shield_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                ),
                              ),
                            ),
                          Image.asset(
                            AppAssets.streakFire3d,
                            height: 82,
                            fit: BoxFit.contain,
                            errorBuilder:
                                (_, __, ___) => const Icon(
                                  Icons.local_fire_department_rounded,
                                  size: 68,
                                  color: AppColors.neonOrange,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Streak Count
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${widget.currentStreak}',
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            color: AppColors.neonGold,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DAY',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              'STREAK',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    if (unlocked != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: AppColors.neonGreen.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.neonGreen.withValues(alpha: 0.7),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '🎁 ${unlocked.streakDays}-DAY MILESTONE UNLOCKED!',
                              style: const TextStyle(
                                color: AppColors.neonGreen,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '+${unlocked.coins} Coins · +${unlocked.gems} Gems'
                              '${unlocked.itemNames.isNotEmpty ? " · ${unlocked.itemNames.join(", ")}" : ""}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Progress bar
                    Container(
                      height: 10,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Stack(
                          children: [
                            AnimatedFractionallySizedBox(
                              duration: const Duration(milliseconds: 800),
                              widthFactor: progress.clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: AppColors.fireGradient,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.neonOrange.withValues(
                                        alpha: 0.5,
                                      ),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    Text(
                      daysRemaining > 0
                          ? '$daysRemaining more day${daysRemaining == 1 ? '' : 's'} to reach Day $targetGoal reward!'
                          : '🎉 Goal reached! Bonus unlocked!',
                      style: TextStyle(
                        color:
                            daysRemaining > 0
                                ? AppColors.textSecondary
                                : AppColors.neonGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Milestone Rewards List
                    _buildMilestoneTier(
                      days: 3,
                      emoji: '🔥',
                      rewardText: '+25 Coins · +2 Gems',
                    ),
                    _buildMilestoneTier(
                      days: 7,
                      emoji: '🏆',
                      rewardText: '+50 Coins · +5 Gems · 50-50 Lifeline',
                    ),
                    _buildMilestoneTier(
                      days: 14,
                      emoji: '🛡️',
                      rewardText: '+100 Coins · +10 Gems · Streak Shield',
                    ),
                    _buildMilestoneTier(
                      days: 30,
                      emoji: '👑',
                      rewardText: '+250 Coins · +25 Gems · Shield + 2x Booster',
                    ),
                    const SizedBox(height: 8),

                    // Motivational message
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.neonOrange.withValues(alpha: 0.15),
                            AppColors.neonGold.withValues(alpha: 0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.neonGold.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Text('💡', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _getMotivationalMessage(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Action button
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.neonGold,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 8,
                          shadowColor: AppColors.neonOrange.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.play_arrow_rounded, size: 22),
                            const SizedBox(width: 6),
                            Text(
                              widget.currentStreak == 0
                                  ? 'START TODAY'
                                  : 'KEEP GOING!',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
