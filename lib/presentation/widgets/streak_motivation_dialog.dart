import 'package:flutter/material.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_colors.dart';
import '../../data/services/haptic_service.dart';
import '../../data/services/sound_service.dart';
import '../widgets/glass_card.dart';

/// Motivational dialog to encourage user to maintain their streak.
class StreakMotivationDialog extends StatefulWidget {
  final int currentStreak;
  final int streakGoal;
  final bool hasShield;

  const StreakMotivationDialog({
    super.key,
    required this.currentStreak,
    required this.streakGoal,
    this.hasShield = false,
  });

  static Future<void> show(
    BuildContext context, {
    required int currentStreak,
    required int streakGoal,
    bool hasShield = false,
  }) {
    SoundService.instance.play('fire');
    Haptics.medium();
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => StreakMotivationDialog(
        currentStreak: currentStreak,
        streakGoal: streakGoal,
        hasShield: hasShield,
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

    // Repeat fire animation
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        _controller.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _getMotivationalMessage() {
    final streak = widget.currentStreak;
    if (streak == 0) {
      return 'Start your journey today! Every streak begins with Day 1 💪';
    } else if (streak < 3) {
      return 'Great start! Keep the fire burning 🔥';
    } else if (streak < 7) {
      // Days LEFT to the goal — not the current streak.
      final remaining = (widget.streakGoal - streak).clamp(
        1,
        widget.streakGoal,
      );
      return 'You\'re on fire! Just $remaining more day${remaining == 1 ? '' : 's'} to the goal! 🔥';
    } else if (streak < 14) {
      return 'Amazing consistency! $streak days strong! 🏆';
    } else if (streak < 30) {
      return 'Incredible! You\'re a streak master! 👑';
    } else {
      return 'Legendary! $streak days - you\'re unstoppable! 🌟';
    }
  }

  @override
  Widget build(BuildContext context) {
    final daysRemaining = (widget.streakGoal - widget.currentStreak).clamp(
      0,
      widget.streakGoal,
    );
    final progress =
        widget.streakGoal > 0 ? widget.currentStreak / widget.streakGoal : 0.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: GlassCard(
              borderRadius: 28,
              borderColor: AppColors.neonGold.withValues(alpha: 0.5),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated Fire Icon
                  Transform.scale(
                    scale: _fireAnimation.value,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Glow effect
                        Container(
                          width: 120,
                          height: 120,
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
                        // Shield badge if available
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
                                width: 24,
                                height: 24,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.shield_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        // Fire image
                        Image.asset(
                          AppAssets.streakFire3d,
                          height: 90,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.local_fire_department_rounded,
                            size: 72,
                            color: AppColors.neonOrange,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Streak Count
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${widget.currentStreak}',
                        style: const TextStyle(
                          fontSize: 48,
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
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            'STREAK',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Progress bar
                  Container(
                    height: 12,
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

                  // Goal text
                  Text(
                    daysRemaining > 0
                        ? '$daysRemaining days to unlock bonus reward!'
                        : '🎉 Goal reached! Bonus unlocked!',
                    style: TextStyle(
                      color: daysRemaining > 0
                          ? AppColors.textSecondary
                          : AppColors.neonGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Motivational message
                  Container(
                    padding: const EdgeInsets.all(12),
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
                        const Text('💡', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _getMotivationalMessage(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Action button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
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
                          const Icon(Icons.play_arrow_rounded, size: 24),
                          const SizedBox(width: 6),
                          Text(
                            widget.currentStreak == 0
                                ? 'START TODAY'
                                : 'KEEP GOING!',
                            style: const TextStyle(
                              fontSize: 15,
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
          );
        },
      ),
    );
  }
}
