import 'package:flutter/material.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/user_model.dart';
import 'glass_card.dart';

class StreakFlameWidget extends StatelessWidget {
  final int streakDays;
  final String? lastStreakDate;
  final List<String> streakDates;
  final DateTime? referenceDate;
  final VoidCallback? onTap;

  const StreakFlameWidget({
    super.key,
    required this.streakDays,
    this.lastStreakDate,
    this.streakDates = const <String>[],
    this.referenceDate,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final now = referenceDate ?? DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final mondayOfThisWeek = todayDate.subtract(
      Duration(days: todayDate.weekday - 1),
    );
    final effectiveLastStreakDate =
        (lastStreakDate == null && streakDates.isEmpty && streakDays > 0)
            ? UserModel.dateKey(todayDate)
            : lastStreakDate;
    final playedToday = UserModel.isDatePlayed(
      todayDate,
      streakDays: streakDays,
      lastStreakDate: effectiveLastStreakDate,
      streakDates: streakDates,
    );

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
                fit: BoxFit.contain,
                errorBuilder:
                    (context, error, stackTrace) => const Icon(
                      Icons.local_fire_department,
                      color: Colors.orangeAccent,
                      size: 32,
                    ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
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
                    Text(
                      playedToday
                          ? 'Today\'s streak completed! Keep it burning 🔥'
                          : 'Play Daily Quiz or Battle Arena to keep streak alive!',
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            playedToday
                                ? AppColors.neonGreen
                                : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Real Monday–Sunday calendar slots for the current week:
          //   * played day (Daily Quiz or Battle Arena) -> check (✓)
          //   * past day not played -> cross (✕)
          //   * today (not played yet) -> highlighted day letter
          //   * future day in this week -> muted day letter
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (index) {
              final dayDate = mondayOfThisWeek.add(Duration(days: index));
              final isToday =
                  dayDate.year == todayDate.year &&
                  dayDate.month == todayDate.month &&
                  dayDate.day == todayDate.day;
              final isPast = dayDate.isBefore(todayDate);
              final isPlayed = UserModel.isDatePlayed(
                dayDate,
                streakDays: streakDays,
                lastStreakDate: effectiveLastStreakDate,
                streakDates: streakDates,
              );
              final isMissed = isPast && !isPlayed;

              final Color fillColor;
              final Color borderColor;
              final Widget centerChild;
              if (isPlayed) {
                fillColor = AppColors.neonGold.withValues(alpha: 0.22);
                borderColor = isToday ? AppColors.neonCyan : AppColors.neonGold;
                centerChild = const Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: AppColors.neonGold,
                );
              } else if (isMissed) {
                fillColor = AppColors.neonRed.withValues(alpha: 0.16);
                borderColor = AppColors.neonRed.withValues(alpha: 0.65);
                centerChild = const Icon(
                  Icons.close_rounded,
                  size: 17,
                  color: AppColors.neonRed,
                );
              } else if (isToday) {
                fillColor = AppColors.neonPurple.withValues(alpha: 0.3);
                borderColor = AppColors.neonCyan;
                centerChild = Text(
                  days[index],
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.neonCyan,
                  ),
                );
              } else {
                fillColor = Colors.white.withValues(alpha: 0.05);
                borderColor = Colors.white.withValues(alpha: 0.1);
                centerChild = Text(
                  days[index],
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                    color: AppColors.textSecondary,
                  ),
                );
              }

              final Color labelColor;
              if (isToday) {
                labelColor = AppColors.neonCyan;
              } else if (isPlayed) {
                labelColor = AppColors.neonGold;
              } else if (isMissed) {
                labelColor = AppColors.neonRed.withValues(alpha: 0.85);
              } else {
                labelColor = AppColors.textMuted;
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: fillColor,
                      border: Border.all(
                        color: borderColor,
                        width: isToday ? 2 : 1.2,
                      ),
                    ),
                    child: Center(child: centerChild),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    days[index],
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          (isToday || isPlayed || isMissed)
                              ? FontWeight.w800
                              : FontWeight.w600,
                      color: labelColor,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}
