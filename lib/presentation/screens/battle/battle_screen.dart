import 'dart:async';
import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/question_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/providers/battle_provider.dart';
import '../../../data/providers/user_provider.dart';
import '../../../l10n/app_strings.dart';
import '../../widgets/cached_avatar.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/neon_button.dart';
import '../../widgets/quiz_language_pills.dart';

class BattleScreen extends StatelessWidget {
  const BattleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final battle = context.watch<BattleProvider>();

    return PopScope(
      // Always intercept back — we handle it ourselves
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _onBackPressed(context, battle);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            S.battleArena,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => _onBackPressed(context, battle),
          ),
          actions: [
            if (battle.phase == BattlePhase.question ||
                battle.phase == BattlePhase.reveal)
              QuizLanguagePills(
                available: battle.availableLanguages,
                selected: battle.displayLanguage,
                onSelected: battle.setDisplayLanguage,
              ),
          ],
        ),
        body: switch (battle.phase) {
          BattlePhase.setup => Column(
              children: [
                // A live match that could not be established says so here
                // instead of silently dropping the player back on the setup
                // screen (R10/R17).
                if (battle.startError != null ||
                    battle.matchmakingError != null)
                  _BattleNoticeBanner(
                    message: battle.startError ?? battle.matchmakingError!,
                    onDismiss: battle.clearStartError,
                  ),
                const Expanded(child: _SetupView()),
              ],
            ),
          BattlePhase.searching => const _SearchingView(),
          BattlePhase.found => const _VsIntroView(),
          BattlePhase.countdown => _CountdownView(
              countdownValue: battle.countdownValue,
            ),
          BattlePhase.question || BattlePhase.reveal => const _ArenaView(),
          BattlePhase.finished => const _ResultView(),
        },
      ),
    );
  }

  Future<void> _onBackPressed(BuildContext context, BattleProvider battle) async {
    // Setup বা finished phase-এ সরাসরি বের হয়ে যাও
    if (battle.phase == BattlePhase.setup ||
        battle.phase == BattlePhase.finished) {
      if (context.mounted) Navigator.of(context).pop();
      return;
    }

    // Searching-এ cancel করে বের হও
    if (battle.phase == BattlePhase.searching) {
      battle.cancelSearch();
      if (context.mounted) Navigator.of(context).pop();
      return;
    }

    // Live match চলছে — confirm dialog দেখাও
    if (battle.isLive &&
        (battle.phase == BattlePhase.question ||
            battle.phase == BattlePhase.reveal ||
            battle.phase == BattlePhase.found ||
            battle.phase == BattlePhase.countdown)) {
      final confirm = await _showForfeitDialog(context);
      if (confirm == true && context.mounted) {
        battle.forfeitAndLeave();
        Navigator.of(context).pop();
      }
      return;
    }

    // Bot match চলছে — confirm dialog
    final confirm = await _showQuitDialog(context);
    if (confirm == true && context.mounted) {
      battle.quitMatch();
      Navigator.of(context).pop();
    }
  }

  Future<bool?> _showForfeitDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B2646),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '🏳️ Forfeit Match?',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        content: const Text(
          'Your opponent will be declared the winner.\nAre you sure you want to leave?',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Stay',
              style: TextStyle(
                color: AppColors.neonCyan,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Forfeit',
              style: TextStyle(
                color: AppColors.neonRed,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showQuitDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B2646),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '🚪 Quit Match?',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        content: const Text(
          'Your progress will be lost.\nAre you sure?',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Continue',
              style: TextStyle(
                color: AppColors.neonCyan,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Quit',
              style: TextStyle(
                color: AppColors.neonRed,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Setup ----

class _SetupView extends StatefulWidget {
  const _SetupView();

  @override
  State<_SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends State<_SetupView>
    with SingleTickerProviderStateMixin {
  BattleDifficulty _selected = BattleDifficulty.normal;
  late final AnimationController _enterCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    
    // Reset battle state if previous game was finished
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final battle = context.read<BattleProvider>();
      if (battle.phase == BattlePhase.finished) {
        battle.resetBattle();
      }
    });
    
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final battle = context.read<BattleProvider>();

    if (battle.hasNoQuestions) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '😔 No questions available yet. Check back soon!',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Image.asset(
              AppAssets.battleDuo,
              height: 130,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Image.asset(
                AppAssets.battleSwords,
                height: 84,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚔️ BATTLE ARENA',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              S.battleRulesLine(n: battle.battleQuestionCount),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              '⚡ ${battle.battleQuestionCount} questions • '
              '✅ Correct +${battle.battleBasePoints} • '
              '⚡ Speed up to +${battle.battleSpeedBonus} • '
              '🥇 First +${battle.battleFirstBonus} • '
              '🔥 Streak +${battle.battleStreakBonus}×n',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.neonGold,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              S.battleChooseDifficulty,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            _difficultyCard(
              context,
              BattleDifficulty.easy,
              S.battleEasy,
              S.battleEasyDesc,
              AppColors.neonGreen,
            ),
            _difficultyCard(
              context,
              BattleDifficulty.normal,
              S.battleNormal,
              S.battleNormalDesc,
              AppColors.neonCyan,
            ),
            _difficultyCard(
              context,
              BattleDifficulty.hard,
              S.battleHard,
              S.battleHardDesc,
              AppColors.neonRed,
            ),
            const SizedBox(height: 20),
            NeonButton(
              text: S.battleStartFinding,
              onPressed: () => context.read<BattleProvider>().startBattle(_selected),
            ),
          ],
        ),
      ),
    );
  }

  Widget _difficultyCard(
    BuildContext context,
    BattleDifficulty diff,
    String title,
    String desc,
    Color accent,
  ) {
    final selected = _selected == diff;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => setState(() => _selected = diff),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? accent : Colors.white12,
              width: selected ? 1.8 : 1.0,
            ),
            color: selected
                ? accent.withValues(alpha: 0.12)
                : AppColors.bgCardGlass,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.25),
                      blurRadius: 16,
                      spreadRadius: 1,
                    )
                  ]
                : [],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    key: ValueKey(selected),
                    color: selected ? accent : AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        desc,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- Searching ---

