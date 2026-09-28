import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Network avatar image with a **persistent disk + memory cache**.
///
/// Wraps [CachedNetworkImage] so every cloud avatar in the app:
/// * downloads from ImgBB only **once** — later loads come from local disk,
///   even after an app restart (unlike `Image.network`);
/// * renders instantly from the in-memory cache while scrolling;
/// * falls back to [fallbackAsset] or an [Icon] when the URL fails,
///   so the UI never breaks when offline.
///
/// Use [showProgress] to control the first-download placeholder.
class CachedAvatar extends StatelessWidget {
  const CachedAvatar({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.borderRadius,
    this.showProgress = true,
    this.progressColor,
    this.fallbackIcon = Icons.person_rounded,
    this.fallbackIconColor,
    this.fallbackIconSize = 28,
    this.fallbackAsset,
    this.fallbackBuilder,
  });

  /// Remote image URL (http/https). Non-network paths are rendered via
  /// `Image.asset` automatically, so the widget is a drop-in replacement.
  final String url;

  final BoxFit fit;
  final Alignment alignment;
  final double? width;
  final double? height;

  /// Optional corner radius applied to the image.
  final BorderRadius? borderRadius;

  /// Show a subtle spinner while the *first-ever* download happens.
  final bool showProgress;
  final Color? progressColor;

  /// Icon shown when the image fails to load and no [fallbackAsset] is set.
  final IconData fallbackIcon;
  final Color? fallbackIconColor;
  final double fallbackIconSize;

  /// Optional asset path (e.g. a bundled default avatar) preferred over the
  /// icon when the network image fails.
  final String? fallbackAsset;

  /// Fully custom fallback widget (takes precedence over [fallbackAsset]).
  final Widget Function(BuildContext context)? fallbackBuilder;

  @override
  Widget build(BuildContext context) {
    final isNetwork = url.startsWith('http://') || url.startsWith('https://');
    final isAnimatedFormat =
        url.toLowerCase().contains('.gif') ||
        url.toLowerCase().contains('.webp');

    Widget image;
    if (isNetwork) {
      image = CachedNetworkImage(
        imageUrl: url,
        fit: fit,
        alignment: alignment,
        width: width,
        height: height,
        // Do not force memCacheWidth for animated GIF/WebP so animation frames loop smoothly
        memCacheWidth: isAnimatedFormat ? null : 512,
        maxWidthDiskCache: isAnimatedFormat ? null : 512,
        useOldImageOnUrlChange: true,
        fadeOutDuration: const Duration(milliseconds: 200),
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder:
            showProgress
                ? (_, __) => Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: progressColor,
                  ),
                )
                : null,
        errorWidget: (_, __, ___) => _buildFallback(),
      );
    } else {
      image = Image.asset(
        url,
        fit: fit,
        alignment: alignment,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => _buildFallback(),
      );
    }

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }

  Widget _buildFallback() {
    if (fallbackBuilder != null) {
      return Builder(builder: fallbackBuilder!);
    }
    if (fallbackAsset != null && fallbackAsset!.isNotEmpty) {
      return Image.asset(
        fallbackAsset!,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => _buildFallbackIcon(),
      );
    }
    return _buildFallbackIcon();
  }

  Widget _buildFallbackIcon() => Center(
    child: Icon(fallbackIcon, color: fallbackIconColor, size: fallbackIconSize),
  );
}
