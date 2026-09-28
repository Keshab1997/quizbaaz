import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_colors.dart';
import '../../data/providers/user_provider.dart';
import '../../data/services/haptic_service.dart';
import '../../data/services/sound_service.dart';
import '../screens/shop/shop_screen.dart';
import 'glass_card.dart';

/// Popup dialog shown when a user misses a day and their Daily Streak is reset.
/// Features 3D illustrations, animations, and motivational content.
class StreakResetDialog extends StatefulWidget {
  final StreakResetDetails details;

  const StreakResetDialog({super.key, required this.details});

  static Future<void> show(BuildContext context, StreakResetDetails details) {
    SoundService.instance.play('battle_lose');
    Haptics.error();
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StreakResetDialog(details: details),
    );
  }

  @override
  State<StreakResetDialog> createState() => _StreakResetDialogState();
}

class _StreakResetDialogState extends State<StreakResetDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _shakeAnimation = Tween<double>(begin: 0, end: 10).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );

    // Shake animation for emphasis
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _shakeController.forward();
    });
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  String _getEncouragementMessage() {
    if (widget.details.lostStreak >= 30) {
      return 'You had an amazing ${widget.details.lostStreak}-day streak! That\'s truly impressive. Let\'s start fresh and beat it! 💪';
    } else if (widget.details.lostStreak >= 14) {
      return 'You were on fire for ${widget.details.lostStreak} days! Every streak can be rebuilt. Ready for round 2? 🔥';
    } else if (widget.details.lostStreak >= 7) {
      return 'A solid ${widget.details.lostStreak}-day streak! The best time to start a new one is now. Let\'s go! 🚀';
    } else if (widget.details.lostStreak >= 3) {
      return 'Good run! ${widget.details.lostStreak} days is just the beginning. Start a new streak today! ✨';
    } else {
      return 'No worries! Every master was once a beginner. Let\'s build something great! 🌟';
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: AnimatedBuilder(
        animation: _shakeAnimation,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(
              _shakeAnimation.value * (0.5 - (_shakeController.value)),
              0,
            ),
            child: GlassCard(
              borderRadius: 28,
              borderColor: AppColors.neonRed.withValues(alpha: 0.6),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 3D Broken/Burning Fire Illustration
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Warning glow
                      Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              AppColors.neonRed.withValues(alpha: 0.3),
                              AppColors.neonOrange.withValues(alpha: 0.1),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      // Broken fire icon
                      Image.asset(
                        AppAssets.streakBroken3d,
                        height: 85,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.neonRed.withValues(alpha: 0.2),
                              ),
                            ),
                            const Icon(
                              Icons.local_fire_department_rounded,
                              size: 60,
                              color: AppColors.neonRed,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Header Title
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('😢', style: TextStyle(fontSize: 24)),
                      SizedBox(width: 8),
                      Text(
                        'STREAK LOST!',
                        style: TextStyle(
                          color: AppColors.neonRed,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text('💔', style: TextStyle(fontSize: 24)),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Streak lost info
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.neonRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.neonRed.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.trending_down_rounded,
                          color: AppColors.neonRed,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Your ${widget.details.lostStreak}-Day Streak',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Encouragement message
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Text('💡', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _getEncouragementMessage(),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Streak Shield Recovery Box
                  if (widget.details.hasShield) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.neonGreen.withValues(alpha: 0.2),
                            AppColors.neonCyan.withValues(alpha: 0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.neonGreen.withValues(alpha: 0.5),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.neonGreen.withValues(alpha: 0.2),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                AppAssets.streakShield3d,
                                width: 28,
                                height: 28,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.shield_moon_rounded,
                                  color: AppColors.neonGreen,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                '🛡️ STREAK SHIELD AVAILABLE!',
                                style: TextStyle(
                                  color: AppColors.neonGreen,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'You have a Streak Shield! Use it to restore your ${widget.details.lostStreak}-Day Streak instantly!',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.neonGreen,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 6,
                                shadowColor: AppColors.neonGreen.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              onPressed: () {
                                final restored = userProvider
                                    .restoreStreakWithShield(
                                      widget.details.lostStreak,
                                    );
                                Navigator.pop(context);
                                if (restored) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          const Icon(
                                            Icons.shield_rounded,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '🛡️ ${widget.details.lostStreak}-Day Streak restored!',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      backgroundColor: AppColors.neonGreen,
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.restore_rounded, size: 20),
                              label: const Text(
                                'RESTORE STREAK NOW',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ] else ...[
                    // Prompt to Buy Shield
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.neonGold.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Image.asset(
                                AppAssets.streakShield3d,
                                width: 36,
                                height: 36,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.shield_moon_outlined,
                                  color: AppColors.neonGold,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Protect Your Future Streaks!',
                                      style: TextStyle(
                                        color: AppColors.neonGold,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Get a Streak Shield to never lose your streak again.',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 40,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.neonGold,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ShopScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.shopping_bag_rounded,
                                size: 18,
                              ),
                              label: const Text(
                                'Get Shield',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Continue Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.refresh_rounded,
                            color: AppColors.textMuted,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.details.hasShield
                                ? 'No Thanks, Start Fresh'
                                : 'Let\'s Rebuild! 🚀',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
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
