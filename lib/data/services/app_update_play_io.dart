import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// Android Play in-app update. Other platforms no-op.
Future<bool> promptPlayUpdate() async {
  if (!Platform.isAndroid) return false;
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
