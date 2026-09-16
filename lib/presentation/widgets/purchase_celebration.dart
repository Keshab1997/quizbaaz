import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/services/haptic_service.dart';
import '../../data/services/sound_service.dart';

/// Premium purchase-reward overlay.
///
/// Layered structure (the underlying Shop screen never moves or re-layouts):
///
///   Stack
///   ├── Semi-transparent dark backdrop + subtle blur   (fades in)
///   ├── Confetti burst                                  (background layer)
///   └── Centered reward content
///       ├── 3D mascot + pulsing glow halo + item badge
///       ├── 🎉 PURCHASED!
///       ├── Item name
///       ├── "Added to your inventory"
///       └── "Tap anywhere to continue"
///
/// Entrance (~900ms): backdrop fades → confetti starts → character scales
/// 0.7→1.0 elastic → texts fade/slide in one after another. The character
/// gently bobs and the glow pulses the whole time it is on screen.
class PurchaseCelebration {
  static bool _showing = false;

  static void show(
    BuildContext context, {
    required String itemName,
    required String subtitle,
    required String characterAsset,
    required IconData itemIcon,
    required Color accent,
  }) {
    // Never stack overlays on rapid taps.
    if (_showing) return;
    _showing = true;

    SoundService.instance.play('ui_open');
    Haptics.medium();

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'purchase-celebration',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 900),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _CelebrationOverlay(
          itemName: itemName,
          subtitle: subtitle,
          characterAsset: characterAsset,
          itemIcon: itemIcon,
          accent: accent,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
    ).whenComplete(() => _showing = false);
  }
}

class _CelebrationOverlay extends StatefulWidget {
  final String itemName;
  final String subtitle;
  final String characterAsset;
  final IconData itemIcon;
  final Color accent;

  const _CelebrationOverlay({
    required this.itemName,
    required this.subtitle,
    required this.characterAsset,
    required this.itemIcon,
    required this.accent,
  });

  @override
  State<_CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<_CelebrationOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _float;
  late final ConfettiController _confetti;
  Timer? _autoDismiss;

  // Entrance phases.
  late final Animation<double> _backdropOpacity;
  late final Animation<double> _charScale;
  late final Animation<double> _titleAnim;
  late final Animation<double> _nameAnim;
  late final Animation<double> _subAnim;
  late final Animation<double> _hintAnim;

  // Continuous idle motion.
  late final Animation<Offset> _bob;
  late final Animation<double> _glowPulse;
  late final Animation<double> _badgePulse;

  @override
  void initState() {
    super.initState();

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _backdropOpacity = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
    );
    _charScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.05, 0.7, curve: Curves.elasticOut),
      ),
    );
    _titleAnim = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.4, 0.75, curve: Curves.easeOutCubic),
    );
    _nameAnim = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.55, 0.9, curve: Curves.easeOutCubic),
    );
    _subAnim = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.7, 1.0, curve: Curves.easeOutCubic),
    );
    _hintAnim = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.8, 1.0, curve: Curves.easeOutCubic),
    );

    _float = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _bob = Tween<Offset>(begin: Offset.zero, end: const Offset(0, -0.035))
        .animate(CurvedAnimation(parent: _float, curve: Curves.easeInOut));
    _glowPulse = Tween<double>(begin: 1.0, end: 1.08)
        .animate(CurvedAnimation(parent: _float, curve: Curves.easeInOut));
    _badgePulse = Tween<double>(begin: 1.0, end: 1.12)
        .animate(CurvedAnimation(parent: _float, curve: Curves.easeInOut));

    _confetti = ConfettiController(duration: const Duration(milliseconds: 2400));
    WidgetsBinding.instance.addPostFrameCallback((_) => _confetti.play());

    // Give the player a moment to enjoy it, then dismiss automatically.
    _autoDismiss = Timer(const Duration(milliseconds: 3200), _dismiss);
  }

  void _dismiss() {
    if (!mounted) return;
    _autoDismiss?.cancel();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    _confetti.dispose();
    _entrance.dispose();
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _dismiss,
      behavior: HitTestBehavior.opaque,
      child: SafeArea(
        child: Stack(
          children: [
            // 1. Dark backdrop with subtle blur (fades in smoothly).
            Positioned.fill(
              child: FadeTransition(
                opacity: _backdropOpacity,
                child: RepaintBoundary(
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                      child: Container(color: const Color(0x8C0A0E21)),
                    ),
                  ),
                ),
              ),
            ),
            // 2. Confetti (behind the content).
            Positioned.fill(
              child: IgnorePointer(
                child: ConfettiWidget(
                  confettiController: _confetti,
                  blastDirectionality: BlastDirectionality.explosive,
                  blastDirection: -math.pi / 2,
                  emissionFrequency: 0.05,
                  numberOfParticles: 22,
                  maxBlastForce: 22,
                  minBlastForce: 8,
                  gravity: 0.3,
                  shouldLoop: false,
                  colors: const [
                    AppColors.neonGold,
                    AppColors.neonPurple,
                    AppColors.neonCyan,
                    AppColors.neonPink,
                    AppColors.neonGreen,
                  ],
                ),
              ),
            ),
            // 3. Centered reward content (scrollable so it never overflows
            //    on short/landscape screens).
            Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: _buildContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCharacter(),
        const SizedBox(height: 26),
        _fadeSlideUp(
          _titleAnim,
          const Text(
            '🎉 PURCHASED!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.0,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _fadeSlideUp(
          _nameAnim,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              widget.itemName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: widget.accent,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _fadeSlideUp(
          _subAnim,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              widget.subtitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _fadeSlideUp(
          _hintAnim,
          const Text(
            'Tap anywhere to continue',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCharacter() {
    final Color onAccent =
        widget.accent == AppColors.neonGold ? Colors.black : Colors.white;

    return SizedBox(
      width: 250,
      height: 320,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Pulsing glow halo behind the character.
          ScaleTransition(
            scale: _glowPulse,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    widget.accent.withValues(alpha: 0.5),
                    widget.accent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // 3D character: elastic scale-in + gentle bob.
          ScaleTransition(
            scale: _charScale,
            child: SlideTransition(
              position: _bob,
              child: Image.asset(
                widget.characterAsset,
                width: 234,
                fit: BoxFit.contain,
                errorBuilder: (c, e, s) => Icon(
                  Icons.celebration,
                  size: 140,
                  color: widget.accent,
                ),
              ),
            ),
          ),
          // Glowing item badge.
          Positioned(
            top: 6,
            right: 24,
            child: ScaleTransition(
              scale: _badgePulse,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.accent,
                  boxShadow: [
                    BoxShadow(
                      color: widget.accent.withValues(alpha: 0.7),
                      blurRadius: 22,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(widget.itemIcon, size: 26, color: onAccent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fadeSlideUp(Animation<double> anim, Widget child) {
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(anim),
        child: child,
      ),
    );
  }
}
