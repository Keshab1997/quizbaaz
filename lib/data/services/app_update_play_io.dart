import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

import 'play_update_info.dart';

/// Android Play in-app update. Other platforms return
/// [PlayUpdateInfo.none]. Fail-soft everywhere — a missing Play Store must
/// never block the dashboard.
///
/// This file used to chain `performImmediateUpdate()` inside the availability
/// check, so the moment Play reported a bundle the app died mid-scroll. It is
/// now strictly three quiet operations: ask, download on the player's tap,
/// install only when they explicitly choose "Restart & update".
Future<PlayUpdateInfo> checkPlayUpdate() async {
  if (!Platform.isAndroid) return const PlayUpdateInfo.none();
  try {
    final info = await InAppUpdate.checkForUpdate();
    return PlayUpdateInfo(
      updateAvailable:
          info.updateAvailability == UpdateAvailability.updateAvailable,
      flexibleAllowed: info.flexibleUpdateAllowed,
      availableVersionCode: info.availableVersionCode ?? 0,
    );
  } catch (e) {
    debugPrint('AppUpdateService: Play update check skipped – $e');
    return const PlayUpdateInfo.none();
  }
}

/// Starts the flexible download (Play shows its own progress UI).
/// Resolves once the bundle is downloaded; nothing installs yet.
///
/// Returns null on success, otherwise a short error line for the UI
/// (`userDeniedUpdate` is not an error the player should see as a failure —
/// the call site treats it as a silent cancel).
Future<String?> startFlexiblePlayUpdate() async {
  if (!Platform.isAndroid) return 'Play in-app update unavailable here';
  try {
    final result = await InAppUpdate.startFlexibleUpdate();
    if (result == AppUpdateResult.success) return null;
    if (result == AppUpdateResult.userDeniedUpdate) return 'user_denied';
    return 'in_app_update_failed';
  } catch (e) {
    debugPrint('AppUpdateService: flexible download failed – $e');
    return '$e';
  }
}

/// Installs the downloaded bundle. The app process restarts as part of the
/// install, so this must only ever run after an explicit player tap.
Future<String?> completePlayUpdate() async {
  if (!Platform.isAndroid) return 'Play in-app update unavailable here';
  try {
    await InAppUpdate.completeFlexibleUpdate();
    return null;
  } catch (e) {
    debugPrint('AppUpdateService: completing the update failed – $e');
    return '$e';
  }
}
