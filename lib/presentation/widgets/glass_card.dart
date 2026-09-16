import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// A soft glass surface used by cards across the app.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? borderColor;
  final Color? backgroundColor;
  final double blur;
  final VoidCallback? onTap;
  final double? width;
  final double? height;
  final List<BoxShadow>? shadows;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 22.0,
    this.padding = const EdgeInsets.all(16.0),
    this.margin,
    this.borderColor,
    this.backgroundColor,
    this.blur = 18.0,
    this.onTap,
    this.width,
    this.height,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final card = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: shadows ??
            [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
      ),
      // RepaintBoundary isolates the blur layer during route transitions.
      // Without it, popping a screen full of glass cards trips the
      // '!semantics.parentDataDirty' assertion in the rendering pipeline.
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: backgroundColor ?? AppColors.bgCardGlass,
                borderRadius: radius,
                border: Border.all(
                  color: borderColor ?? AppColors.outline,
                  width: 1,
                ),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.075),
                    Colors.white.withValues(alpha: 0.018),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        splashColor: AppColors.neonCyan.withValues(alpha: 0.10),
        highlightColor: Colors.white.withValues(alpha: 0.025),
        child: card,
      ),
    );
  }
}
