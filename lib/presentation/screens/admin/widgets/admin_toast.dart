import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

/// A top-of-screen toast for admin feedback, replacing bottom SnackBars.
///
/// SnackBars misbehave in the admin flows: the messenger sits above the
/// Navigator, so a "chapter saved" notice lingers ~4 seconds and rides along
/// to whatever screen the admin opens next. This toast instead:
///
/// - slides down from the top, above the content (below the status bar),
/// - auto-dismisses (success/info 2.5 s, error 4 s, with-action 5 s),
/// - dismisses on tap,
/// - replaces any toast already showing instead of queuing behind it.
class AdminToast {
  AdminToast._();

  static OverlayEntry? _current;
  static Timer? _timer;

  /// Green check. Use for completed work: saved, added, deleted, copied.
  static void showSuccess(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) => show(
    context,
    message,
    accent: AppColors.neonGreen,
    icon: Icons.check_circle_rounded,
    actionLabel: actionLabel,
    onAction: onAction,
  );

  /// Red alert. Use for failures: the admin must notice these.
  static void showError(BuildContext context, String message) => show(
    context,
    message,
    accent: AppColors.neonRed,
    icon: Icons.error_outline_rounded,
    timeout: const Duration(seconds: 4),
  );

  /// Cyan info. Use for neutral notices: nothing to save, bundled content
  /// that cannot be deleted, hints.
  static void showInfo(BuildContext context, String message) => show(
    context,
    message,
    accent: AppColors.neonCyan,
    icon: Icons.info_outline_rounded,
  );

  static void show(
    BuildContext context,
    String message, {
    Color accent = AppColors.neonGreen,
    IconData icon = Icons.check_circle_rounded,
    Duration timeout = const Duration(milliseconds: 2500),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    hide();
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder:
          (_) => _ToastBanner(
            entry: entry,
            message: message,
            accent: accent,
            icon: icon,
            actionLabel: actionLabel,
            onAction: onAction,
            onDismiss: () => _dismissEntry(entry),
          ),
    );
    _current = entry;
    overlay.insert(entry);
    // An action (Undo) needs reading + aiming time.
    final wait = actionLabel == null ? timeout : const Duration(seconds: 5);
    _timer = Timer(wait, () => _dismissEntry(entry));
  }

  static void _dismissEntry(OverlayEntry entry) {
    if (_current != entry) return;
    hide();
  }

  /// Called by the banner itself when its overlay dies, so a stale entry is
  /// never removed twice (which trips an assert in debug builds).
  static void _release(OverlayEntry entry) {
    if (_current != entry) return;
    _timer?.cancel();
    _timer = null;
    _current = null;
  }

  static void hide() {
    _timer?.cancel();
    _timer = null;
    _current?.remove();
    _current = null;
  }
}

class _ToastBanner extends StatefulWidget {
  final OverlayEntry entry;
  final String message;
  final Color accent;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;

  const _ToastBanner({
    required this.entry,
    required this.message,
    required this.accent,
    required this.icon,
    required this.actionLabel,
    required this.onAction,
    required this.onDismiss,
  });

  @override
  State<_ToastBanner> createState() => _ToastBannerState();
}

class _ToastBannerState extends State<_ToastBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, -0.4),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    AdminToast._release(widget.entry);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: GestureDetector(
            onTap: widget.onDismiss,
            child: Material(
              color: AppColors.bgNavy,
              elevation: 8,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: widget.accent.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, color: widget.accent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.message,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                          height: 1.35,
                        ),
                      ),
                    ),
                    if (widget.actionLabel != null) ...[
                      const SizedBox(width: 6),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: const Size(0, 34),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
                          widget.onAction?.call();
                          widget.onDismiss();
                        },
                        child: Text(
                          widget.actionLabel!,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.neonGold,
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
