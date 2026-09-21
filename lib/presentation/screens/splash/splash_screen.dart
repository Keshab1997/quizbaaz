import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/services/hive_service.dart';
import '../../../data/services/sound_service.dart';
import '../../../l10n/app_strings.dart';
import '../dashboard/dashboard_screen.dart';
import '../onboarding/onboarding_screen.dart';

/// 3D Splash Screen shown on cold start.
///
/// Multi-phase cinematic reveal:
///   1. logo pops in with an elastic scale + 3D flip and a glow bloom,
///   2. a rotating neon ring with orbiting sparkles settles around the logo,
///   3. the brand title shimmers and slides up, then the tagline follows,
///   4. a sleek loading bar fills while the background glows breathe.
///
/// After the reveal it checks the onboarding flag in Hive
/// (`has_completed_onboarding`) and cross-fades into the
/// OnboardingScreen (first launch) or DashboardScreen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  /// One-shot reveal timeline for the whole brand block.
  late final AnimationController _entrance;

  /// Looping ambient controller (breathing glow / shimmer sweep).
  late final AnimationController _breathe;

  /// Continuous one-way rotation for the neon ring + sparkles.
  late final AnimationController _spin;

  /// Loading bar fill (matches the navigation delay).
  late final AnimationController _progress;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoFlip;
  late final Animation<double> _glowBloom;

  late final Animation<double> _titleFade;
  late final Animation<double> _titleSlide;
  late final Animation<double> _taglineFade;
  late final Animation<double> _taglineSlide;

  @override
  void initState() {
    super.initState();

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2100),
    );

    // Logo: elastic pop-in during the first half, 3D flip during the same.
    _logoScale = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.0, 0.55, curve: Curves.elasticOut),
    );
    _logoFlip = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.0, 0.50, curve: Curves.easeOutBack),
    );
    _glowBloom = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.15, 0.7, curve: Curves.easeOutCubic),
    );

    // Title + tagline reveal.
    _titleFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.45, 0.75, curve: Curves.easeOut),
    );
    _titleSlide = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.45, 0.75, curve: Curves.easeOutCubic),
    );
    _taglineFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.60, 0.9, curve: Curves.easeOut),
    );
    _taglineSlide = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.60, 0.9, curve: Curves.easeOutCubic),
    );

    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);

    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();

    _progress = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2150),
    );

    _entrance.forward();
    _progress.forward();
    SoundService.instance.playOpen();

    _scheduleNavigation();
  }

  Future<void> _scheduleNavigation() async {
    await Future.delayed(const Duration(milliseconds: 2450));
    if (!mounted) return;

    final hasCompletedOnboarding =
        HiveService.getMeta<bool>('has_completed_onboarding') ?? false;

    final targetScreen = hasCompletedOnboarding
        ? const DashboardScreen()
        : const OnboardingScreen();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => targetScreen,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _entrance.dispose();
    _breathe.dispose();
    _spin.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Stack(
        children: [
          // ── Ambient gradient glow blobs (breathing) ──────────────────
          _buildAmbientGlows(),

          // ── Central brand block ──────────────────────────────────────
          Center(child: _buildBranding()),

          // ── Bottom: loading bar + version badge ──────────────────────
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Column(
              children: [
                _buildLoadingBar(),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Text(
                    'v1.0.0+1',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Ambient background glows
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildAmbientGlows() {
    return AnimatedBuilder(
      animation: _breathe,
      builder: (context, _) {
        final t = _breathe.value; // 0..1 breathing
        return Stack(
          children: [
            Positioned(
              top: -100,
              left: -100,
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.neonPurple.withValues(
                        alpha: 0.18 + 0.14 * t,
                      ),
                      blurRadius: 110,
                      spreadRadius: 10 * t,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: -80,
              right: -80,
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.neonCyan.withValues(
                        alpha: 0.14 + 0.12 * (1 - t),
                      ),
                      blurRadius: 110,
                      spreadRadius: 8 * (1 - t),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Central logo + ring + title + tagline
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildBranding() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ── Logo with 3D flip + elastic scale + orbiting neon ring ──
        SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Bloom glow behind the logo.
              AnimatedBuilder(
                animation: Listenable.merge([_glowBloom, _breathe]),
                builder: (context, _) {
                  return Container(
                    width: 190,
                    height: 190,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.neonGold.withValues(
                            alpha: 0.35 * _glowBloom.value,
                          ),
                          blurRadius: 60,
                          spreadRadius: 6 * _glowBloom.value,
                        ),
                        BoxShadow(
                          color: AppColors.neonCyan.withValues(
                            alpha: 0.25 * _glowBloom.value,
                          ),
                          blurRadius: 90,
                          spreadRadius: -8,
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Rotating neon ring + orbiting sparkles.
              SizedBox(
                width: 210,
                height: 210,
                child: AnimatedBuilder(
                  animation: _spin,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _OrbitPainter(
                        rotation: _spin.value,
                        bloom: _glowBloom.value,
                      ),
                    );
                  },
                ),
              ),

              // The 3D logo tile itself.
              AnimatedBuilder(
                animation: _entrance,
                builder: (context, _) {
                  final double scale = _logoScale.value
                      .clamp(0.0, 1.15)
                      .toDouble();
                  final double flip = _logoFlip.value
                      .clamp(0.0, 1.0)
                      .toDouble();
                  final double angleY = (1 - flip) * (math.pi / 2);
                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..rotateY(angleY),
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 140,
                        height: 140,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.neonGold.withValues(alpha: 0.45),
                              blurRadius: 36,
                              spreadRadius: 2,
                              offset: const Offset(0, 8),
                            ),
                            BoxShadow(
                              color: AppColors.neonCyan.withValues(alpha: 0.30),
                              blurRadius: 50,
                              spreadRadius: -4,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Image.asset(
                            'assets/icons/app_icon_3d.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Image.asset(
                              'assets/images/characters/quizbaaz_mascot_boy.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 30),

        // ── App title with shimmer + slide-up ─────────────────────────
        FadeTransition(
          opacity: _titleFade,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.45),
              end: Offset.zero,
            ).animate(_titleSlide),
            child: AnimatedBuilder(
              animation: _spin,
              builder: (context, _) {
                final sweep = _spin.value;
                return ShaderMask(
                  shaderCallback: (bounds) {
                    final shift = -1.4 + 2.8 * sweep;
                    return LinearGradient(
                      begin: Alignment(shift, -0.6),
                      end: Alignment(shift + 1.2, 0.6),
                      colors: const [
                        AppColors.neonGold,
                        Colors.white,
                        AppColors.neonCyan,
                        AppColors.neonGold,
                      ],
                    ).createShader(bounds);
                  },
                  child: const Text(
                    'QuizBaaz 3D',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        const SizedBox(height: 8),

        // ── Tagline slide-up ───────────────────────────────────────────
        FadeTransition(
          opacity: _taglineFade,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.6),
              end: Offset.zero,
            ).animate(_taglineSlide),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                S.splashTagline,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Sleek animated loading bar
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildLoadingBar() {
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        final value = _progress.value;
        return Container(
          width: 150,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(3),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              children: [
                // Filling gradient bar.
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: value,
                    heightFactor: 1,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.neonCyan,
                            AppColors.neonPurple,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Soft leading glow dot.
                if (value > 0.02 && value < 1.0)
                  Align(
                    alignment: Alignment(2 * value - 1, 0),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.neonCyan,
                            blurRadius: 8,
                            spreadRadius: 1,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Painter: rotating gradient ring + orbiting sparkles around the logo.
// ─────────────────────────────────────────────────────────────────────────
class _OrbitPainter extends CustomPainter {
  _OrbitPainter({required this.rotation, required this.bloom});

  /// 0..1 rotation phase (continuous).
  final double rotation;

  /// 0..1 appearance amount (ring fades in with the logo).
  final double bloom;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 6;

    // Faint full ring (backdrop for the rotating arcs).
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = AppColors.neonPurple.withValues(alpha: 0.22 * bloom);
    canvas.drawCircle(center, radius, faint);

    // Two glowing arc segments chasing each other around the ring.
    final phase = rotation * math.pi * 2;
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;

    arcPaint
      ..color = AppColors.neonCyan.withValues(alpha: 0.95 * bloom)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      phase,
      math.pi * 0.75,
      false,
      arcPaint,
    );

    arcPaint.color = AppColors.neonPurple.withValues(alpha: 0.90 * bloom);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      phase + math.pi * 0.95,
      math.pi * 0.55,
      false,
      arcPaint,
    );

    // Orbiting sparkle dots.
    final dotColors = [
      AppColors.neonGold,
      AppColors.neonPink,
      Colors.white,
    ];
    for (int i = 0; i < dotColors.length; i++) {
      final angle = phase + (i * math.pi * 2 / dotColors.length);
      final pos = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      final dot = Paint()
        ..color = dotColors[i].withValues(alpha: 0.9 * bloom)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(pos, 3.2 + (i % 2), dot);
      canvas.drawCircle(pos, 1.4, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) {
    return oldDelegate.rotation != rotation || oldDelegate.bloom != bloom;
  }
}
