import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/champion_model.dart';
import '../../../data/models/leaderboard_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/user_stats.dart';
import '../../../data/providers/quiz_provider.dart';
import '../../../data/providers/rewards_provider.dart';
import '../../../data/providers/user_provider.dart';
import '../../../data/services/ad_service.dart';
import '../../../data/services/consent_service.dart';
import '../../../data/services/haptic_service.dart';
import '../../../data/services/notification_inbox.dart';
import '../../../data/services/notification_service.dart';
import '../../../data/services/onesignal_service.dart';
import '../../../data/services/sound_service.dart';
import '../../app_navigator.dart';
import '../../../l10n/app_strings.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/name_effect_text.dart';
import '../../widgets/neon_button.dart';
import '../admin/admin_dashboard_screen.dart';
import '../battle/battle_screen.dart';
import '../battle/online_battle_screen.dart';
import '../chapter_quiz/chapter_list_screen.dart';
import '../daily_quiz/daily_quiz_screen.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../history/quiz_history_screen.dart';
import '../notifications/notification_history_screen.dart';
import '../profile/profile_screen.dart';
import '../rewards/rewards_screen.dart';
import '../shop/shop_screen.dart';
import '../../widgets/aura_avatar.dart';
import '../../widgets/cached_avatar.dart';
import '../../widgets/daily_winner_celebration_dialog.dart';
import '../../widgets/streak_reset_dialog.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentNavIndex = 0;
  final bool _isFemaleMascot = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userProvider = context.read<UserProvider>();
      await userProvider.initialize();
      if (!mounted) return;
      unawaited(NotificationService.instance.bootstrap());
      unawaited(OneSignalService.instance.syncFromHive());
      NotificationInbox.instance.reload();
      AppNavigator.flushPending();
      context
          .read<RewardsProvider>()
          .initialize(userId: userProvider.user.userId);

      // UMP consent: shows Google's consent form only where required
      // (EU/EEA/UK). Ads are gated until this resolves; elsewhere this
      // returns immediately.
      await ConsentService.instance.showConsentFormIfRequired();

      // Preload the AdMob interstitial so it is ready when a quiz ends.
      AdService.instance.preloadInterstitial();

      // Check and claim yesterday's daily leaderboard rewards!
      final reward = await userProvider.checkAndClaimDailyLeaderboardRewards();

      // Streak reset warning takes priority over the reward celebration —
      // it is the more urgent message (and both can occur on the same day).
      if (mounted) {
        final streakReset = userProvider.checkStreakResetWarning();
        if (streakReset != null) {
          StreakResetDialog.show(context, streakReset);
        } else if (reward != null) {
          DailyWinnerCelebrationDialog.show(context, reward);
        }
      }
    });
  }

  Future<void> _refresh() async {
    final userProvider = context.read<UserProvider>();
    await Future.wait([
      userProvider.refreshRankings(force: true),
      context
          .read<RewardsProvider>()
          .initialize(userId: userProvider.user.userId),
    ]);
  }

  /// Opens a tab and restores the Home highlight once the user comes back,
  /// so the bottom bar never lies about where you are.
  Future<void> _openTab(int index, Widget screen) async {
    setState(() => _currentNavIndex = index);
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) setState(() => _currentNavIndex = 0);
  }

  void _onNavTap(int index) {
    SoundService.instance.play('ui_click');
    Haptics.tap();
    switch (index) {
      case 0:
        setState(() => _currentNavIndex = 0);
        break;
      case 1:
        _openTab(1, const ChapterListScreen());
        break;
      case 2:
        _openTab(2, const LeaderboardScreen());
        break;
      case 3:
        _openTab(3, const ProfileScreen());
        break;
    }
  }

  /// Time-aware greeting instead of a fixed "Good morning".
  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 5) return S.greetStillAwake;
    if (hour < 12) return S.greetMorning;
    if (hour < 17) return S.greetAfternoon;
    if (hour < 21) return S.greetEvening;
    return S.greetNight;
  }

  void _startDailyQuiz() {
    SoundService.instance.play('ui_whoosh');
    Haptics.tap();
    context.read<QuizProvider>().startDailyQuiz();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DailyQuizScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final user = userProvider.user;
    final heroAsset = _isFemaleMascot ? AppAssets.heroGirl : AppAssets.heroBoy;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.neonCyan,
          backgroundColor: AppColors.surfaceElevated,
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 132),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Header — নাম + coins/gems
                      _buildHeader(user, userProvider),
                      const SizedBox(height: 16),

                      // 2. Streak Card
                      _buildStreakCard(user, userProvider),
                      const SizedBox(height: 16),

                      // 3. Battle Arena Card
                      const _BattleArenaCard(),
                      const SizedBox(height: 16),

                      // 4. Daily Quiz Hero Card
                      _buildHeroCard(heroAsset, userProvider),
                      const SizedBox(height: 14),

                      // 5. Stat Strip
                      _buildStatStrip(user, userProvider),
                      const SizedBox(height: 22),

                      // 6. Daily Quiz Champion Card
                      _buildChampionCard(userProvider),
                      const SizedBox(height: 22),

                      // 7. Daily Quiz Leaderboard
                      _buildSectionHeader(
                        eyebrow: S.dashLiveToday,
                        title: S.dashLeaderboard,
                        actionLabel: S.dashViewFull,
                        onAction: () => _onNavTap(2),
                      ),
                      const SizedBox(height: 12),
                      _buildLeaderboardPreview(userProvider),
                      const SizedBox(height: 22),

                      // 8. Quick Actions
                      _buildSectionHeader(
                        eyebrow: S.dashExploreMore,
                        title: S.dashMoreOptions,
                      ),
                      const SizedBox(height: 12),
                      _buildQuickActions(),
                      const SizedBox(height: 12),
                      if (userProvider.isAdmin) _buildAdminShortcut(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // AdMob banner (SizedBox.shrink until loaded — no layout jump).
          // Rebuilt when consent resolves, so EU/UK users get their banner
          // right after answering the consent form.
          ListenableBuilder(
            listenable: ConsentService.instance,
            builder: (context, _) => AdService.instance.banner(),
          ),
          _buildBottomNavigation(),
        ],
      ),
    );
  }

  bool _isNetworkAvatar(String avatar) =>
      avatar.startsWith('http://') || avatar.startsWith('https://');

  Widget _avatarImage(
    String avatar, {
    BoxFit fit = BoxFit.cover,
    Alignment alignment = Alignment.center,
    double? width,
    double? height,
    IconData fallbackIcon = Icons.person_rounded,
    double fallbackSize = 28,
  }) {
    if (_isNetworkAvatar(avatar)) {
      return CachedAvatar(
        url: avatar,
        fit: fit,
        alignment: alignment,
        width: width,
        height: height,
        fallbackIcon: fallbackIcon,
        fallbackIconColor: Colors.white,
        fallbackIconSize: fallbackSize,
      );
    }

    return Image.asset(
      avatar,
      fit: fit,
      alignment: alignment,
      width: width,
      height: height,
      errorBuilder: (_, __, ___) => Icon(
        fallbackIcon,
        color: Colors.white,
        size: fallbackSize,
      ),
    );
  }

  Widget _buildHeader(UserModel user, UserProvider userProvider) {
    return Row(
      children: [
        AuraAvatar(
          url: user.effectiveAvatar,
          size: 68,
          fallbackAsset: user.avatarPath,
          onTap: () => _openTab(3, const ProfileScreen()),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MarqueeText(
                '$_greeting  👋',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              _MarqueeText(
                user.fullName.isNotEmpty ? user.fullName : user.username,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
                effectId: user.nameEffect,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _buildCurrencyPill(
          icon: Icons.monetization_on_rounded,
          value: '${user.coins}',
          color: AppColors.neonGold,
        ),
        const SizedBox(width: 6),
        _buildCurrencyPill(
          icon: Icons.diamond_rounded,
          value: '${user.gems}',
          color: AppColors.neonPurple,
        ),
        const SizedBox(width: 7),
        ListenableBuilder(
          listenable: NotificationInbox.instance,
          builder: (context, _) {
            final unread = NotificationInbox.instance.unreadCount;
            final on =
                userProvider.setting(UserProvider.settingNotifications);
            return GestureDetector(
              onTap: () {
                SoundService.instance.play('ui_click');
                Haptics.tap();
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const NotificationHistoryScreen(),
                  ),
                );
              },
              child: SizedBox(
                width: 36,
                height: 36,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.055),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10)),
                      ),
                      child: Icon(
                        on
                            ? Icons.notifications_rounded
                            : Icons.notifications_off_outlined,
                        color: AppColors.textPrimary,
                        size: 19,
                      ),
                    ),
                    if (unread > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: AppColors.neonPink,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.bgDark,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            unread > 9 ? '9+' : '$unread',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCurrencyPill({
    required IconData icon,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(String heroAsset, UserProvider userProvider) {
    final config = userProvider.config;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF2D1C68), Color(0xFF162D67)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.neonPurple.withValues(alpha: 0.42)),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonPurple.withValues(alpha: 0.20),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned(
              top: -60,
              right: -45,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.neonCyan.withValues(alpha: 0.10),
                ),
              ),
            ),
            Positioned(
              bottom: -55,
              left: -40,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.neonPink.withValues(alpha: 0.09),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 16, 16, 17),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 126,
                    height: 182,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Image.asset(
                        heroAsset,
                        height: 181,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.emoji_events_rounded,
                          color: AppColors.neonGold,
                          size: 78,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.neonCyan.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.neonCyan.withValues(alpha: 0.32),
                            ),
                          ),
                          child: const Text(
                            'DAILY QUIZ',
                            style: TextStyle(
                              color: AppColors.neonCyan,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          '${config.dailyQuestionCount} questions.\nOne brilliant run.',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 20,
                            height: 1.08,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Row(
                          children: [
                            _buildHeroMeta(
                                Icons.timer_outlined, config.dailyDurationLabel),
                            const SizedBox(width: 6),
                            _buildHeroMeta(Icons.card_giftcard_rounded,
                                'up to ${config.dailyMaxCoins} coins'),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: NeonButton(
                            text: userProvider.user.playedTodayDailyQuiz
                                ? 'PLAY AGAIN'
                                : 'START QUIZ',
                            height: 43,
                            borderRadius: 14,
                            icon: const Icon(
                              Icons.bolt_rounded,
                              color: Color(0xFF191126),
                              size: 18,
                            ),
                            gradient: AppColors.goldGradient,
                            glowColor: AppColors.neonGold,
                            onPressed: _startDailyQuiz,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroMeta(IconData icon, String label) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.neonGold, size: 12),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatStrip(UserModel user, UserProvider userProvider) {
    final UserStats stats = userProvider.stats;
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.local_fire_department_rounded,
            value: '${user.dailyStreak}',
            label: S.dashDayStreak,
            color: AppColors.neonGold,
            detail: user.dailyStreak > 0
                ? 'Keep it alive'
                : 'Play today to start',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            icon: Icons.track_changes_rounded,
            value: stats.accuracyLabel,
            label: S.dashAccuracyShort,
            color: AppColors.neonCyan,
            detail: stats.hasData
                ? (userProvider.percentileLabel ??
                    '${stats.totalAnswered} questions answered')
                : 'No quiz played yet',
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
    required String detail,
  }) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      borderRadius: 19,
      borderColor: color.withValues(alpha: 0.24),
      child: Row(
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.13),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _getWeekdayName(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'M';
      case DateTime.tuesday:
        return 'T';
      case DateTime.wednesday:
        return 'W';
      case DateTime.thursday:
        return 'T';
      case DateTime.friday:
        return 'F';
      case DateTime.saturday:
        return 'S';
      case DateTime.sunday:
        return 'S';
      default:
        return '';
    }
  }

  static String _getWeekdayShort(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Mon';
      case DateTime.tuesday:
        return 'Tue';
      case DateTime.wednesday:
        return 'Wed';
      case DateTime.thursday:
        return 'Thu';
      case DateTime.friday:
        return 'Fri';
      case DateTime.saturday:
        return 'Sat';
      case DateTime.sunday:
        return 'Sun';
      default:
        return '';
    }
  }

  Widget _buildStreakCard(UserModel user, UserProvider userProvider) {
    final goal = userProvider.config.streakGoalDays;
    final completed = user.dailyStreak.clamp(0, goal).toInt();
    final remaining = goal - completed;
    final now = DateTime.now();

    DateTime? lastPlayDate;
    if (user.lastStreakDate != null && user.lastStreakDate!.isNotEmpty) {
      try {
        lastPlayDate = DateTime.parse(user.lastStreakDate!);
      } catch (_) {}
    }

    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
      borderColor: AppColors.neonGold.withValues(alpha: 0.28),
      backgroundColor: const Color(0x54291E2D),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.fireGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.neonGold.withValues(alpha: 0.22),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  color: Color(0xFF551F05),
                  size: 26,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.dashStreakTitle,
                      style: const TextStyle(
                        color: AppColors.neonGold,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      remaining <= 0
                          ? 'Streak goal complete — bonus unlocked!'
                          : '$remaining more day${remaining == 1 ? '' : 's'} to unlock the bonus',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$completed/$goal',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: goal == 0 ? 0.0 : completed / goal,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.neonGold),
            ),
          ),
          const SizedBox(height: 11),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(goal, (index) {
              final mondayOfThisWeek = DateTime(now.year, now.month, now.day)
                  .subtract(Duration(days: now.weekday - 1));
              final dayDate = mondayOfThisWeek.add(Duration(days: index));
              final isToday = dayDate.year == now.year &&
                  dayDate.month == now.month &&
                  dayDate.day == now.day;
              final isFuture = dayDate.isAfter(DateTime(now.year, now.month, now.day));

              bool isAttended = false;
              if (!isFuture && lastPlayDate != null && user.dailyStreak > 0) {
                final diff = DateTime(lastPlayDate.year, lastPlayDate.month, lastPlayDate.day)
                    .difference(dayDate)
                    .inDays;
                if (diff >= 0 && diff < user.dailyStreak) {
                  isAttended = true;
                }
              }

              final label = _getWeekdayName(dayDate.weekday);
              final dayShort = _getWeekdayShort(dayDate.weekday);
              final dateStr = '${dayDate.day}/${dayDate.month}';

              return GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      duration: const Duration(seconds: 2),
                      content: Text(
                        isFuture
                            ? '📅 $dayShort ($dateStr): Future Day'
                            : '📅 $dayShort ($dateStr)${isToday ? " Today" : ""}: ${isAttended ? "Attended ✓" : "Missed ❌"}',
                      ),
                      backgroundColor: isAttended
                          ? AppColors.neonGreen
                          : (isFuture ? Colors.white24 : AppColors.neonRed),
                    ),
                  );
                },
                child: Column(
                  children: [
                    Container(
                      width: 27,
                      height: 27,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isAttended
                            ? AppColors.neonGold.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.045),
                        border: Border.all(
                          color: isToday
                              ? AppColors.neonCyan
                              : isAttended
                                  ? AppColors.neonGold.withValues(alpha: 0.75)
                                  : Colors.white.withValues(alpha: 0.10),
                          width: isToday ? 2 : 1,
                        ),
                      ),
                      child: Icon(
                        isAttended ? Icons.check_rounded : Icons.circle_outlined,
                        size: 14,
                        color: isAttended ? AppColors.neonGold : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(
                        color: isToday
                            ? AppColors.neonCyan
                            : (isAttended ? AppColors.neonGold : AppColors.textMuted),
                        fontSize: 9,
                        fontWeight: isToday || isAttended ? FontWeight.w900 : FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String eyebrow,
    required String title,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: const TextStyle(
                  color: AppColors.neonCyan,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.35,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.25,
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionLabel,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 3),
                const Icon(Icons.arrow_forward_rounded, size: 13),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      _QuickAction(S.dashChapters, Icons.menu_book_rounded, AppColors.neonCyan,
          () => _onNavTap(1)),
      _QuickAction(S.dashHistory, Icons.history_rounded, AppColors.neonPurple,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuizHistoryScreen()))),
      _QuickAction(S.dashBattle, Icons.bolt_rounded, AppColors.neonPink,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BattleScreen()))),
      _QuickAction('Online', Icons.people_alt_rounded, const Color(0xFF00B4D8),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OnlineBattleScreen()))),
      _QuickAction(S.dashRewards, Icons.card_giftcard_rounded, AppColors.neonGold,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RewardsScreen()))),
      _QuickAction(S.dashShop, Icons.storefront_rounded, AppColors.neonPurple,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShopScreen()))),
    ];

    return SizedBox(
      height: 116,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final action = actions[index];
          return GlassCard(
            width: 91,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            borderRadius: 19,
            borderColor: action.color.withValues(alpha: 0.26),
            onTap: () {
              SoundService.instance.play('ui_click');
              Haptics.tap();
              action.onTap();
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        action.color.withValues(alpha: 0.28),
                        action.color.withValues(alpha: 0.08),
                      ],
                    ),
                    border: Border.all(color: action.color.withValues(alpha: 0.38)),
                  ),
                  child: Icon(action.icon, color: action.color, size: 23),
                ),
                const SizedBox(height: 8),
                Text(
                  action.title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Yesterday's champion — real data from Hive/Firestore, or an honest
  /// empty state while nobody has been crowned yet.
  Widget _buildChampionCard(UserProvider userProvider) {
    final ChampionModel? champ = userProvider.yesterdayTopChampion;

    if (champ == null) {
      return GlassCard(
        borderRadius: 24,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        borderColor: AppColors.neonGold.withValues(alpha: 0.22),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.neonGold.withValues(alpha: 0.12),
              ),
              child: const Icon(Icons.workspace_premium_rounded,
                  color: AppColors.neonGold, size: 24),
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No champion yet',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    "Yesterday's winner appears here once results are in.",
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final championAvatar =
        champ.avatarPath.isNotEmpty ? champ.avatarPath : AppAssets.maleAvatar;
    final prizeLabel = _championPrizeLabel(champ);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF33240F), Color(0xFF251B33)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.neonGold.withValues(alpha: 0.32)),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonGold.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          height: 186,
          child: Stack(
            children: [
              Positioned(
                right: -22,
                bottom: -44,
                child: Container(
                  width: 175,
                  height: 175,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.neonGold.withValues(alpha: 0.10),
                  ),
                ),
              ),
              Positioned(
                left: 14,
                bottom: -5,
                child: _avatarImage(
                  championAvatar,
                  height: 178,
                  fit: BoxFit.contain,
                  fallbackIcon: Icons.emoji_events_rounded,
                  fallbackSize: 90,
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(148, 17, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.workspace_premium_rounded,
                              color: AppColors.neonGold, size: 17),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "YESTERDAY'S CHAMPION",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.neonGold,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.9,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 13),
                      NameEffectText(
                        champ.name.isNotEmpty ? champ.name : champ.username,
                        effectId: champ.nameEffect,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${champ.score} pts  •  Rank #${champ.rank}',
                        style: const TextStyle(
                          color: AppColors.neonGold,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      if (prizeLabel != null)
                        Row(
                          children: [
                            const Icon(Icons.card_giftcard_rounded,
                                color: AppColors.neonPink, size: 15),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                prizeLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
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
  }

  /// Builds the prize line only from what the backend actually sent.
  String? _championPrizeLabel(ChampionModel champ) {
    final parts = <String>[];
    if (champ.bonusCoins > 0) parts.add('${champ.bonusCoins} coins');
    if (champ.giftName.isNotEmpty) parts.add(champ.giftName);
    return parts.isEmpty ? null : parts.join(' + ');
  }

  /// Live top-4 straight from the Hive-cached leaderboard.
  Widget _buildLeaderboardPreview(UserProvider userProvider) {
    final List<LeaderboardItem> players =
        userProvider.leaderboard.take(4).toList();

    if (players.isEmpty) {
      return GlassCard(
        borderRadius: 22,
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
        borderColor: AppColors.neonCyan.withValues(alpha: 0.18),
        child: Row(
          children: [
            const Icon(Icons.leaderboard_rounded,
                color: AppColors.textMuted, size: 22),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                userProvider.isLoading
                    ? 'Loading today\'s ranking…'
                    : 'No scores today yet — be the first on the board!',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
      borderColor: AppColors.neonCyan.withValues(alpha: 0.22),
      child: Column(
        children: players.map((player) {
          final color = _rankColor(player.rank);
          final avatar = player.avatarPath.isNotEmpty
              ? player.avatarPath
              : AppAssets.maleAvatar;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 25,
                  child: Text(
                    '${player.rank}',
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.18),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _avatarImage(avatar, alignment: Alignment.topCenter),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: NameEffectText(
                    player.name.isNotEmpty ? player.name : player.username,
                    effectId: player.nameEffect,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${player.score} pts',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  static Color _rankColor(int rank) {
    switch (rank) {
      case 1:
        return AppColors.neonGold;
      case 2:
        return const Color(0xFFC7D2E8);
      case 3:
        return const Color(0xFFDC9A67);
      default:
        return AppColors.textSecondary;
    }
  }

  Widget _buildAdminShortcut() {
    return Center(
      child: TextButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
          );
        },
        icon: const Icon(Icons.shield_rounded, size: 15, color: AppColors.textMuted),
        label: const Text(
          'Admin control panel',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 9),
        child: GlassCard(
          borderRadius: 27,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
          borderColor: Colors.white.withValues(alpha: 0.14),
          backgroundColor: const Color(0xB3141A32),
          child: Row(
            children: [
              Expanded(
                child: _buildNavItem(
                  icon: Icons.home_rounded,
                  label: S.navHome,
                  index: 0,
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  icon: Icons.menu_book_rounded,
                  label: S.navExplore,
                  index: 1,
                ),
              ),
              SizedBox(
                width: 66,
                height: 60,
                child: GestureDetector(
                  onTap: _startDailyQuiz,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.goldGradient,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.42)),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.neonGold.withValues(alpha: 0.38),
                          blurRadius: 20,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: Color(0xFF211326),
                      size: 30,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  icon: Icons.emoji_events_rounded,
                  label: S.navRanking,
                  index: 2,
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  icon: Icons.person_rounded,
                  label: S.navProfile,
                  index: 3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final selected = _currentNavIndex == index;
    final color = selected ? AppColors.neonGold : AppColors.textMuted;
    return GestureDetector(
      onTap: () => _onNavTap(index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction(this.title, this.icon, this.color, this.onTap);
}

/// A single-line text that scrolls horizontally (marquee) when it overflows
/// its available width, so long greetings and names stay fully readable on
/// narrow screens instead of being truncated with an ellipsis.
class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final String? effectId;

  const _MarqueeText(
    this.text, {
    required this.style,
    this.effectId,
  });

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// How long one full scroll loop takes.
  static const Duration _scrollDuration = Duration(seconds: 6);

  /// Horizontal gap between the two copies of the text that make the scroll
  /// loop look seamless.
  static const double _gap = 48;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _scrollDuration,
    );
  }

  @override
  void didUpdateWidget(_MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();

        final textWidth = painter.width;
        final textHeight = painter.height;
        final overflow = textWidth > constraints.maxWidth;

        // Drive the animation controller outside of build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (overflow && !_controller.isAnimating) {
            _controller.repeat();
          } else if (!overflow && _controller.isAnimating) {
            _controller.stop();
            _controller.reset();
          }
        });

        if (!overflow) {
          return SizedBox(
            height: textHeight,
            child: NameEffectText(
              widget.text,
              effectId: widget.effectId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: widget.style,
            ),
          );
        }

        return SizedBox(
          height: textHeight,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final dx = -_controller.value * (textWidth + _gap);
                  return Transform.translate(
                    offset: Offset(dx, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        NameEffectText(
                          widget.text,
                          effectId: widget.effectId,
                          maxLines: 1,
                          style: widget.style,
                        ),
                        const SizedBox(width: _gap),
                        NameEffectText(
                          widget.text,
                          effectId: widget.effectId,
                          maxLines: 1,
                          style: widget.style,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}


// ═══════════════════════════════════════════════════════════════════════════
// 🥊 BATTLE ARENA CARD — animated 3D illustration, pure Flutter CustomPaint
// ═══════════════════════════════════════════════════════════════════════════

class _BattleArenaCard extends StatefulWidget {
  const _BattleArenaCard();

  @override
  State<_BattleArenaCard> createState() => _BattleArenaCardState();
}

class _BattleArenaCardState extends State<_BattleArenaCard>
    with TickerProviderStateMixin {
  // floating / bob animation for the two fighters
  late final AnimationController _floatCtrl;
  // lightning bolt flash
  late final AnimationController _flashCtrl;
  // VS pulse
  late final AnimationController _vsCtrl;
  // overall entrance
  late final AnimationController _enterCtrl;

  late final Animation<double> _floatAnim;
  late final Animation<double> _flashAnim;
  late final Animation<double> _vsAnim;
  late final Animation<double> _enterAnim;

  @override
  void initState() {
    super.initState();

    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _vsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();

    _floatAnim = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );
    _flashAnim = CurvedAnimation(parent: _flashCtrl, curve: Curves.easeInOut);
    _vsAnim = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _vsCtrl, curve: Curves.easeInOut),
    );
    _enterAnim = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _flashCtrl.dispose();
    _vsCtrl.dispose();
    _enterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _enterAnim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(_enterAnim),
        child: GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BattleScreen()),
          ),
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                colors: [Color(0xFF1A0A3D), Color(0xFF0D1F4D), Color(0xFF1A0A2E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: AppColors.neonPurple.withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.neonPurple.withValues(alpha: 0.3),
                  blurRadius: 32,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: AppColors.neonPink.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(
                children: [
                  // ── Animated background stars / sparks ──
                  AnimatedBuilder(
                    animation: _flashAnim,
                    builder: (_, __) => CustomPaint(
                      size: const Size(double.infinity, 200),
                      painter: _ArenaBgPainter(progress: _flashAnim.value),
                    ),
                  ),

                  // ── Left fighter (blue) — floats up/down ──
                  AnimatedBuilder(
                    animation: _floatAnim,
                    builder: (_, __) => Positioned(
                      left: 0,
                      bottom: 28 + _floatAnim.value,
                      child: const _FighterImage(
                        asset: AppAssets.battleFighterBlue,
                        glowColor: AppColors.neonCyan,
                        label: 'YOU',
                        flip: false,
                      ),
                    ),
                  ),

                  // ── Right fighter (pink) — floats opposite phase ──
                  AnimatedBuilder(
                    animation: _floatAnim,
                    builder: (_, __) => Positioned(
                      right: 0,
                      bottom: 28 - _floatAnim.value,
                      child: const _FighterImage(
                        asset: AppAssets.battleFighterPink,
                        glowColor: AppColors.neonPink,
                        label: 'BOT',
                        flip: true,
                      ),
                    ),
                  ),

                  // ── Centre VS badge ──
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.center,
                      child: ScaleTransition(
                        scale: _vsAnim,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Lightning bolt
                            AnimatedBuilder(
                              animation: _flashAnim,
                              builder: (_, __) => CustomPaint(
                                size: const Size(36, 44),
                                painter: _LightningPainter(
                                  progress: _flashAnim.value,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: const LinearGradient(
                                  colors: [
                                    AppColors.neonGold,
                                    Color(0xFFFF8C3C),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.neonGold.withValues(alpha: 0.7),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Text(
                                'VS',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF1A1030),
                                  fontStyle: FontStyle.italic,
                                  letterSpacing: 2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── Bottom CTA bar ──
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            AppColors.neonPurple.withValues(alpha: 0.35),
                          ],
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '⚔️ BATTLE ARENA',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Bot • Online Players • 1v1',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // ── ONLINE button ──
                                GestureDetector(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const OnlineBattleScreen()),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF00B4D8), Color(0xFF0077B6)],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF00B4D8).withValues(alpha: 0.4),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.wifi_rounded,
                                            color: Colors.white, size: 11),
                                        SizedBox(width: 3),
                                        Text(
                                          'ONLINE',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // ── FIGHT button (existing) ──
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    gradient: const LinearGradient(
                                      colors: [AppColors.neonPink, AppColors.neonPurple],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.neonPink.withValues(alpha: 0.4),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'FIGHT',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                      SizedBox(width: 3),
                                      Icon(Icons.bolt_rounded,
                                          color: Colors.white, size: 12),
                                    ],
                                  ),
                                ),
                              ],
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
        ),
      ),
    );
  }
}

// ── Real 3D fighter image with glow + label ────────────────────────────────

class _FighterImage extends StatelessWidget {
  final String asset;
  final Color glowColor;
  final String label;
  final bool flip;

  const _FighterImage({
    required this.asset,
    required this.glowColor,
    required this.label,
    required this.flip,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // glow halo behind image
        Container(
          width: 110,
          height: 118,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: glowColor.withValues(alpha: 0.45),
                blurRadius: 32,
                spreadRadius: 8,
              ),
            ],
          ),
          child: Transform(
            alignment: Alignment.center,
            transform: flip
                ? (Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0))
                : Matrix4.identity(),
            child: Image.asset(
              asset,
              width: 110,
              height: 118,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                Icons.person_rounded,
                color: glowColor,
                size: 60,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: glowColor.withValues(alpha: 0.18),
            border: Border.all(color: glowColor.withValues(alpha: 0.6)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: glowColor,
              letterSpacing: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Animated lightning bolt ────────────────────────────────────────────────

class _LightningPainter extends CustomPainter {
  final double progress;

  _LightningPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // animated glow intensity
    final glow = (0.5 + 0.5 * math.sin(progress * 2 * math.pi));
    final boltColor = Color.lerp(
      AppColors.neonGold,
      Colors.white,
      glow * 0.5,
    )!;

    final glowPaint = Paint()
      ..color = boltColor.withValues(alpha: 0.4 * glow)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final boltPaint = Paint()
      ..color = boltColor
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // lightning zigzag path
    final path = Path()
      ..moveTo(w * 0.58, 0)
      ..lineTo(w * 0.32, h * 0.44)
      ..lineTo(w * 0.52, h * 0.44)
      ..lineTo(w * 0.26, h)
      ..lineTo(w * 0.55, h * 0.58)
      ..lineTo(w * 0.38, h * 0.58)
      ..close();

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, boltPaint);

    // inner white core
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7 * glow)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_LightningPainter old) => old.progress != progress;
}

// ── Arena background — sparks + orbit rings ────────────────────────────────

class _ArenaBgPainter extends CustomPainter {
  final double progress;

  _ArenaBgPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // Orbiting rings around VS centre
    for (var r = 0; r < 3; r++) {
      final radius = 38.0 + r * 26;
      final alpha = (0.06 - r * 0.015).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(cx, cy - 10),
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = AppColors.neonPurple.withValues(alpha: alpha),
      );
    }

    // Rotating dot on outermost ring
    final angle = progress * 2 * math.pi;
    final dotX = cx + 90 * math.cos(angle);
    final dotY = (cy - 10) + 90 * math.sin(angle);
    canvas.drawCircle(
      Offset(dotX, dotY),
      3,
      Paint()..color = AppColors.neonCyan.withValues(alpha: 0.5),
    );

    // Sparks (small random static stars)
    final rng = math.Random(42);
    for (var i = 0; i < 18; i++) {
      final sx = rng.nextDouble() * w;
      final sy = rng.nextDouble() * h;
      final twinkle = (math.sin(progress * 2 * math.pi + i * 1.3) + 1) / 2;
      final sparkColor = i % 2 == 0 ? AppColors.neonGold : AppColors.neonCyan;
      canvas.drawCircle(
        Offset(sx, sy),
        1.2 + twinkle * 1.5,
        Paint()..color = sparkColor.withValues(alpha: 0.15 + twinkle * 0.3),
      );
    }
  }

  @override
  bool shouldRepaint(_ArenaBgPainter old) => old.progress != progress;
}
