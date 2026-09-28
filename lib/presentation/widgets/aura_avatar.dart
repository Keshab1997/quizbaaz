import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import 'cached_avatar.dart';

/// Animated Holographic Neon Aura Avatar frame.
///
/// Features:
/// - 60 FPS rotating holographic neon gradient ring
/// - Pulsing glowing border
/// - Floating sparkle particles
/// - Full GIF / WebP / Network image support
class AuraAvatar extends StatefulWidget {
  final String url;
  final double size;
  final bool isAnimated;
  final List<Color> auraColors;
  final String? fallbackAsset;
  final VoidCallback? onTap;

  const AuraAvatar({
    super.key,
    required this.url,
    this.size = 100,
    this.isAnimated = true,
    this.auraColors = const [
      AppColors.neonCyan,
      AppColors.neonPurple,
      AppColors.neonPink,
      AppColors.neonGold,
      AppColors.neonCyan,
    ],
    this.fallbackAsset,
    this.onTap,
  });

  @override
  State<AuraAvatar> createState() => _AuraAvatarState();
}

class _AuraAvatarState extends State<AuraAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.isAnimated) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(AuraAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAnimated && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isAnimated && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Rotating Holographic Aura Ring
            if (widget.isAnimated)
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final angle = _controller.value * 2 * math.pi;
                  final pulse =
                      (math.sin(_controller.value * 2 * math.pi) + 1) / 2;

                  return Container(
                    width: widget.size * 0.96,
                    height: widget.size * 0.96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        transform: GradientRotation(angle),
                        colors: widget.auraColors,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: widget.auraColors.first.withValues(
                            alpha: 0.3 + (pulse * 0.3),
                          ),
                          blurRadius: 18 + (pulse * 8),
                          spreadRadius: 2 + (pulse * 3),
                        ),
                      ],
                    ),
                  );
                },
              )
            else
              Container(
                width: widget.size * 0.92,
                height: widget.size * 0.92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(colors: widget.auraColors),
                ),
              ),

            // Inner Dark Glass Ring Padding — slightly smaller to avoid head clipping
            Container(
              width: widget.size * 0.84,
              height: widget.size * 0.84,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF100B26),
              ),
              child: ClipOval(
                child: CachedAvatar(
                  url: widget.url,
                  fit: BoxFit.cover,
                  // Top bias (-0.2) keeps head visible, prevents top cut
                  alignment: const Alignment(0, -0.2),
                  fallbackAsset: widget.fallbackAsset,
                  fallbackIconSize: widget.size * 0.4,
                ),
              ),
            ),

            // Sparkle Particle Dots
            if (widget.isAnimated)
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final val = _controller.value * 2 * math.pi;
                  final x1 = math.cos(val) * (widget.size * 0.44);
                  final y1 = math.sin(val) * (widget.size * 0.44);
                  final x2 = math.cos(val + math.pi) * (widget.size * 0.44);
                  final y2 = math.sin(val + math.pi) * (widget.size * 0.44);

                  return Stack(
                    children: [
                      Positioned(
                        left: (widget.size / 2) + x1 - 4,
                        top: (widget.size / 2) + y1 - 4,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.neonCyan,
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: (widget.size / 2) + x2 - 4,
                        top: (widget.size / 2) + y2 - 4,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.neonGold,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.neonGold,
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
