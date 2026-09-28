import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// The shared visual canvas for every QuizBaaz screen.
///
/// Keeping this behind the Navigator means the dashboard, quiz, ranking,
/// rewards and profile pages all feel like one product instead of separate
/// dark screens. It is intentionally built with Flutter primitives only, so
/// it works offline and does not depend on a remote image or CSS asset.
class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.pageGradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(
            child: Stack(
              children: [
                _GlowOrb(
                  alignment: Alignment(-1.12, -1.10),
                  size: 330,
                  color: AppColors.neonPurple,
                  opacity: 0.22,
                ),
                _GlowOrb(
                  alignment: Alignment(1.15, -0.25),
                  size: 290,
                  color: AppColors.neonCyan,
                  opacity: 0.13,
                ),
                _GlowOrb(
                  alignment: Alignment(0.95, 1.12),
                  size: 310,
                  color: AppColors.neonGold,
                  opacity: 0.10,
                ),
                Positioned.fill(child: CustomPaint(painter: _AmbientPainter())),
              ],
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final Alignment alignment;
  final double size;
  final Color color;
  final double opacity;

  const _GlowOrb({
    required this.alignment,
    required this.size,
    required this.color,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 54, sigmaY: 54),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: opacity),
          ),
        ),
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.018)
          ..strokeWidth = 1;

    for (double x = 20; x < size.width; x += 54) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 24; y < size.height; y += 54) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final points = <Offset>[
      Offset(size.width * .12, size.height * .15),
      Offset(size.width * .84, size.height * .10),
      Offset(size.width * .73, size.height * .33),
      Offset(size.width * .16, size.height * .55),
      Offset(size.width * .88, size.height * .72),
      Offset(size.width * .27, size.height * .88),
    ];
    final dotPaint =
        Paint()..color = AppColors.neonCyan.withValues(alpha: 0.20);
    for (final point in points) {
      canvas.drawCircle(point, 1.6, dotPaint);
      canvas.drawCircle(
        point,
        5,
        Paint()..color = AppColors.neonCyan.withValues(alpha: 0.035),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
