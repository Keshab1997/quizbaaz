import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/services/app_update_service.dart';
import '../../data/services/app_version.dart';
import '../../data/services/update_banner_target.dart';
import '../../l10n/app_strings.dart';
import '../app_navigator.dart';
import 'glass_card.dart';
import 'neon_button.dart';

/// Top-of-dashboard slide-in that replaced the old surprise "What's new"
/// modal. It never blocks the screen, can be dismissed with ×, and every
/// path through it lands on the Update Center — nothing closes the app or
/// hijacks the session.
///
/// `whatsNew` reads as "look what changed", `availableUpdate` as "a new
/// bundle is waiting"; both are driven by [AppUpdateService], which the
/// dashboard's readiness check updates.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  // The entrance animation needs the widget mounted hidden first: the
  // post-frame flip from false to true is what AnimatedSlide/AnimatedOpacity
  // then animate. A dismissed banner unmounts (SizedBox.shrink) — exiting is
  // instant on purpose, the player asked for it to go.
  bool _entered = false;

  void _scheduleEnter(bool shouldEnter) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _entered == shouldEnter) return;
      setState(() => _entered = shouldEnter);
    });
  }

  void _openCenter(UpdateBannerTarget target) {
    if (target == UpdateBannerTarget.whatsNew) {
      unawaited(AppUpdateService.instance.markChangelogSeen());
    } else {
      unawaited(AppUpdateService.instance.dismissBanner());
    }
    AppNavigator.handleOpen('app_update');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppUpdateService.instance,
      builder: (context, _) {
        final target = AppUpdateService.instance.banner;
        if (target == UpdateBannerTarget.none) {
          _scheduleEnter(false);
          return const SizedBox.shrink();
        }
        _scheduleEnter(true);

        return AnimatedSlide(
          offset: _entered ? Offset.zero : const Offset(0, -1.2),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _entered ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: _card(context, target),
          ),
        );
      },
    );
  }

  Widget _card(BuildContext context, UpdateBannerTarget target) {
    final isWhatsNew = target == UpdateBannerTarget.whatsNew;
    final title =
        isWhatsNew
            ? S.whatsNewTitle(v: AppVersion.instance.version)
            : S.updateBannerAvailableTitle;
    final body =
        isWhatsNew ? S.updateBannerChangelogBody : S.updateBannerAvailableBody;
    final cta =
        isWhatsNew ? S.updateBannerCtaWhatsNew : S.updateBannerCtaUpdate;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 4),
      borderRadius: 18,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      borderColor: (isWhatsNew ? AppColors.neonGold : AppColors.neonCyan)
          .withValues(alpha: 0.45),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            isWhatsNew
                ? Icons.auto_awesome_rounded
                : Icons.system_update_rounded,
            color: isWhatsNew ? AppColors.neonGold : AppColors.neonCyan,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openCenter(target),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          NeonButton(
            text: cta,
            height: 34,
            borderRadius: 12,
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
            onPressed: () => _openCenter(target),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppColors.textMuted,
            ),
            onPressed: () {
              unawaited(AppUpdateService.instance.dismissBanner());
            },
          ),
        ],
      ),
    );
  }
}
