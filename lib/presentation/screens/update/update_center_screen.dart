import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_links.dart';
import '../../../data/services/app_update_service.dart';
import '../../../data/services/app_version.dart';
import '../../../data/services/play_update_info.dart';
import '../../../data/services/whats_new_catalog.dart';
import '../../../l10n/app_strings.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/neon_button.dart';
import '../../widgets/whats_new_dialog.dart';

enum _Phase { loading, idle, downloading, downloaded }

/// The one place an update is explained and started.
///
/// Reached from three doors — the dashboard banner, a push with
/// `open: app_update`, and an inbox row tap — and it always answers the same
/// two questions: *what changed* (this build's notes, straight from
/// [WhatsNewCatalog]) and *how do I update* (flexible in-app download when
/// Play offers one, Play Store otherwise). Nothing here restarts the app
/// without an explicit "Restart & update" tap.
class UpdateCenterScreen extends StatefulWidget {
  const UpdateCenterScreen({super.key});

  @override
  State<UpdateCenterScreen> createState() => _UpdateCenterScreenState();
}

class _UpdateCenterScreenState extends State<UpdateCenterScreen> {
  _Phase _phase = _Phase.loading;
  PlayUpdateInfo _info = const PlayUpdateInfo.none();
  bool _failed = false;
  bool _busy = false;
  List<String> _bullets = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await AppVersion.load();
    final info = await AppUpdateService.playAvailability();
    if (!mounted) return;
    setState(() {
      _info = info;
      _phase = _Phase.idle;
      _bullets = WhatsNewCatalog.bulletsFor(AppVersion.instance.version);
    });
    // Opening this screen counts as having seen the changelog — same as
    // dismissing the old dialog, so the banner does not come back.
    await AppUpdateService.instance.markChangelogSeen();
  }

  Future<void> _startUpdate() async {
    if (_phase != _Phase.idle) return;
    setState(() {
      _phase = _Phase.downloading;
      _failed = false;
    });
    final err = await AppUpdateService.startFlexibleUpdate();
    if (!mounted) return;
    if (err == null) {
      setState(() => _phase = _Phase.downloaded);
    } else if (err == 'user_denied') {
      setState(() => _phase = _Phase.idle);
    } else {
      setState(() {
        _phase = _Phase.idle;
        _failed = true;
      });
    }
  }

  Future<void> _restart() async {
    // completeFlexibleUpdate restarts the app; a double tap must not fire it
    // twice while Play is still tearing the process down.
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final err = await AppUpdateService.completeUpdate();
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      setState(() => _failed = true);
    }
    // Success: Play restarts the app into the new version from here.
  }

  Future<void> _openPlayStore() async {
    // The store id lives only in AppLinks.playStore; reuse it for the
    // market:// intent and fall back to the https URL when Play is absent.
    final package = AppLinks.playStore.split('id=').last;
    try {
      final market = Uri.parse('market://details?id=$package');
      if (await launchUrl(market, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      // Fall through to the https link.
    }
    await launchUrl(
      Uri.parse(AppLinks.playStore),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final version = AppVersion.instance.label;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          S.updateCenterTitle,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _statusCard(version),
          const SizedBox(height: 14),
          _whatsNewCard(version),
          const SizedBox(height: 14),
          NeonButton(
            text: S.updateCenterOpenStore,
            height: 48,
            borderRadius: 14,
            onPressed: _openPlayStore,
          ),
        ],
      ),
    );
  }

  Widget _statusCard(String version) {
    if (_phase == _Phase.loading) {
      return const GlassCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: CircularProgressIndicator(
              color: AppColors.neonCyan,
              strokeWidth: 2.5,
            ),
          ),
        ),
      );
    }

    final available = _info.updateAvailable;
    final downloaded = _phase == _Phase.downloaded;
    final downloading = _phase == _Phase.downloading;

    return GlassCard(
      borderColor: (available ? AppColors.neonCyan : AppColors.neonPurple)
          .withValues(alpha: 0.32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                available
                    ? (downloaded
                        ? Icons.download_done_rounded
                        : Icons.system_update_rounded)
                    : Icons.check_circle_rounded,
                color: available ? AppColors.neonCyan : AppColors.neonPurple,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  available
                      ? S.updateCenterAvailableTitle
                      : S.updateCenterUpToDate,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            available
                ? (downloaded
                    ? S.updateCenterDownloadedBody
                    : S.updateCenterAvailableBody)
                : '${S.updateCenterInstalled(v: version)} — ${S.updateCenterUpToDateBody}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (available &&
              !downloaded &&
              _info.flexibleAllowed &&
              !downloading) ...[
            const SizedBox(height: 14),
            NeonButton(
              text: S.updateCenterUpdateNow,
              height: 46,
              borderRadius: 14,
              onPressed: _startUpdate,
            ),
          ],
          if (downloading) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: AppColors.neonCyan,
                    strokeWidth: 2,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  S.updateCenterDownloading,
                  style: const TextStyle(
                    color: AppColors.neonCyan,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
          if (downloaded && !downloading) ...[
            const SizedBox(height: 14),
            NeonButton(
              text: S.updateCenterRestartNow,
              height: 46,
              borderRadius: 14,
              onPressed: _restart,
            ),
          ],
          if (_failed) ...[
            const SizedBox(height: 10),
            Text(
              S.updateCenterUpdateFailed,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.neonRed,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _whatsNewCard(String version) {
    return GlassCard(
      child: Column(
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
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          if (_bullets.isEmpty)
            Text(
              S.updateCenterNoNotes,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            )
          else
            WhatsNewDialog.bulletList(_bullets),
        ],
      ),
    );
  }
}