/// Matchmaking radar — shown while looking for a real opponent.
class _SearchingView extends StatefulWidget {
  const _SearchingView();

  @override
  State<_SearchingView> createState() => _SearchingViewState();
}

// BUG FIX: was SingleTickerProviderStateMixin but had 2 AnimationControllers → crash.
// Fixed to TickerProviderStateMixin which supports multiple controllers.
class _SearchingViewState extends State<_SearchingView>
    with TickerProviderStateMixin {
  late final AnimationController _radar;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _radar = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _radar.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final battle = context.watch<BattleProvider>();
    final user = context.watch<UserProvider>().user;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 230,
          height: 230,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Radar rings
              AnimatedBuilder(
                animation: _radar,
                builder: (_, __) => CustomPaint(
                  size: const Size(230, 230),
                  painter: _RadarPainter(progress: _radar.value),
                ),
              ),
              // My avatar, breathing
              ScaleTransition(
                scale: Tween(begin: 0.94, end: 1.06).animate(
                  CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                ),
                child: _AvatarCircle(asset: user.effectiveAvatar, size: 64),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          S.battleSearching,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          S.battleSearchingHint,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Text(
          '${battle.difficulty.name.toUpperCase()} • '
          '${S.battleRulesLine(n: battle.battleQuestionCount)}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.neonGold,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: 220,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: battle.searchSecondsTotal == 0
                  ? 0
                  : 1 -
                      battle.searchSecondsRemaining /
                          battle.searchSecondsTotal,
              minHeight: 6,
              backgroundColor: Colors.white10,
              color: AppColors.neonCyan,
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.neonRed),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () => context.read<BattleProvider>().cancelSearch(),
          child: Text(
            S.battleCancelSearch,
            style: const TextStyle(color: AppColors.neonRed),
          ),
        ),
      ],
    );
  }
}

/// Sweeping radar beam + fading rings.
class _RadarPainter extends CustomPainter {
  final double progress;

  _RadarPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    // Static faint rings
    for (var i = 1; i <= 3; i++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AppColors.neonCyan.withValues(alpha: 0.18 - i * 0.04);
      canvas.drawCircle(center, maxR * i / 3, paint);
    }

