import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/providers/locale_provider.dart';
import '../../../data/services/hive_service.dart';
import '../../../data/services/sound_service.dart';
import '../../../l10n/app_strings.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/neon_button.dart';
import '../../widgets/quiz_language_pills.dart';
import '../dashboard/dashboard_screen.dart';

/// Interactive 3D Onboarding Screen for first-time visitors.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  void _finishOnboarding() {
    SoundService.instance.playOpen();
    HiveService.setMeta('has_completed_onboarding', true);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const DashboardScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  void _nextPage() {
    if (_currentPage < 2) {
      SoundService.instance.playWhoosh();
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finishOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            // Top Header Bar (Language Switcher + Skip)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  // App Badge
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.neonCyan.withValues(alpha: 0.5),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: Image.asset(
                            'assets/icons/app_icon_3d.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Image.asset(
                              'assets/images/characters/quizbaaz_mascot_boy.png',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'QuizBaaz',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),

                  // Language Pills
                  QuizLanguagePills(
                    available: const ['en', 'bn', 'hi'],
                    selected: localeProvider.appLanguage,
                    onSelected: (code) => localeProvider.setAppLanguage(code),
                  ),

                  // Skip Button
                  TextButton(
                    onPressed: _finishOnboarding,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                    ),
                    child: Text(
                      S.onboardingSkip,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Middle Carousel Area
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                children: [
                  // Slide 1: Daily Quiz & 3D Streaks
                  _buildSlide(
                    imagePath:
                        'assets/images/characters/quizbaaz_mascot_boy.png',
                    iconPath: 'assets/icons/streak_fire_3d.png',
                    title: S.onboard1Title,
                    description: S.onboard1Desc,
                    glowColor: AppColors.neonGold,
                  ),

                  // Slide 2: 1v1 Battle Arena
                  _buildSlide(
                    imagePath:
                        'assets/images/characters/quizbaaz_battle_duo.png',
                    iconPath: 'assets/icons/battle_swords_3d.png',
                    title: S.onboard2Title,
                    description: S.onboard2Desc,
                    glowColor: AppColors.neonCyan,
                  ),

                  // Slide 3: Chapter Bank & Champion Rewards
                  _buildSlide(
                    imagePath:
                        'assets/images/characters/quizbaaz_champion.png',
                    iconPath: 'assets/icons/gift_box_3d.png',
                    title: S.onboard3Title,
                    description: S.onboard3Desc,
                    glowColor: AppColors.neonPurple,
                  ),
                ],
              ),
            ),

            // Bottom Navigation Controls
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  // Indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, (index) {
                      final active = index == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 8,
                        width: active ? 28 : 8,
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.neonGold
                              : Colors.white.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color: AppColors.neonGold
                                        .withValues(alpha: 0.5),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 24),

                  // Action Button
                  NeonButton(
                    text: _currentPage == 2
                        ? S.onboardingStart
                        : S.onboardingNext,
                    width: double.infinity,
                    glowColor: _currentPage == 2
                        ? AppColors.neonCyan
                        : AppColors.neonGold,
                    onPressed: _nextPage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlide({
    required String imagePath,
    required String iconPath,
    required String title,
    required String description,
    required Color glowColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 3D Glass Hero Showcase Card
          Expanded(
            child: GlassCard(
              blur: 20,
              padding: const EdgeInsets.all(20),
              child: Stack(
                children: [
                  // Ambient Glow
                  Center(
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: glowColor.withValues(alpha: 0.22),
                            blurRadius: 70,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 3D Hero Mascot Character
                  Center(
                    child: Image.asset(
                      imagePath,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.quiz_rounded,
                        size: 100,
                        color: AppColors.neonGold,
                      ),
                    ),
                  ),

                  // Floating 3D Badge Overlay
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      width: 64,
                      height: 64,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.40),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: glowColor.withValues(alpha: 0.60),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: glowColor.withValues(alpha: 0.35),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: Image.asset(
                        iconPath,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.stars_rounded,
                          color: glowColor,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Slide Title
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              height: 1.2,
            ),
          ),

          const SizedBox(height: 12),

          // Slide Description
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
