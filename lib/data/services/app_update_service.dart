import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../presentation/widgets/whats_new_dialog.dart';
import 'app_update_play_stub.dart'
    if (dart.library.io) 'app_update_play_io.dart';
import 'app_version.dart';
import 'hive_service.dart';
import 'play_update_info.dart';
import 'update_banner_target.dart';
import 'whats_new_catalog.dart';

/// Play in-app updates + the post-update "What's new" entry point.
///
/// This service never shows UI on its own — it only decides *what the
/// dashboard banner should offer* and remembers what the player has already
/// seen. Two old behaviours were deliberately removed:
///
///  * the modal What's-new dialog popping up out of nowhere a few seconds
///    after the dashboard loaded (the player is mid-scroll and has no idea
///    it is coming), and
///  * `performImmediateUpdate()` running from the readiness check, which
///    killed the app the moment Play reported a bundle.
///
/// Banner targets:
///
///  * [UpdateBannerTarget.whatsNew] — first launch after an update: the
///    banner opens the Update Center with this build's notes.
///  * [UpdateBannerTarget.availableUpdate] — Play has a newer bundle: the
///    Update Center downloads only when the player taps Update.
class AppUpdateService extends ChangeNotifier {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const metaLastSeenVersion = 'last_seen_version';

  /// Version code the player pressed "later" on, so the available-update
  /// banner nags exactly once per bundle.
  static const metaDismissedUpdateCode = 'update_banner_dismissed_vc';

  UpdateBannerTarget _banner = UpdateBannerTarget.none;
  UpdateBannerTarget get banner => _banner;

  PlayUpdateInfo _play = const PlayUpdateInfo.none();

  /// Latest Play availability (kept for the Update Center CTA).
  PlayUpdateInfo get play => _play;

  /// Pure decision, exposed for unit tests: does this install owe the
  /// player a "what's new" banner?
  static bool shouldOfferChangelog({
    required String? lastSeenVersion,
    required String currentVersion,
    required List<String> bullets,
  }) {
    if (currentVersion.isEmpty || bullets.isEmpty) return false;
    // Fresh install — don't lecture a new student about an "update".
    if (lastSeenVersion == null) return false;
    return lastSeenVersion != currentVersion;
  }

  /// Ask Play for a newer bundle, then decide the banner. Called from the
  /// dashboard once it is ready (the slot the old auto-dialog used) —
  /// streak / reward dialogs run before it, never after.
  Future<void> checkAfterDashboardReady() async {
    await AppVersion.load();
    final current = AppVersion.instance.version;

    _play = await checkPlayUpdate();
    if (_play.updateAvailable && _play.availableVersionCode > 0) {
      final dismissed = HiveService.getMeta<int>(metaDismissedUpdateCode) ?? 0;
      if (_play.availableVersionCode > dismissed) {
        _setBanner(UpdateBannerTarget.availableUpdate);
        return;
      }
    }

    final lastSeen = HiveService.getMeta<String>(metaLastSeenVersion);
    final bullets = WhatsNewCatalog.bulletsFor(current);
    if (shouldOfferChangelog(
      lastSeenVersion: lastSeen,
      currentVersion: current,
      bullets: bullets,
    )) {
      _setBanner(UpdateBannerTarget.whatsNew);
      return;
    }

    // An update with no notes recorded (or already seen): mark it handled so
    // we stop re-checking, exactly like the old dialog did.
    if (lastSeen != null && lastSeen != current && current.isNotEmpty) {
      await HiveService.setMeta(metaLastSeenVersion, current);
    }
    _setBanner(UpdateBannerTarget.none);
  }

  /// Banner closed (×) or an available-update banner navigated away from:
  /// remember the choice so it stops sliding in. The changelog itself stays
  /// reachable from Profile → version row either way.
  ///
  /// The banner hides on the same tick as the tap — persistence follows, so
  /// a slow Hive write never keeps a dismissed banner on screen.
  Future<void> dismissBanner() async {
    final target = _banner;
    final dismissedCode = _play.availableVersionCode;
    _setBanner(UpdateBannerTarget.none);
    if (target == UpdateBannerTarget.whatsNew) {
      await _markCurrentSeen();
    } else if (target == UpdateBannerTarget.availableUpdate &&
        dismissedCode > 0) {
      await HiveService.setMeta(metaDismissedUpdateCode, dismissedCode);
    }
  }

  /// The Update Center showed this build's notes — same as having seen the
  /// changelog dialog.
  Future<void> markChangelogSeen() async {
    if (_banner == UpdateBannerTarget.whatsNew) {
      _setBanner(UpdateBannerTarget.none);
    }
    await _markCurrentSeen();
  }

  Future<void> _markCurrentSeen() async {
    final current = AppVersion.instance.version;
    if (current.isNotEmpty) {
      await HiveService.setMeta(metaLastSeenVersion, current);
    }
  }

  void _setBanner(UpdateBannerTarget next) {
    if (_banner == next) return;
    _banner = next;
    notifyListeners();
  }

  /// Test-only: drop in-memory state so a later call starts clean. Notifies
  /// like any other state change so widget tests can observe the reset.
  @visibleForTesting
  void debugReset() {
    _banner = UpdateBannerTarget.none;
    _play = const PlayUpdateInfo.none();
    notifyListeners();
  }

  /// Play availability, wrapped so only this file ever holds the conditional
  /// io/stub import — screens talk to the service, never to the backend.
  static Future<PlayUpdateInfo> playAvailability() => checkPlayUpdate();

  /// Starts the flexible download; null on success (see the io backend for
  /// the `user_denied` / error line contract).
  static Future<String?> startFlexibleUpdate() => startFlexiblePlayUpdate();

  /// Installs the downloaded bundle (restarts the app — user tap only).
  static Future<String?> completeUpdate() => completePlayUpdate();

  static String versionLine() {
    final label = AppVersion.instance.label;
    return label.isEmpty
        ? S.profileVersion(v: '…')
        : S.profileVersion(v: label);
  }

  /// Profile → version row: re-show this build's notes on demand. A
  /// deliberate open, so the modal dialog is appropriate here.
  static Future<void> showChangelog(BuildContext context) async {
    await AppVersion.load();
    final current = AppVersion.instance.version;
    final bullets = WhatsNewCatalog.bulletsFor(current);
    if (!context.mounted) return;
    if (bullets.isEmpty) return;
    await WhatsNewDialog.show(context, version: current, bullets: bullets);
  }
}