    // Sweeping beam
    final beamPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * pi,
        colors: [
          AppColors.neonCyan.withValues(alpha: 0.0),
          AppColors.neonCyan.withValues(alpha: 0.45),
          AppColors.neonCyan.withValues(alpha: 0.0),
        ],
        stops: const [0.82, 0.97, 1.0],
        transform: GradientRotation(progress * 2 * pi),
      ).createShader(Rect.fromCircle(center: center, radius: maxR));
    canvas.drawCircle(center, maxR, beamPaint);

    // Leading dot on the beam
    final dotAngle = progress * 2 * pi;
    final dotPos = center +
        Offset(cos(dotAngle), sin(dotAngle)) * (maxR * 0.82);
    canvas.drawCircle(
      dotPos,
      3.5,
      Paint()..color = AppColors.neonCyan,
    );
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ---------------------------------------------------------------- VS intro ---

/// Cricket-league style VS splash: two cards slide in, "VS" slams in the
/// middle. Live matches get confetti + a LIVE badge.
class _VsIntroView extends StatefulWidget {
  const _VsIntroView();

  @override
  State<_VsIntroView> createState() => _VsIntroViewState();
}

class _VsIntroViewState extends State<_VsIntroView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;
  late final ConfettiController _confetti;
  bool _confettiFired = false;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    _intro.dispose();
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final battle = context.watch<BattleProvider>();
    final user = context.watch<UserProvider>().user;

    if (battle.isLive && !_confettiFired) {
      _confettiFired = true;
      Future.delayed(const Duration(milliseconds: 550), () {
        if (mounted) _confetti.play();
      });
    }

    final leftSlide = Tween<Offset>(
      begin: const Offset(-1.4, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutBack),
      ),
    );
    final rightSlide = Tween<Offset>(
      begin: const Offset(1.4, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.05, 0.5, curve: Curves.easeOutBack),
      ),
    );
    final vsScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.4, 0.72, curve: Curves.elasticOut),
      ),
    );
    final badgeFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        // Confetti behind everything (live matches only)
        if (battle.isLive)
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              emissionFrequency: 0.06,
              numberOfParticles: 14,
              gravity: 0.18,
              colors: const [
                AppColors.neonGold,
                AppColors.neonCyan,
                AppColors.neonPink,
                AppColors.neonGreen,
              ],
            ),
          ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SlideTransition(
                      position: leftSlide,
                      child: _VsPlayerCard(
                        name: S.you,
                        avatar: user.effectiveAvatar,
                        accent: AppColors.neonCyan,
                      ),
                    ),
                  ),
                  ScaleTransition(
                    scale: vsScale,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: const LinearGradient(
                          colors: [AppColors.neonGold, Color(0xFFFF8E3C)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.neonGold.withValues(alpha: 0.55),
                            blurRadius: 30,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Text(
                        'VS',
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1A1030),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SlideTransition(
                      position: rightSlide,
                      child: _VsPlayerCard(
                        name: battle.opponentName,
                        avatar: battle.opponentAvatar,
                        accent: AppColors.neonPink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 34),
              FadeTransition(
                opacity: badgeFade,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: battle.isLive
                          ? AppColors.neonGreen
                          : AppColors.neonPink,
                    ),
                    color: (battle.isLive
                            ? AppColors.neonGreen
                            : AppColors.neonPink)
                        .withValues(alpha: 0.12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (battle.isLive)
                        const SizedBox(
                          width: 9,
                          height: 9,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.neonGreen,
                            ),
                          ),
                        ),
                      if (battle.isLive) const SizedBox(width: 8),
                      Text(
                        battle.isLive
                            ? S.battleLiveMatch
                            : S.battleBotMatch,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          color: battle.isLive
                              ? AppColors.neonGreen
                              : AppColors.neonPink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FadeTransition(
                opacity: badgeFade,
                child: Text(
                  S.battleFoundHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VsPlayerCard extends StatelessWidget {
  final String name;
  final String avatar;
  final Color accent;

  const _VsPlayerCard({
    required this.name,
    required this.avatar,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 92,
          height: 92,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [accent, accent.withValues(alpha: 0.4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.4),
                blurRadius: 22,
              ),
            ],
          ),
          child: ClipOval(
            child: _NetworkAwareAvatar(avatar: avatar),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

// Builds avatars for local assets or https URLs.
class _NetworkAwareAvatar extends StatelessWidget {
  final String avatar;

  const _NetworkAwareAvatar({required this.avatar});

  @override
  Widget build(BuildContext context) {
    if (avatar.startsWith('http://') || avatar.startsWith('https://')) {
      return CachedAvatar(
        url: avatar,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        fallbackIcon: Icons.person_rounded,
        fallbackIconColor: Colors.white,
        fallbackIconSize: 34,
      );
    }
    return Image.asset(
      avatar,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      errorBuilder: (_, __, ___) => const Icon(
        Icons.person_rounded,
        color: Colors.white,
        size: 34,
      ),
    );
  }
}

class _AvatarCircle extends StatelessWidget {
  final String asset;
  final double size;

  const _AvatarCircle({required this.asset, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.primaryGradient,
      ),
      child: ClipOval(child: _NetworkAwareAvatar(avatar: asset)),
    );
  }
}

// --------------------------------------------------------------- Countdown ---

/// IMPROVED: Countdown number now bounces in with scale + fade on each tick.
class _CountdownView extends StatefulWidget {
  final int countdownValue;

  const _CountdownView({required this.countdownValue});

  @override
  State<_CountdownView> createState() => _CountdownViewState();
}

class _CountdownViewState extends State<_CountdownView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceCtrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _scaleAnim = Tween<double>(begin: 1.6, end: 1.0).animate(
      CurvedAnimation(parent: _bounceCtrl, curve: Curves.elasticOut),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _bounceCtrl,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );
    _bounceCtrl.forward();
  }

  @override
  void didUpdateWidget(_CountdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.countdownValue != widget.countdownValue) {
      _bounceCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final battle = context.watch<BattleProvider>();
    final user = context.watch<UserProvider>().user;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _VsPlayerCard(
                name: S.you,
                avatar: user.effectiveAvatar,
                accent: AppColors.neonCyan,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  'VS',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: AppColors.neonGold,
                  ),
                ),
              ),
              _VsPlayerCard(
                name: battle.opponentName,
                avatar: battle.opponentAvatar,
                accent: AppColors.neonPink,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            battle.isLive
                ? '🔴 ${S.battleLiveMatch}'
                : '🤖 ${S.battleBotMatch}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          // Bounce + fade animation on each countdown tick
          AnimatedBuilder(
            animation: _bounceCtrl,
            builder: (_, __) => FadeTransition(
              opacity: _fadeAnim,
              child: ScaleTransition(
                scale: _scaleAnim,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [
                        Color(0x44FFC857),
                        Color(0x00FFC857),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.neonGold.withValues(alpha: 0.4),
                        blurRadius: 40,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '${widget.countdownValue}',
                      style: const TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                        color: AppColors.neonGold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            S.battleGetReady,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Arena ---

/// Arena view: compact scoreboard pinned at top, question + options below.
/// Converted to StatefulWidget to support per-question slide-in animation.
class _ArenaView extends StatefulWidget {
  const _ArenaView();

  @override
  State<_ArenaView> createState() => _ArenaViewState();
}

class _ArenaViewState extends State<_ArenaView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _qCtrl;
  late final Animation<Offset> _qSlide;
  late final Animation<double> _qFade;
  int _lastIndex = -1;

  @override
  void initState() {
    super.initState();
    _qCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _qSlide = Tween<Offset>(
      begin: const Offset(0.08, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _qCtrl, curve: Curves.easeOutCubic));
    _qFade = CurvedAnimation(parent: _qCtrl, curve: Curves.easeOut);
    _qCtrl.forward();
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  void _animateIfNewQuestion(int index) {
    if (index != _lastIndex) {
      _lastIndex = index;
      _qCtrl.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final battle = context.watch<BattleProvider>();
    final user = context.watch<UserProvider>().user;
    final question = battle.currentQuestion;

    if (question == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.neonCyan),
      );
    }

    _animateIfNewQuestion(battle.currentIndex);

    return Column(
      children: [
        // ── Compact scoreboard (fixed height, never pushes options down) ──
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: _CompactScoreboard(battle: battle, user: user),
        ),

        // ── Q counter + timer row ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // progress dots
              Row(
                children: List.generate(battle.totalQuestions, (i) {
                  final done = i < battle.currentIndex;
                  final current = i == battle.currentIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.only(right: 5),
                    width: current ? 18 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: current
                          ? AppColors.neonCyan
                          : done
                              ? AppColors.neonCyan.withValues(alpha: 0.4)
                              : Colors.white12,
                    ),
                  );
                }),
              ),
              _TimerBadge(seconds: battle.secondsRemaining),
            ],
          ),
        ),

        // ── Scrollable question + options ──
        Expanded(
          child: SlideTransition(
            position: _qSlide,
            child: FadeTransition(
              opacity: _qFade,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                children: [
                  _questionCard(context, question),
                  const SizedBox(height: 12),
                  ...question
                      .optionsIn(battle.displayLanguage)
                      .asMap()
                      .entries
                      .map((e) => _OptionTile(
                            battle: battle,
                            index: e.key,
                            option: e.value,
                          )),
                  const SizedBox(height: 8),
                  _statusRow(battle),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _questionCard(BuildContext context, QuestionModel question) {
    final language = context.watch<BattleProvider>().displayLanguage;
    final primary = question.questionIn(language);
    final secondary = language == 'en' ? null : question.questionIn('en');

    return GlassCard(
      borderRadius: 18,
      borderColor: AppColors.neonPurple.withValues(alpha: 0.35),
      backgroundColor: const Color(0x331E1B4B),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            primary,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              height: 1.4,
            ),
          ),
          if (secondary != null && secondary != primary) ...[
            const SizedBox(height: 6),
            Text(
              secondary,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusRow(BattleProvider battle) {
    if (battle.phase == BattlePhase.reveal) {
      return _RevealPanel(battle: battle);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (battle.playerAnswered && !battle.opponentAnswered) ...[
            if (battle.isLive)
              const Icon(Icons.check_circle, size: 16, color: AppColors.neonCyan)
            else
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.neonPink,
                ),
              ),
            const SizedBox(width: 8),
            Text(
              battle.isLive
                  ? '${battle.opponentName} is answering…'
                  : '${battle.opponentName} is thinking…',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ] else if (battle.opponentAnswered && !battle.playerAnswered) ...[
            const Icon(Icons.check_circle, size: 16, color: AppColors.neonPink),
            const SizedBox(width: 8),
            Text(
              '${battle.opponentName} answered! Your turn…',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ] else ...[
            const Icon(Icons.bolt, size: 16, color: AppColors.neonGold),
            const SizedBox(width: 8),
            const Text(
              '🎯 Choose the right answer!',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Compact horizontal scoreboard ─────────────────────────────────────────

class _CompactScoreboard extends StatelessWidget {
  final BattleProvider battle;
  final UserModel user;

  const _CompactScoreboard({required this.battle, required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          // Player side
          Expanded(child: _playerSide()),
          // VS divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'VS',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppColors.neonGold,
                  ),
                ),
                const SizedBox(height: 2),
                Container(width: 1, height: 22, color: Colors.white12),
              ],
            ),
          ),
          // Opponent side
          Expanded(child: _opponentSide()),
        ],
      ),
    );
  }

  Widget _playerSide() {
    return Row(
      children: [
        _AvatarCircle(asset: user.effectiveAvatar, size: 36),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                S.you,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppColors.neonCyan,
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Text(
                  '${battle.playerScore}',
                  key: ValueKey(battle.playerScore),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              if (battle.playerStreak >= 2)
                Text(
                  '🔥${battle.playerStreak}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.neonCyan,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _opponentSide() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                battle.opponentName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppColors.neonPink,
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Text(
                  '${battle.opponentScore}',
                  key: ValueKey(battle.opponentScore),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              if (battle.opponentStreak >= 2)
                Text(
                  '🔥${battle.opponentStreak}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.neonPink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _AvatarCircle(asset: battle.opponentAvatar, size: 36),
      ],
    );
  }
}

// ── Reveal panel with animated point breakdown ─────────────────────────────

class _RevealPanel extends StatefulWidget {
  final BattleProvider battle;
  const _RevealPanel({required this.battle});

  @override
  State<_RevealPanel> createState() => _RevealPanelState();
}

class _RevealPanelState extends State<_RevealPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    )..forward();
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final battle = widget.battle;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.neonGold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.neonGold.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            children: [
              Text(
                battle.revealMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.neonGold,
                ),
              ),
              const SizedBox(height: 10),
              // Point breakdown table
              Row(
                children: [
                  Expanded(
                    child: _PointsBreakdown(
                      label: S.you,
                      pts: battle.lastRoundPlayer,
                      color: AppColors.neonCyan,
                      align: CrossAxisAlignment.start,
                    ),
                  ),
                  Container(width: 1, height: 56, color: Colors.white12),
                  Expanded(
                    child: _PointsBreakdown(
                      label: battle.opponentName,
                      pts: battle.lastRoundOpponent,
                      color: AppColors.neonPink,
                      align: CrossAxisAlignment.end,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PointsBreakdown extends StatelessWidget {
  final String label;
  final BattleRoundPoints pts;
  final Color color;
  final CrossAxisAlignment align;

  const _PointsBreakdown({
    required this.label,
    required this.pts,
    required this.color,
    required this.align,
  });

  @override
  Widget build(BuildContext context) {
    final isLeft = align == CrossAxisAlignment.start;
    return Padding(
      padding: EdgeInsets.only(
        left: isLeft ? 8 : 16,
        right: isLeft ? 16 : 8,
      ),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '+${pts.total} pts',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: pts.total > 0 ? Colors.white : AppColors.textMuted,
            ),
          ),
          if (pts.msTaken > 0) ...[
            const SizedBox(height: 2),
            Text(
              '⏱ ${(pts.msTaken / 1000).toStringAsFixed(1)}s',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (pts.total > 0) ...[
            const SizedBox(height: 2),
            _chip('✅ Correct', pts.base, color),
            if (pts.speedBonus > 0) _chip('⚡ Speed', pts.speedBonus, color),
            if (pts.firstBonus > 0) _chip('🥇 First', pts.firstBonus, color),
            if (pts.streakBonus > 0) _chip('🔥 Streak', pts.streakBonus, color),
          ] else
            const Text(
              'No points',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(String lbl, int val, Color color) {
    return Text(
      '$lbl +$val',
      style: TextStyle(
        fontSize: 10,
        color: color.withValues(alpha: 0.8),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// IMPROVED: Timer badge pulses red when ≤5 seconds remain.
class _TimerBadge extends StatefulWidget {
  final int seconds;
  const _TimerBadge({required this.seconds});

  @override
  State<_TimerBadge> createState() => _TimerBadgeState();
}

class _TimerBadgeState extends State<_TimerBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    if (widget.seconds <= 5) {
      _pulseCtrl.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_TimerBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.seconds <= 5 && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    } else if (widget.seconds > 5 && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUrgent = widget.seconds <= 5;
    final color = isUrgent ? AppColors.neonRed : AppColors.neonCyan;

    return ScaleTransition(
      scale: _pulseAnim,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color),
          boxShadow: isUrgent
              ? [
                  BoxShadow(
                    color: AppColors.neonRed.withValues(alpha: 0.35),
                    blurRadius: 12,
                    spreadRadius: 1,
                  )
                ]
              : [],
        ),
        child: Text(
          '⏱ ${widget.seconds}s',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// IMPROVED: Option tile animates in with a staggered slide, and has a
/// press-scale effect. On reveal, correct answer glows green.
class _OptionTile extends StatefulWidget {
  final BattleProvider battle;
  final int index;
  final String option;

  const _OptionTile({
    required this.battle,
    required this.index,
    required this.option,
  });

  @override
  State<_OptionTile> createState() => _OptionTileState();
}

class _OptionTileState extends State<_OptionTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _pressAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _pressAnim = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final battle = widget.battle;
    final index = widget.index;
    final option = widget.option;

    final revealing = battle.phase == BattlePhase.reveal;
    final correctIndex = battle.currentQuestion?.correctIndex ?? 0;

    Color border = Colors.white.withValues(alpha: 0.15);
    Color bg = Colors.white.withValues(alpha: 0.04);
    Color text = AppColors.textPrimary;
    IconData icon = Icons.radio_button_unchecked;
    String? tag;
    List<BoxShadow> glow = [];

    if (revealing) {
      if (index == correctIndex) {
        border = AppColors.neonGreen;
        bg = AppColors.neonGreen.withValues(alpha: 0.12);
        text = AppColors.neonGreen;
        icon = Icons.check_circle;
        tag = S.correct;
        glow = [
          BoxShadow(
            color: AppColors.neonGreen.withValues(alpha: 0.35),
            blurRadius: 16,
            spreadRadius: 1,
          )
        ];
      } else if (index == battle.playerSelected) {
        border = AppColors.neonRed;
        bg = AppColors.neonRed.withValues(alpha: 0.08);
        text = AppColors.neonRed;
        icon = Icons.cancel;
        tag = S.you;
      } else if (index == battle.opponentSelected) {
        border = AppColors.neonPink;
        bg = AppColors.neonPink.withValues(alpha: 0.08);
        text = AppColors.neonPink;
        icon = Icons.cancel;
        tag = battle.opponentName;
      } else {
        text = AppColors.textMuted;
      }
    } else {
      if (index == battle.playerSelected) {
        border = AppColors.neonCyan;
        bg = AppColors.neonCyan.withValues(alpha: 0.10);
        text = AppColors.neonCyan;
        icon = Icons.check_circle;
        glow = [
          BoxShadow(
            color: AppColors.neonCyan.withValues(alpha: 0.25),
            blurRadius: 12,
          )
        ];
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTapDown: revealing ? null : (_) {
          _pressCtrl.forward();
        },
        onTapUp: revealing ? null : (_) {
          _pressCtrl.reverse();
          battle.answerQuestion(index);
        },
        onTapCancel: revealing ? null : () {
          _pressCtrl.reverse();
        },
        child: ScaleTransition(
          scale: _pressAnim,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: revealing && index == correctIndex ? 1.8 : 1.2),
              boxShadow: glow,
            ),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    icon,
                    key: ValueKey(icon),
                    size: 18,
                    color: text,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    option,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          revealing && (index == correctIndex ||
                                  index == battle.playerSelected ||
                                  index == battle.opponentSelected)
                              ? FontWeight.bold
                              : FontWeight.w500,
                      color: text,
                    ),
                  ),
                ),
                if (tag != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 90),
                      child: Text(
                        tag,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: text,
                        ),
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
}

// ------------------------------------------------------------------ Result ---

/// IMPROVED: _ResultView is now a StatefulWidget with:
/// - Confetti for win/draw
/// - Entrance animations (scale + fade for emoji, slide-up for cards)
/// - Animated score counter
class _ResultView extends StatefulWidget {
  const _ResultView();

  @override
  State<_ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<_ResultView>
    with TickerProviderStateMixin {
  late final AnimationController _enterCtrl;
  late final AnimationController _scoreCtrl;
  late final ConfettiController _confetti;

  late final Animation<double> _emojiScale;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _card1Slide;
  late final Animation<Offset> _card2Slide;
  late final Animation<double> _btnFade;

  @override
  void initState() {
    super.initState();

    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scoreCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _confetti = ConfettiController(duration: const Duration(seconds: 3));

    _emojiScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _enterCtrl,
        curve: const Interval(0.0, 0.4, curve: Curves.elasticOut),
      ),
    );
    _titleFade = CurvedAnimation(
      parent: _enterCtrl,
      curve: const Interval(0.3, 0.6, curve: Curves.easeOut),
    );
    _card1Slide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _enterCtrl,
        curve: const Interval(0.4, 0.75, curve: Curves.easeOutCubic),
      ),
    );
    _card2Slide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _enterCtrl,
        curve: const Interval(0.55, 0.88, curve: Curves.easeOutCubic),
      ),
    );
    _btnFade = CurvedAnimation(
      parent: _enterCtrl,
      curve: const Interval(0.75, 1.0, curve: Curves.easeOut),
    );

    _enterCtrl.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _scoreCtrl.forward();
    });
  }

  void _maybeFireConfetti(bool isWin, bool isDraw) {
    if (isWin || isDraw) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _confetti.play();
      });
    }
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _scoreCtrl.dispose();
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final battle = context.watch<BattleProvider>();

    final String title;
    final String emoji;
    final Color color;
    bool confettiFired = false;

    if (battle.isForfeit) {
      title = '🏆 ${battle.opponentName} left — ${S.battleWinTitle}';
      emoji = '🏆';
      color = AppColors.neonGold;
    } else if (battle.isPlayerWin) {
      title = S.battleWinTitle;
      emoji = '🏆';
      color = AppColors.neonGold;
    } else if (battle.isDraw) {
      title = S.battleDrawTitle;
      emoji = '🤝';
      color = AppColors.neonCyan;
    } else {
      title = S.battleLoseTitle;
      emoji = '🤖';
      color = AppColors.neonPink;
    }

    if (!confettiFired && (battle.isPlayerWin || battle.isDraw || battle.isForfeit)) {
      confettiFired = true;
      _maybeFireConfetti(battle.isPlayerWin || battle.isForfeit, battle.isDraw);
    }

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        // Confetti for win/draw
        ConfettiWidget(
          confettiController: _confetti,
          blastDirectionality: BlastDirectionality.explosive,
          emissionFrequency: 0.07,
          numberOfParticles: 18,
          gravity: 0.2,
          colors: const [
            AppColors.neonGold,
            AppColors.neonCyan,
            AppColors.neonPink,
            AppColors.neonGreen,
            AppColors.neonPurple,
          ],
        ),

        ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const SizedBox(height: 20),

            // Bouncing emoji
            ScaleTransition(
              scale: _emojiScale,
              child: Text(
                emoji,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 72),
              ),
            ),
            const SizedBox(height: 8),

            // Fading title
            FadeTransition(
              opacity: _titleFade,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 4),

            FadeTransition(
              opacity: _titleFade,
              child: Text(
                'vs ${battle.opponentName} '
                '(${battle.difficulty.name} • '
                '${battle.isLive ? S.battleLiveMatch : S.battleBotMatch})',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 24),

            // Score card slides up
            SlideTransition(
              position: _card1Slide,
              child: FadeTransition(
                opacity: _titleFade,
                child: GlassCard(
                  borderRadius: 20,
                  borderColor: color.withValues(alpha: 0.5),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _resultStat(
                            S.you,
                            '${battle.playerScore}',
                            '${battle.playerCorrect}/'
                                '${battle.totalQuestions} ${S.correct}',
                            AppColors.neonCyan,
                          ),
                          Container(width: 1, height: 60, color: Colors.white12),
                          _resultStat(
                            battle.opponentName,
                            '${battle.opponentScore}',
                            S.battleBotCorrect(n: battle.opponentCorrect),
                            AppColors.neonPink,
                          ),
                        ],
                      ),
                      // Total answer time — the equal-score tie-breaker.
                      if (battle.playerTotalMs > 0 && battle.opponentTotalMs > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            '⏱ ${(battle.playerTotalMs / 1000).toStringAsFixed(1)}s'
                            '  vs  '
                            '${(battle.opponentTotalMs / 1000).toStringAsFixed(1)}s',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Coins card slides up
            SlideTransition(
              position: _card2Slide,
              child: FadeTransition(
                opacity: _btnFade,
                child: GlassCard(
                  borderRadius: 16,
                  borderColor: AppColors.neonGold.withValues(alpha: 0.4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.monetization_on, color: AppColors.neonGold, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        '+${battle.earnedCoins} ${S.coins}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.neonGold,
                        ),
                      ),
                      if (battle.earnedGems > 0) ...[
                        const SizedBox(width: 16),
                        const Icon(Icons.diamond, color: AppColors.neonPurple, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '+${battle.earnedGems} ${S.gems}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.neonPurple,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Buttons fade in last
            FadeTransition(
              opacity: _btnFade,
              child: NeonButton(
                text: S.battleRematch,
                onPressed: () => context.read<BattleProvider>().rematch(),
              ),
            ),
            const SizedBox(height: 12),
            
            // Revenge Match button (only if we have a previous opponent)
            if (context.read<BattleProvider>().hasRematchTarget)
              FadeTransition(
                opacity: _btnFade,
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6B6B), Color(0xFFE94560)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE94560).withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        final battle = context.read<BattleProvider>();
                        final success = await battle.rematchSameOpponent();
                        if (!success && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not start revenge match'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.gavel_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            context.read<BattleProvider>().lastOpponent?.isBot == true
                                ? '⚔️ Revenge (Same Bot)'
                                : '⚔️ Revenge (${context.read<BattleProvider>().lastOpponent?.name ?? "Opponent"})',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            FadeTransition(
              opacity: _btnFade,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: () {
                  context.read<BattleProvider>().resetBattle();
                  Navigator.popUntil(context, (route) => route.isFirst);
                },
                child: Text(
                  S.battleBackHome,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _resultStat(String label, String score, String sub, Color color) {
    return Column(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 110),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          score,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(sub, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
      ],
    );
  }
}

/// Small dismissible banner used for live-match failures on the setup screen.
class _BattleNoticeBanner extends StatelessWidget {
  const _BattleNoticeBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Colors.redAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded,
                color: Colors.white54, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
