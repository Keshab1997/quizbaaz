import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../l10n/app_strings.dart';
import 'glass_card.dart';
import 'neon_button.dart';

/// First-open-after-update sheet. Copy comes from [WhatsNewCatalog], never
/// invented at the call site.
class WhatsNewDialog {
  WhatsNewDialog._();

  static Future<void> show(
    BuildContext context, {
    required String version,
    required List<String> bullets,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WhatsNewBody(version: version, bullets: bullets),
    );
  }
}

class _WhatsNewBody extends StatelessWidget {
  const _WhatsNewBody({required this.version, required this.bullets});

  final String version;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: GlassCard(
        borderRadius: 24,
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        borderColor: AppColors.neonCyan.withValues(alpha: 0.35),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              S.whatsNewEyebrow,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.neonCyan,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              S.whatsNewTitle(v: version),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final line in bullets)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Icon(
                                Icons.auto_awesome_rounded,
                                size: 14,
                                color: AppColors.neonGold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                line,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            NeonButton(
              text: S.whatsNewGotIt,
              height: 44,
              borderRadius: 14,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
