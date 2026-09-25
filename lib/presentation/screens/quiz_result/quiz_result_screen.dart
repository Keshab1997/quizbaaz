import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_assets.dart';
import '../../../data/models/shop_item.dart';
import '../../../data/providers/auth_provider.dart';
import '../../../data/providers/quiz_provider.dart';
import '../../../data/providers/user_provider.dart';
import '../../../data/services/ad_service.dart';
import '../../../data/services/daily_score_lock.dart';
import '../../../data/services/hive_service.dart';
import '../../widgets/streak_motivation_dialog.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/neon_button.dart';
import '../leaderboard/leaderboard_screen.dart';
import 'review_answers_screen.dart';
import '../../widgets/cached_avatar.dart';
import '../../../l10n/app_strings.dart';

class QuizResultScreen extends StatefulWidget {
  const QuizResultScreen({super.key});

  @override
  State<QuizResultScreen> createState() => _QuizResultScreenState();
}

class _QuizResultScreenState extends State<QuizResultScreen> {
  @override
  void initState() {
    super.initState();
    // AdMob interstitial after a finished quiz — frequency-capped inside
    // AdService, so it never shows on every single quiz.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AdService.instance.showInterstitialAfterQuiz();
      _maybeShowStreakMotivation();
    });
  }

  /// Celebrates streak milestones (e.g. every [AppConfig.streakGoalDays]
  /// days) once per streak value — guarded in Hive so it never repeats.
  void _maybeShowStreakMotivation() {
    final userProvider = context.read<UserProvider>();
    final streak = userProvider.user.dailyStreak;
    final goal = userProvider.config.streakGoalDays;
    if (streak <= 0 || goal <= 0) return;
    if (streak % goal != 0) return;

    if (HiveService.getMeta<int>('last_streak_motivation') == streak) return;
    HiveService.setMeta('last_streak_motivation', streak);

    if (!mounted) return;
    StreakMotivationDialog.show(
      context,
      currentStreak: streak,
      streakGoal: goal,
      hasShield: userProvider.hasItem(ShopItemIds.streakShield),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quiz = context.watch<QuizProvider>();
    final userProvider = context.watch<UserProvider>();
    final auth = context.watch<AuthProvider>();
    final isGuest = userProvider.user.isGuest;

    final totalQuestions = quiz.questions.length;
    final score = quiz.score;
    final correct = quiz.correctCount;
    final wrong = quiz.wrongCount;

    // Actual rewards credited to the player's balance.
    final coinsEarned = quiz.earnedCoins;
    final gemsEarned = quiz.earnedGems;
    final rewardSkipped = quiz.dailyRewardSkipped;
    final isPerfect = correct == totalQuestions && totalQuestions > 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Background Glows
          Positioned(
            top: -50,
            left: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.neonGold.withValues(alpha: 0.15),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  // Trophy / 3D Asset — show the player's selected avatar
                  // (local asset or cloud/Google photo) instead of a hardcoded mascot.
                  Center(
                    child: _ResultAvatar(
                      avatar: userProvider.user.effectiveAvatar,
                      fallbackAsset: AppAssets.heroBoy,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Text(
                    S.resultCompleted,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppColors.neonGold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    S.resultSummary,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // Score Glass Card
                  GlassCard(
                    borderRadius: 24,
                    borderColor: AppColors.neonGold.withValues(alpha: 0.4),
                    backgroundColor: const Color(0x33281E48),
                    child: Column(
                      children: [
                        Text(
                          S.resultTotalScore,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$score',
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            color: AppColors.neonGold,
                          ),
                        ),
                        const Divider(color: Colors.white12, height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatColumn(S.correct, '$correct', AppColors.neonGreen, Icons.check_circle),
                            _buildStatColumn(S.wrong, '$wrong', AppColors.neonRed, Icons.cancel),
                            _buildStatColumn(S.coins, '+$coinsEarned', AppColors.neonGold, Icons.monetization_on),
                            _buildStatColumn(S.gems, '+$gemsEarned', AppColors.neonPurple, Icons.diamond),
                          ],
                        ),
                        if (quiz.isDailyQuiz && !isGuest) ...[
                          const SizedBox(height: 12),
                          _buildRankingNotice(quiz, userProvider),
                        ],
                        if (isPerfect) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.neonGold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.neonGold.withValues(alpha: 0.5)),
                            ),
                            child: Text(
                              S.resultPerfect,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.neonGold,
                              ),
                            ),
                          ),
                        ],
                        if (rewardSkipped) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'ℹ️ Today\'s daily reward already claimed — play again tomorrow!',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Score Shield: the only way to reopen a locked day, offered
                  // right where the player sees the score they are unhappy
                  // with.
                  if (quiz.isDailyQuiz &&
                      !isGuest &&
                      userProvider.canRetryDailyScoreWithShield) ...[
                    _buildShieldRetryCard(userProvider),
                    const SizedBox(height: 20),
                  ],

                  // Guest Conversion Card (If Guest)
                  if (isGuest) ...[
                    GlassCard(
                      borderColor: AppColors.neonCyan.withValues(alpha: 0.4),
                      backgroundColor: const Color(0x33003B46),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.workspace_premium, color: AppColors.neonCyan, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  S.resultSaveScore,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.neonCyan,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            S.resultGuestBody,
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 12),
                          NeonButton(
                            text: auth.isBusy ? S.resultSigningIn : S.resultGoogleSignIn,
                            height: 40,
                            gradient: AppColors.primaryGradient,
                            onPressed: auth.isBusy
                                ? () {}
                                : () => _handleGoogleSignIn(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Action Buttons
                  NeonButton(
                    text: S.resultLeaderboard,
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  NeonButton(
                    text: S.resultReview,
                    gradient: const LinearGradient(
                      colors: [AppColors.neonCyan, AppColors.neonPurple],
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ReviewAnswersScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: () {
                      Navigator.popUntil(context, (route) => route.isFirst);
                    },
                    child: Text(
                      S.resultBackHome,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tells the player exactly what happened to today's leaderboard score.
  ///
  /// Three things used to be invisible here and made the score look lost:
  /// whether the run was ranked at all (an unranked practice set never
  /// reaches the leaderboard — R12), whether this run was the one that
  /// counted, and that any later run is ignored by design.
  Widget _buildRankingNotice(QuizProvider quiz, UserProvider userProvider) {
    final ranked = quiz.isDailyRanked;
    // Defaults: the settle writes Hive and mirrors to Firestore behind the
    // scenes, so for a beat after the run ends the outcome is still unknown.
    var icon = Icons.emoji_events;
    var colour = AppColors.neonGreen;
    var message = S.resultDailyRankedNotice;

    if (!ranked) {
      icon = Icons.sports_score;
      colour = AppColors.neonGold;
      message = S.resultDailyUnrankedNotice;
    } else {
      switch (quiz.dailyScoreOutcome) {
        case DailyScoreOutcome.counted:
          icon = Icons.emoji_events;
          colour = AppColors.neonGreen;
          message = S.resultDailyCountedNotice(
            score: userProvider.todayCountedScore,
          );
          break;
        case DailyScoreOutcome.replaced:
          icon = Icons.shield;
          colour = AppColors.neonGreen;
          message = S.resultDailyReplacedNotice(
            score: userProvider.todayCountedScore,
          );
          break;
        case DailyScoreOutcome.ignored:
          icon = Icons.lock;
          colour = AppColors.neonGold;
          message = S.resultDailyLockedNotice(
            score: userProvider.todayCountedScore,
          );
          break;
        case DailyScoreOutcome.notApplicable:
          // Nothing to report yet (or a guest, whose run never counts) — the
          // defaults above already say the right thing.
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colour.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colour),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colour,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Offers to spend a Score Shield so the player's next daily attempt
  /// replaces today's locked score.
  Widget _buildShieldRetryCard(UserProvider userProvider) {
    final score = userProvider.todayCountedScore;
    final stock = userProvider.inventoryCount(ShopItemIds.scoreShield);
    return GlassCard(
      borderColor: AppColors.neonPurple.withValues(alpha: 0.45),
      backgroundColor: const Color(0x33281E48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.shield, color: AppColors.neonPurple, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  S.resultShieldRetryTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.neonPurple,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            S.resultShieldRetryBody(score: score),
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          NeonButton(
            text: S.resultShieldRetryAction(count: stock),
            height: 42,
            gradient: AppColors.primaryGradient,
            onPressed: () => _confirmShieldRetry(userProvider),
          ),
        ],
      ),
    );
  }

  /// Confirms before spending a paid item, then sends the player back to the
  /// dashboard where the daily quiz card starts the replacement run.
  Future<void> _confirmShieldRetry(UserProvider userProvider) async {
    // Grabbed before the awaits: the same BuildContext must not be touched
    // across an async gap.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF1B1230),
            title: Text(
              S.resultShieldRetryDialogTitle,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            content: Text(
              S.resultShieldRetryDialogBody,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                  S.cancel,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  S.resultShieldRetryConfirm,
                  style: const TextStyle(color: AppColors.neonPurple),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    final spent = await userProvider.unlockDailyScoreWithShield();
    if (!spent || !mounted) return;

    // Back to the dashboard, where the daily quiz card starts the run that
    // replaces today's score.
    navigator.popUntil((route) => route.isFirst);
    messenger.showSnackBar(
      SnackBar(content: Text(S.resultShieldRetryDone)),
    );
  }

  Future<void> _handleGoogleSignIn(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final userProvider = context.read<UserProvider>();
    final messenger = ScaffoldMessenger.of(context);

    if (auth.isBusy) return;

    try {
      final signedIn = await auth.signInWithGoogle();
      if (!signedIn) {
        messenger.showSnackBar(SnackBar(content: Text(S.authSignInCanceled)));
        return;
      }

      final user = auth.firebaseUser;
      if (user == null) return;

      await userProvider.linkGoogleAccount(
        user.displayName ?? user.email ?? S.battlePlayer,
        user.email ?? user.uid,
        photoURL: user.photoURL,
        uid: user.uid,
      );

      messenger.showSnackBar(
        SnackBar(content: Text(S.resultSignedIn)),
      );
    } on AuthException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade800),
      );
    }
  }

  Widget _buildStatColumn(String title, String val, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          val,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Shows the player's selected profile avatar (local asset or cloud/Google
/// photo). Falls back to the classic mascot when the avatar can't be loaded.
class _ResultAvatar extends StatelessWidget {
  final String avatar;
  final String fallbackAsset;

  const _ResultAvatar({required this.avatar, required this.fallbackAsset});

  bool get _isRemote =>
      avatar.startsWith('http://') || avatar.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    if (_isRemote) {
      return CachedAvatar(
        url: avatar,
        height: 150,
        fit: BoxFit.contain,
        fallbackAsset: fallbackAsset,
        fallbackIcon: Icons.military_tech,
        fallbackIconColor: AppColors.neonGold,
        fallbackIconSize: 90,
      );
    }
    return Image.asset(
      avatar.isNotEmpty ? avatar : fallbackAsset,
      height: 150,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => const Icon(
        Icons.military_tech,
        size: 90,
        color: AppColors.neonGold,
      ),
    );
  }
}
