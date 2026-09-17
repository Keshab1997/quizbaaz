import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/services/sound_service.dart';

class NeonButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Gradient? gradient;
  final Color? glowColor;
  final Widget? icon;
  final double height;
  final double? width;
  final double borderRadius;
  final TextStyle? textStyle;

  const NeonButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.gradient,
    this.glowColor,
    this.icon,
    this.height = 52.0,
    this.width,
    this.borderRadius = 16.0,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveGlowColor = glowColor ?? AppColors.neonGold;
    final effectiveGradient = gradient ?? AppColors.goldGradient;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: effectiveGlowColor.withValues(alpha: 0.4),
            blurRadius: 18,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: () {
            SoundService.instance.playClick();
            onPressed();
          },
          child: Ink(
            decoration: BoxDecoration(
              gradient: effectiveGradient,
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    icon!,
                    const SizedBox(width: 8),
                  ],
                  Text(
                    text,
                    style: textStyle ??
                        const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
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
