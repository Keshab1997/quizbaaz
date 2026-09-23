import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../presentation/widgets/whats_new_dialog.dart';
import 'app_update_play_stub.dart'
    if (dart.library.io) 'app_update_play_io.dart';
import 'app_version.dart';
import 'hive_service.dart';
import 'whats_new_catalog.dart';

/// Play in-app updates + first-launch-after-update "What's new".
///
/// Closed / internal / production tracks all work as long as the install
/// came from Play (sideloaded APKs are ignored by the Play API). Fail-soft
/// everywhere — a missing Play Store must never block the dashboard.
class AppUpdateService {
  AppUpdateService._();

  static const metaLastSeenVersion = 'last_seen_version';

  /// Ask Play for a newer bundle, then (if this install itself is new)
  /// show the What's new dialog. Streak / reward dialogs should run first.
  static Future<void> checkAfterDashboardReady(BuildContext context) async {
    await AppVersion.load();
    if (!context.mounted) return;

    final playTookOver = await _promptPlayUpdate();
    if (playTookOver) return;
    if (!context.mounted) return;

    await _showWhatsNewIfNeeded(context);
  }

  /// Returns true when Play is already showing its own update UI, so we
  /// should not stack another dialog on top.
  static Future<bool> _promptPlayUpdate() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return false;
      }
      if (info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
        return true;
      }
      if (info.flexibleUpdateAllowed) {
        await InAppUpdate.startFlexibleUpdate();
        await InAppUpdate.completeFlexibleUpdate();
        return true;
      }
    } catch (e) {
      debugPrint('AppUpdateService: Play in-app update skipped – $e');
    }
    return false;
  }

  static Future<void> _showWhatsNewIfNeeded(BuildContext context) async {
    final current = AppVersion.version;
    if (current.isEmpty) return;

    final last = HiveService.getMeta<String>(metaLastSeenVersion);
    if (last == null) {
      // Fresh install — don't lecture a new student about an "update".
      await HiveService.setMeta(metaLastSeenVersion, current);
      return;
    }
    if (last == current) return;

    final bullets = WhatsNewCatalog.bulletsFor(current);
    if (bullets.isEmpty) {
      await HiveService.setMeta(metaLastSeenVersion, current);
      return;
    }
    if (!context.mounted) return;

    await WhatsNewDialog.show(
      context,
      version: current,
      bullets: bullets,
    );
    await HiveService.setMeta(metaLastSeenVersion, current);
  }

  static String versionLine() {
    final label = AppVersion.label;
    return label.isEmpty ? S.profileVersion(v: '…') : S.profileVersion(v: label);
  }

  /// Profile → version row: re-show this build's notes on demand.
  static Future<void> showChangelog(BuildContext context) async {
    await AppVersion.load();
    final current = AppVersion.version;
    final bullets = WhatsNewCatalog.bulletsFor(current);
    if (!context.mounted) return;
    if (bullets.isEmpty) return;
    await WhatsNewDialog.show(
      context,
      version: current,
      bullets: bullets,
    );
  }
}
