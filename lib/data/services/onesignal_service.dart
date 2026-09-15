import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import '../../core/constants/onesignal_config.dart';
import '../../l10n/app_strings.dart';
import '../models/notification_item.dart';
import 'hive_service.dart';
import 'notification_inbox.dart';
import 'notification_service.dart';

/// OneSignal client. Android delivery still goes through FCM; we never
/// talk to FCM ourselves (`firebase_messaging` is not a dependency).
///
/// Safe to fire-and-forget. No-ops when [OneSignalConfig.appId] is empty,
/// on web/desktop, or when the plugin is missing (widget tests).
/// Must never be `await`ed before `runApp`.
class OneSignalService {
  OneSignalService._();
  static final OneSignalService instance = OneSignalService._();

  bool _ready = false;
  bool _clickBound = false;
  bool _foregroundBound = false;

  /// Set from `main.dart` to [AppNavigator.handleOpen]. Kept as a callback
  /// so this service never imports presentation.
  static void Function(String? open)? onNotificationOpen;

  static bool get isSupported {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return true;
      default:
        return false;
    }
  }

  /// Initialise the SDK and the click listener. Call right after `runApp`
  /// so a notification that launched a killed app still has a listener.
  Future<void> bootstrap() async {
    if (!isSupported || !OneSignalConfig.isConfigured) return;
    try {
      await _ensureReady().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('OneSignalService: bootstrap failed – $e');
    }
  }

  /// Login, tags, and opt-in/out from Hive + Firebase. Called whenever
  /// the local reminder window is rebuilt.
  Future<void> syncFromHive() async {
    if (!isSupported || !OneSignalConfig.isConfigured) return;
    try {
      await _ensureReady();
      final enabled =
          HiveService.getMeta<bool>(NotificationService.settingNotifications) ??
              true;
      if (enabled) {
        await OneSignal.Notifications.requestPermission(false);
        await OneSignal.User.pushSubscription.optIn();
      } else {
        await OneSignal.User.pushSubscription.optOut();
        return;
      }

      final externalId = _externalId();
      if (externalId != null && externalId.isNotEmpty) {
        await OneSignal.login(externalId);
      }

      final user = HiveService.loadUser();
      user?.refreshDailyFlags(DateTime.now());
      await OneSignal.User.setLanguage(S.code);
      await OneSignal.User.addTags({
        'lang': S.code,
        'guest': (user?.isGuest ?? true) ? 'true' : 'false',
        'streak': '${user?.dailyStreak ?? 0}',
        'played_today': (user?.playedTodayDailyQuiz ?? false) ? 'true' : 'false',
      });
    } catch (e) {
      debugPrint('OneSignalService: sync failed – $e');
    }
  }

  Future<void> logout() async {
    if (!isSupported || !OneSignalConfig.isConfigured || !_ready) return;
    try {
      await OneSignal.logout();
    } catch (e) {
      debugPrint('OneSignalService: logout failed – $e');
    }
  }

  Future<void> _ensureReady() async {
    if (_ready) return;
    OneSignal.initialize(OneSignalConfig.appId);
    if (!_clickBound) {
      _clickBound = true;
      OneSignal.Notifications.addClickListener(_onClick);
    }
    if (!_foregroundBound) {
      _foregroundBound = true;
      OneSignal.Notifications.addForegroundWillDisplayListener(_onForeground);
    }
    _ready = true;
  }

  void _onForeground(OSNotificationWillDisplayEvent event) {
    try {
      _record(event.notification);
    } catch (e) {
      debugPrint('OneSignalService: foreground handler – $e');
    }
  }

  void _onClick(OSNotificationClickEvent event) {
    try {
      _record(event.notification);
      final data = event.notification.additionalData;
      final open = data == null ? null : data['open']?.toString();
      onNotificationOpen?.call(open);
    } catch (e) {
      debugPrint('OneSignalService: click handler – $e');
    }
  }

  void _record(OSNotification n) {
    final title = (n.title ?? '').trim();
    final body = (n.body ?? '').trim();
    if (title.isEmpty && body.isEmpty) return;
    final data = n.additionalData;
    final open = data == null ? null : data['open']?.toString();
    unawaited(NotificationInbox.instance.add(NotificationItem(
      id: 'os_${n.notificationId}',
      kind: NotificationItem.kindPush,
      title: title.isEmpty ? S.appTitle : title,
      body: body,
      open: (open == null || open.isEmpty) ? null : open,
      receivedAt: DateTime.now(),
    )));
  }

  /// Prefer the Firebase uid so a reinstall still maps to the same player.
  /// Guests fall back to the Hive local id.
  String? _externalId() {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) return uid;
    } catch (_) {}
    return HiveService.loadUser()?.userId;
  }
}
