import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_assets.dart';
import '../../../data/providers/user_provider.dart';
import '../../../data/models/champion_model.dart';
import '../../../data/models/leaderboard_model.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/name_effect_text.dart';
import '../../widgets/cached_avatar.dart';
import '../../../l10n/app_strings.dart';

/// A clean, standard leaderboard: compact header, static top-3 podium with
/// medals, numbered rank rows and a "your position" card at the bottom.
/// No pulse / scale animations — everything is calm, readable and compact.
class LeaderboardScreen extends StatefulWidget {
  final int initialTabIndex;

  const LeaderboardScreen({super.key, this.initialTabIndex = 0});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<_ConfettiParticle> _confetti = [];
  final math.Random _random = math.Random();

  // Medal emojis for the classic leaderboard look.
  static const Map<int, String> _medals = {
    1: '🥇',
    2: '🥈',
    3: '🥉',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _generateConfetti();
  }

  void _generateConfetti() {
    for (int i = 0; i < 18; i++) {
      _confetti.add(_ConfettiParticle(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        color: [
          AppColors.neonGold,
          AppColors.neonOrange,
          AppColors.neonCyan,
          AppColors.neonPurple,
          AppColors.neonPink,
        ][_random.nextInt(5)],
        size: _random.nextDouble() * 5 + 2.5,
        speed: 0,
      ));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _isNetworkAvatar(String avatar) =>
      avatar.startsWith('http://') || avatar.startsWith('https://');

  Widget _leaderboardAvatar(String avatar, double size, {Color? borderColor}) {
    final safeAvatar = avatar.isNotEmpty ? avatar : AppAssets.maleAvatar;
    final image = _isNetworkAvatar(safeAvatar)
        ? CachedAvatar(
            url: safeAvatar,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.72),
            fallbackIcon: Icons.person_rounded,
            fallbackIconColor: Colors.white,
          )
        : Image.asset(
            safeAvatar,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.72),
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.person_rounded, color: Colors.white),
          );

