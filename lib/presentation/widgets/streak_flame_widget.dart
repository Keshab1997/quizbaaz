import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_assets.dart';
import 'glass_card.dart';

class StreakFlameWidget extends StatelessWidget {
  final int streakDays;
  final VoidCallback? onTap;

  const StreakFlameWidget({super.key, required this.streakDays, this.onTap});

  @override
  Widget build(BuildContext context) {
    final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return GlassCard(
      onTap: onTap,
      borderColor: AppColors.neonGold.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(
                AppAssets.streakFire,
                width: 38,
                height: 38,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.local_fire_department,
                  color: Colors.orangeAccent,
                  size: 32,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '$streakDays Days',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.neonGold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'STREAK 🔥',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'Play today to keep streak alive!',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Day bubbles — a 7-slot weekly cycle. A streak that is an exact
          // multiple of 7 fills all 7 slots; otherwise the remainder fills the
          // first slots and the next slot is "today".
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (index) {
              final cycle = streakDays % 7;
              final completedCount = (cycle == 0 && streakDays > 0) ? 7 : cycle;
              final isCompleted = index < completedCount;
              final isToday =
                  streakDays == 0 ? index == 0 : (cycle != 0 && index == cycle);

              return Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted
                      ? AppColors.neonGold.withValues(alpha: 0.2)
                      : (isToday
                          ? AppColors.neonPurple.withValues(alpha: 0.3)
                          : Colors.white.withValues(alpha: 0.05)),
                  border: Border.all(
                    color: isCompleted
                        ? AppColors.neonGold
                        : (isToday
                            ? AppColors.neonCyan
                            : Colors.white.withValues(alpha: 0.1)),
                    width: isToday ? 2 : 1,
                  ),
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(
                          Icons.check,
                          size: 16,
                          color: AppColors.neonGold,
                        )
                      : Text(
                          days[index],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                isToday ? FontWeight.bold : FontWeight.normal,
                            color: isToday
                                ? AppColors.neonCyan
                                : AppColors.textSecondary,
                          ),
                        ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
