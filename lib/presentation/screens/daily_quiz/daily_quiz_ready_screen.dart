import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/providers/quiz_provider.dart';
import '../../../data/providers/user_provider.dart';
import '../../../data/services/haptic_service.dart';
import '../../../data/services/sound_service.dart';
import '../../../l10n/app_strings.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/neon_button.dart';
import 'daily_quiz_screen.dart';

/// The gate between a notification tap and a live daily run.
///
/// The 19:00 reminder used to open [DailyQuizScreen] *and* start the run in the
/// same breath: the timer began under whatever screen the player happened to be
/// on, and the day's one counted attempt was spent before they had decided to
/// play. A reminder tap now lands here instead — the run starts only on START.
///
/// Two rules keep the gate honest:
///  * it never starts anything by itself, and
///  * a run already in flight is resumed, never restarted — a second tap must
///    not throw away a run the player has already begun (see
///    [QuizProvider.hasLiveDailyRun]).
class DailyQuizReadyScreen extends StatelessWidget {
  const DailyQuizReadyScreen({super.key});

  /// Opens the run the player already owns.
  ///
  /// Reached by a second tap of the reminder, by a run started from the
  /// dashboard while this gate was open, or by a cold-start race — starting a
  /// fresh run here would abandon the live one, so the gate simply gets out of
  /// the way.
  void _openLiveRun(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(builder: (_) => const DailyQuizScreen()),
    );
  }

  void _start(BuildContext context) {
    final quiz = context.read<QuizProvider>();
    if (quiz.hasLiveDailyRun) {
      _openLiveRun(context);
      return;
    }
    SoundService.instance.play('ui_whoosh');
    Haptics.tap();
    quiz.startDailyQuiz();
    _openLiveRun(context);
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final streak = userProvider.user.dailyStreak;
    final locked = userProvider.isDailyScoreLockedToday;
    final retryOpen = userProvider.isDailyRetryUnlockedToday;
    final score = userProvider.todayCountedScore;

    // The same ranked/unranked wording the run itself shows, so the rule the
    // gate states is the rule the quiz honours.
    final String rankNote;
    if (retryOpen) {
      rankNote = S.dailyRetryBanner(score: score);
    } else if (locked) {
      rankNote = S.dailyLockedBanner(score: score);
    } else {
      rankNote = S.dailyCountedBanner;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(
              children: [
                _eyebrow(),
                const SizedBox(height: 12),
                _mascot(),
                const SizedBox(height: 16),
                Text(
                  S.dailyReadyTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  S.dailyReadyBody,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                _noteRow(
                  rankNote,
                  locked && !retryOpen
                      ? Icons.lock_rounded
                      : Icons.emoji_events_rounded,
                ),
                if (streak > 0) ...[
                  const SizedBox(height: 10),
                  _noteRow(
                    S.notifStreakBody(n: streak),
                    Icons.local_fire_department_rounded,
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: NeonButton(
                    text: S.dailyReadyStart,
                    height: 50,
                    borderRadius: 15,
                    icon: const Icon(
                      Icons.bolt_rounded,
                      color: Color(0xFF191126),
                      size: 20,
                    ),
                    gradient: AppColors.goldGradient,
                    glowColor: AppColors.neonGold,
                    onPressed: () => _start(context),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    S.dailyReadyNotNow,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _eyebrow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColors.neonGold.withValues(alpha: 0.12),
        border: Border.all(color: AppColors.neonGold.withValues(alpha: 0.45)),
      ),
      child: Text(
        S.dailyReadyEyebrow,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: AppColors.neonGold,
        ),
      ),
    );
  }

  Widget _mascot() {
    return Container(
      height: 148,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.neonPurple.withValues(alpha: 0.28),
            blurRadius: 46,
            spreadRadius: 6,
          ),
        ],
      ),
      child: Image.asset(AppAssets.dailyStar, fit: BoxFit.contain),
    );
  }

  Widget _noteRow(String text, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppColors.neonCyan),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