    return Container(
      width: size,
      height: size,
      padding:
          borderColor != null ? EdgeInsets.all(borderColor == AppColors.neonGold ? 3 : 2) : null,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: borderColor != null
            ? Border.all(color: borderColor, width: borderColor == AppColors.neonGold ? 3 : 2)
            : null,
        gradient: borderColor == AppColors.neonGold
            ? const LinearGradient(colors: [AppColors.neonGold, AppColors.neonOrange])
            : null,
        boxShadow: borderColor != null
            ? [
                BoxShadow(
                  color: borderColor.withValues(alpha: 0.5),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: image,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final leaderboard = userProvider.leaderboard;
    final champions = userProvider.champions;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          S.lbTitle,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.neonGold,
          indicatorWeight: 2,
          labelColor: AppColors.neonGold,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          tabs: const [
            Tab(text: 'LIVE TODAY'),
            Tab(text: 'WINNERS 🏆'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTodayLeaderboardTab(leaderboard, userProvider),
          _buildWinnersHistoryTab(champions),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TODAY'S LIVE TAB
  // ---------------------------------------------------------------------------

  Widget _buildTodayLeaderboardTab(
      List<LeaderboardItem> list, UserProvider userProvider) {
    if (list.isEmpty) {
      return RefreshIndicator(
        color: AppColors.neonCyan,
        onRefresh: () => userProvider.refreshRankings(force: true),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 70),
            _buildEmptyState(
              icon: Icons.leaderboard_rounded,
              title: userProvider.isLoading
                  ? 'Loading today\'s ranking…'
                  : S.lbNoScoresToday,
              message: userProvider.isLoading ? S.lbFetching : S.lbNoScoresBody,
            ),
          ],
        ),
      );
    }

    final top3 = list.take(3).toList();
    final rest = list.skip(3).toList();

    return RefreshIndicator(
      color: AppColors.neonCyan,
      onRefresh: () => userProvider.refreshRankings(force: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Stack(
          children: [
            // Subtle static confetti background
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ConfettiPainter(particles: _confetti),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                children: [
                  // Compact header
                  _buildLeaderboardHeader(list.length),
                  const SizedBox(height: 12),

                  // Top 3 podium (static, compact)
                  _buildPodiumView(top3),
                  const SizedBox(height: 14),

                  // Rest of the ranks
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: rest.length,
                    itemBuilder: (context, index) {
                      final item = rest[index];
                      return _buildRankTile(item, index + 4);
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildYourPositionCard(userProvider),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderboardHeader(int totalPlayers) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.neonGold.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.neonGold.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: const BoxDecoration(
              gradient: AppColors.goldGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "TODAY'S LIVE RANKING",
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.neonGold,
                    letterSpacing: 0.6,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  'Top players competing right now',
                  style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.people_alt_rounded, size: 12, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '$totalPlayers',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TOP 3 PODIUM (static, compact)
  // ---------------------------------------------------------------------------

  Widget _buildPodiumView(List<LeaderboardItem> top3) {
    return GlassCard(
      borderRadius: 18,
      borderColor: AppColors.neonGold.withValues(alpha: 0.25),
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (top3.length > 1)
            _buildPodiumColumn(top3[1], 2, 54, const Color(0xFFBFC9DA)),
          if (top3.isNotEmpty)
            _buildPodiumColumn(top3[0], 1, 74, AppColors.neonGold),
          if (top3.length > 2)
            _buildPodiumColumn(top3[2], 3, 42, const Color(0xFFCD7F32)),
        ],
      ),
    );
  }

  Widget _buildPodiumColumn(
      LeaderboardItem item, int rank, double standHeight, Color color) {
    final isFirst = rank == 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Medal
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [color, color.withValues(alpha: 0.65)],
            ),
          ),
          child: Text(
            _medals[rank] ?? '#$rank',
            style: const TextStyle(fontSize: 16),
          ),
        ),
        const SizedBox(height: 5),

        // Avatar
        _leaderboardAvatar(
          item.avatarPath.isNotEmpty ? item.avatarPath : AppAssets.heroBoy,
          isFirst ? 50 : 42,
        ),
        const SizedBox(height: 5),

        // Name
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 78),
          child: Text(
            (item.name.isNotEmpty ? item.name : item.username).split(' ').first,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isFirst ? 12 : 10.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Score
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.stars_rounded, size: 11, color: color),
            const SizedBox(width: 2),
            Text(
              '${item.score}',
              style: TextStyle(
                fontSize: isFirst ? 13 : 11.5,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),

        // Podium stand
        Container(
          width: 70,
          height: standHeight,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.32),
                color.withValues(alpha: 0.12),
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            border: Border.all(color: color.withValues(alpha: 0.55), width: 1.4),
          ),
          child: Center(
            child: Text(
              '#$rank',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // YOUR POSITION (compact, static)
  // ---------------------------------------------------------------------------

  Widget _buildYourPositionCard(UserProvider userProvider) {
    if (!userProvider.hasPlayedDailyQuiz) {
      return GlassCard(
        borderRadius: 14,
        borderColor: Colors.white12,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                gradient: AppColors.goldGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'JOIN THE RACE!',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: AppColors.neonGold,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Play today\'s Daily Quiz to appear here! 🎯',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final rank = userProvider.playerRank ?? 1;
    final isTop3 = rank <= 3;
    final user = userProvider.user;

    return GlassCard(
      borderRadius: 14,
      borderColor: isTop3
          ? AppColors.neonGold.withValues(alpha: 0.55)
          : AppColors.neonCyan.withValues(alpha: 0.35),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          // Rank chip
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isTop3 ? AppColors.goldGradient : null,
              color: isTop3 ? null : Colors.white10,
              border: isTop3 ? null : Border.all(color: AppColors.neonCyan, width: 1.5),
            ),
            child: Text(
              isTop3 ? (_medals[rank] ?? '#$rank') : '$rank',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: isTop3 ? Colors.black : AppColors.neonCyan,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _leaderboardAvatar(user.effectiveAvatar, 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: NameEffectText(
                        user.fullName,
                        effectId: user.nameEffect,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: AppColors.cyanGradient,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        S.you,
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  isTop3 ? 'Amazing! You\'re on the podium! 🏆' : 'Keep going — you\'re doing great!',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: isTop3 ? AppColors.neonGold : AppColors.neonGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${userProvider.todayCountedScore > 0 ? userProvider.todayCountedScore : userProvider.bestDailyScore}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.neonGold,
                ),
              ),
              const Text(
                'pts',
                style: TextStyle(fontSize: 9, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // RANK ROWS (4th place onwards)
  // ---------------------------------------------------------------------------

  Widget _buildRankTile(LeaderboardItem item, int rank) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        borderRadius: 14,
        borderColor: Colors.white.withValues(alpha: 0.08),
        child: Row(
          children: [
            // Rank number
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$rank',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 10),

            _leaderboardAvatar(
              item.avatarPath.isNotEmpty ? item.avatarPath : AppAssets.maleAvatar,
              32,
            ),
            const SizedBox(width: 10),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NameEffectText(
                    item.name.isNotEmpty ? item.name : item.username,
                    effectId: item.nameEffect,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.speed_rounded, size: 11, color: AppColors.textMuted),
                      const SizedBox(width: 3),
                      Text(
                        '${item.timeSeconds}s',
                        style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Score chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.neonGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.neonGold.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.stars_rounded, size: 12, color: AppColors.neonGold),
                  const SizedBox(width: 3),
                  Text(
                    '${item.score}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: AppColors.neonGold,
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

  // ---------------------------------------------------------------------------
  // EMPTY STATE
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.neonGold.withValues(alpha: 0.18),
                Colors.transparent,
              ],
            ),
          ),
          child: Icon(icon, size: 42, color: AppColors.neonGold),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // YESTERDAY'S WINNERS TAB
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // DAILY WINNERS HISTORY (date + winner names)
  // ---------------------------------------------------------------------------

  Widget _buildWinnersHistoryTab(List<ChampionModel> champions) {
    if (champions.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 70),
          _buildEmptyState(
            icon: Icons.emoji_events_rounded,
            title: S.lbNoChampions,
            message: 'Daily quiz winners and their prizes will show up here '
                'day by day once the results are declared.',
          ),
        ],
      );
    }

    // Group winners by their day (newest day first, ranks inside each day).
    final byKey = <String, List<ChampionModel>>{};
    for (final c in champions) {
      final key = c.dateKey.isNotEmpty ? c.dateKey : '_recent_';
      byKey.putIfAbsent(key, () => []).add(c);
    }
    final keys = byKey.keys.toList()
      ..sort((a, b) => a == '_recent_'
          ? 1
          : b == '_recent_'
              ? -1
              : b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      itemCount: keys.length,
      itemBuilder: (context, index) {
        final key = keys[index];
        return _buildHistoryDayCard(key, byKey[key]!);
      },
    );
  }

  Widget _buildHistoryDayCard(String key, List<ChampionModel> winners) {
    final isYesterday = key == _dateKey(DateTime.now().subtract(const Duration(days: 1)));
    final isToday = key == _dateKey(DateTime.now());

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        borderRadius: 16,
        borderColor: isYesterday || isToday
            ? AppColors.neonGold.withValues(alpha: 0.4)
            : Colors.white12,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- Date header ----
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.neonGold.withValues(alpha: 0.16),
                  ),
                  child: const Icon(Icons.calendar_month_rounded,
                      size: 14, color: AppColors.neonGold),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _formatDate(key),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: AppColors.neonGold,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${winners.length} winner${winners.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ---- Winners for this day ----
            ...winners.take(5).map((c) => _buildWinnerRow(c)),
            if (winners.length > 5)
              Padding(
                padding: const EdgeInsets.only(left: 34, top: 2),
                child: Text(
                  '+ ${winners.length - 5} more…',
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWinnerRow(ChampionModel champ) {
    final isFirst = champ.rank == 1;
    final rank = champ.rank > 0 ? champ.rank : 0;
    const medals = {1: '🥇', 2: '🥈', 3: '🥉'};

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // Rank / medal
          SizedBox(
            width: 26,
            height: 26,
            child: Center(
              child: medals.containsKey(rank)
                  ? Text(medals[rank]!, style: const TextStyle(fontSize: 14))
                  : Text(
                      rank > 0 ? '$rank' : '·',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textSecondary,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 6),

          _leaderboardAvatar(
            champ.avatarPath.isNotEmpty ? champ.avatarPath : AppAssets.maleAvatar,
            30,
          ),
          const SizedBox(width: 9),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  champ.name.isNotEmpty ? champ.name : champ.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: isFirst ? AppColors.neonGold : Colors.white,
                  ),
                ),
                if (champ.giftName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.card_giftcard,
                            size: 10, color: AppColors.neonPink),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            champ.giftName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.neonPink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Score
          Text(
            '${champ.score}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: AppColors.neonGold,
            ),
          ),
          const SizedBox(width: 3),
          const Icon(Icons.stars_rounded, size: 12, color: AppColors.neonGold),
        ],
      ),
    );
  }

  /// Formats a `yyyy-MM-dd` key into a friendly label
  /// (e.g. "Yesterday • 27 Aug" or "15 Aug, 2026").
  String _formatDate(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return 'Recent';
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return key;

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final label = '${months[month - 1]} $day';
    final now = DateTime.now();
    if (key == _dateKey(now)) return 'Today • $label';
    if (key == _dateKey(now.subtract(const Duration(days: 1)))) {
      return 'Yesterday • $label';
    }
    return '$label, $year';
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// Confetti particle class (static, subtle)
class _ConfettiParticle {
  double x;
  double y;
  final Color color;
  final double size;
  final double speed;

  _ConfettiParticle({
    required this.x,
    required this.y,
    required this.color,
    required this.size,
    required this.speed,
  });
}

// Confetti painter
class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;

  _ConfettiPainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final paint = Paint()
        ..color = particle.color.withValues(alpha: 0.14)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(particle.x * size.width, particle.y * size.height),
        particle.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
