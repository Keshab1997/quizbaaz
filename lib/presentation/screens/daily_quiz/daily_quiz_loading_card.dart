import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/chapter_set_progress.dart';
import '../../../data/providers/quiz_provider.dart';
import '../../../data/providers/user_provider.dart';
import '../../../l10n/app_strings.dart';

/// Cinematic 3D loading card shown while a daily (or chapter) quiz is
/// prepared. Replaces the old indeterminate spinner — the question bank is
/// local, so without this card the player would never see a loading state.
class DailyQuizLoadingCard extends StatefulWidget {
  const DailyQuizLoadingCard({super.key});

  @override
  State<DailyQuizLoadingCard> createState() => _DailyQuizLoadingCardState();
}

class _DailyQuizLoadingCardState extends State<DailyQuizLoadingCard>
    with TickerProviderStateMixin {
  late final AnimationController _floatCtrl;
  late final AnimationController _glowCtrl;
  late final AnimationController _progressCtrl;
  late final AnimationController _sparkCtrl;

  late final Animation<double> _float;
  late final Animation<double> _glow;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward();
    _sparkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();

    _float = Tween<double>(
      begin: -8,
      end: 8,
    ).animate(CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut));
    _glow = Tween<double>(
      begin: 0.35,
      end: 0.75,
    ).animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));
    _progress = CurvedAnimation(parent: _progressCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _glowCtrl.dispose();
    _progressCtrl.dispose();
    _sparkCtrl.dispose();
    super.dispose();
  }

  String _stepLabel(double t) {
    if (t < 0.28) return S.quizLoadStepShuffle;
    if (t < 0.55) return S.quizLoadStepTimer;
    if (t < 0.82) return S.quizLoadStepBoost;
    return S.quizLoadStepReady;
  }

  @override
  Widget build(BuildContext context) {
    final quiz = context.watch<QuizProvider>();
    final config = context.watch<UserProvider>().config;
    final isDaily = quiz.isDailyQuiz;
    final character = isDaily ? AppAssets.dailyStar : AppAssets.heroGirl;

    final eyebrow = isDaily ? S.quizLoadEyebrow : S.quizLoadChapterEyebrow;
    final title =
        isDaily ? S.quizLoadTitle : S.quizLoadChapterTitle(n: quiz.setNumber);
    final body =
        isDaily
            ? S.quizLoadBody(n: config.dailyQuestionCount)
            : S.quizLoadChapterBody;
    final questionCount =
        isDaily ? config.dailyQuestionCount : kQuestionsPerSet;
    final totalSeconds = questionCount * config.secondsPerQuestion;
    final durationLabel =
        '${(totalSeconds ~/ 60).toString().padLeft(2, '0')}:${(totalSeconds % 60).toString().padLeft(2, '0')}';
    final maxCoins =
        isDaily
            ? config.dailyMaxCoins
            : questionCount * config.coinsPerCorrectPractice +
                config.perfectBonusCoins;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [AppColors.bgNavy, AppColors.bgCard, AppColors.bgDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: AppColors.neonPurple.withValues(alpha: 0.48),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.neonPurple.withValues(alpha: 0.28),
              blurRadius: 32,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: AppColors.neonCyan.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _sparkCtrl,
                  builder:
                      (_, __) => CustomPaint(
                        painter: _LoadingSparkPainter(
                          progress: _sparkCtrl.value,
                        ),
                      ),
                ),
              ),
              Positioned(
                top: -70,
                right: -50,
                child: AnimatedBuilder(
                  animation: _glow,
                  builder:
                      (_, __) => Container(
                        width: 210,
                        height: 210,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.neonCyan.withValues(
                            alpha: 0.08 * _glow.value,
                          ),
                        ),
                      ),
                ),
              ),
              Positioned(
                bottom: -80,
                left: -40,
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.neonPink.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.neonCyan.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.neonCyan.withValues(alpha: 0.34),
                        ),
                      ),
                      child: Text(
                        eyebrow,
                        style: const TextStyle(
                          color: AppColors.neonCyan,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.15,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 210,
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_float, _glow]),
                        builder:
                            (_, __) => Transform.translate(
                              offset: Offset(0, _float.value),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.neonPurple.withValues(
                                        alpha: 0.38 * _glow.value,
                                      ),
                                      blurRadius: 42,
                                      spreadRadius: 10,
                                    ),
                                    BoxShadow(
                                      color: AppColors.neonGold.withValues(
                                        alpha: 0.18 * _glow.value,
                                      ),
                                      blurRadius: 24,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Image.asset(
                                  character,
                                  height: 200,
                                  fit: BoxFit.contain,
                                  errorBuilder:
                                      (_, __, ___) => const Icon(
                                        Icons.auto_awesome_rounded,
                                        color: AppColors.neonGold,
                                        size: 88,
                                      ),
                                ),
                              ),
                            ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 18),
                    AnimatedBuilder(
                      animation: _progress,
                      builder: (_, __) {
                        return Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                height: 8,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ColoredBox(
                                      color: AppColors.textPrimary.withValues(
                                        alpha: 0.08,
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: FractionallySizedBox(
                                        widthFactor: _progress.value.clamp(
                                          0.08,
                                          1,
                                        ),
                                        heightFactor: 1,
                                        child: const DecoratedBox(
                                          decoration: BoxDecoration(
                                            gradient: AppColors.cyanGradient,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _stepLabel(_progress.value),
                              style: const TextStyle(
                                color: AppColors.neonGold,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _MetaChip(
                            icon: Icons.quiz_rounded,
                            label: S.quizLoadMetaQuestions(n: questionCount),
                            color: AppColors.neonCyan,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MetaChip(
                            icon: Icons.timer_outlined,
                            label: durationLabel,
                            color: AppColors.neonGold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MetaChip(
                            icon: Icons.monetization_on_rounded,
                            label: S.quizLoadMetaCoins(n: maxCoins),
                            color: AppColors.neonGold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgDark.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingSparkPainter extends CustomPainter {
  final double progress;

  _LoadingSparkPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final cx = size.width / 2;
    final cy = size.height * 0.38;

    for (var r = 0; r < 3; r++) {
      final radius = 48.0 + r * 28;
      canvas.drawCircle(
        Offset(cx, cy),
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = AppColors.neonPurple.withValues(alpha: 0.07 - r * 0.015),
      );
    }

    final angle = progress * 2 * math.pi;
    canvas.drawCircle(
      Offset(cx + 92 * math.cos(angle), cy + 40 * math.sin(angle)),
      3.2,
      Paint()..color = AppColors.neonCyan.withValues(alpha: 0.55),
    );
    canvas.drawCircle(
      Offset(
        cx + 70 * math.cos(-angle * 1.4),
        cy + 58 * math.sin(-angle * 1.4),
      ),
      2.4,
      Paint()..color = AppColors.neonGold.withValues(alpha: 0.5),
    );

    final rng = math.Random(7);
    for (var i = 0; i < 16; i++) {
      final sx = rng.nextDouble() * size.width;
      final sy = rng.nextDouble() * size.height;
      final twinkle = (math.sin(progress * 2 * math.pi + i * 1.15) + 1) / 2;
      final color = i.isEven ? AppColors.neonGold : AppColors.neonCyan;
      canvas.drawCircle(
        Offset(sx, sy),
        1.1 + twinkle * 1.4,
        Paint()..color = color.withValues(alpha: 0.12 + twinkle * 0.28),
      );
    }
  }

  @override
  bool shouldRepaint(_LoadingSparkPainter old) => old.progress != progress;
}
