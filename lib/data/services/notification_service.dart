import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../l10n/app_strings.dart';
import '../models/champion_model.dart';
import '../models/notification_item.dart';
import 'hive_service.dart';
import 'notification_inbox.dart';
import 'notification_planner.dart';
import 'notification_winner_sync.dart';

/// Resolved copy + metadata for one scheduled local notification.
class ScheduledNotificationCopy {
  final String title;
  final String body;
  final String kind;
  final String channelId;
  final String channelName;
  final String channelDesc;

  const ScheduledNotificationCopy({
    required this.title,
    required this.body,
    required this.kind,
    required this.channelId,
    required this.channelName,
    required this.channelDesc,
  });
}

/// OS-scheduled local notifications for QuizBaaz:
/// - Yesterday's Daily Quiz Winner reveal (08:15)
/// - Morning Daily Quiz kickoff (10:00)
/// - Afternoon engagement hook: Mistake Notebook / 1v1 Battle / Practice / Chapters (16:00)
/// - Evening Daily Quiz prime reminder (19:00)
/// - Last-chance streak rescue while an active streak is at risk (21:30)
///
/// All public methods are safe to fire-and-forget: they no-op on web /
/// desktop, swallow plugin errors, and must never be `await`ed before
/// `runApp` (see AGENTS.md §3).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _channelRemindersId = 'quizbaaz_daily_reminders';
  static const _channelWinnersId = 'quizbaaz_winner_alerts';
  static const _channelEngageId = 'quizbaaz_engage_prompts';

  /// Hive keys — same strings [UserProvider] already persists.
  static const settingNotifications = 'setting_notifications';
  static const settingVibration = 'setting_vibration';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  /// Set from `main.dart` to [AppNavigator.handleOpen]. Kept as a callback
  /// so this service never imports presentation.
  static void Function(String? open)? onNotificationOpen;

  String? _lastHandledKey;
  DateTime? _lastHandledAt;

  /// Android + iOS only. Everywhere else the calls below are no-ops.
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

  /// After the first frame: init the plugin, ask for permission if the
  /// setting is on, then (re)build the multi-slot local schedule.
  Future<void> bootstrap() async {
    if (!isSupported) return;
    try {
      await _ensureReady().timeout(const Duration(seconds: 5));
      await syncFromHive();
    } catch (e) {
      debugPrint('NotificationService: bootstrap failed – $e');
    }
  }

  /// Rebuilds the reminder window from Hive. Language, settings, winner
  /// resolution, and finished quizzes all land here so we never import
  /// [UserProvider] (that would cycle).
  Future<void> syncFromHive() async {
    if (!isSupported) return;
    final enabled = HiveService.getMeta<bool>(settingNotifications) ?? true;
    final vibrate = HiveService.getMeta<bool>(settingVibration) ?? false;
    final user = HiveService.loadUser();
    final now = DateTime.now();
    user?.refreshDailyFlags(now);
    final mistakeCount =
        HiveService.isInitialized ? HiveService.mistakeQuestionCount() : 0;
    final cachedChampions =
        HiveService.isInitialized
            ? HiveService.cacheGetList(
              HiveService.cacheChampions,
            ).map(ChampionModel.fromJson).toList()
            : const <ChampionModel>[];
    final yesterdayWinner = NotificationWinnerSync.findYesterdayTopChampion(
      cachedChampions,
      now: now,
    );

    await sync(
      enabled: enabled,
      playedToday: user?.playedTodayDailyQuiz ?? false,
      streak: user?.dailyStreak ?? 0,
      vibrate: vibrate,
      mistakeCount: mistakeCount,
      todayWinnerAnnounced: NotificationWinnerSync.isAnnouncedForYesterday(now),
      yesterdayWinner: yesterdayWinner,
    );
  }

  Future<void> sync({
    required bool enabled,
    required bool playedToday,
    required int streak,
    required bool vibrate,
    int mistakeCount = 0,
    bool todayWinnerAnnounced = false,
    ChampionModel? yesterdayWinner,
  }) async {
    if (!isSupported) return;
    try {
      await _ensureReady();
      if (!enabled) {
        await _plugin.cancelAll();
        return;
      }
      final allowed = await requestPermission();
      if (!allowed) {
        await _plugin.cancelAll();
        return;
      }
      await _plugin.cancelAll();
      await _scheduleWindow(
        playedToday: playedToday,
        streak: streak,
        vibrate: vibrate,
        mistakeCount: mistakeCount,
        todayWinnerAnnounced: todayWinnerAnnounced,
        yesterdayWinner: yesterdayWinner,
      );
    } catch (e) {
      debugPrint('NotificationService: sync failed – $e');
    }
  }

  /// Android 13+ / iOS runtime prompt. Returns true when we may post.
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    try {
      await _ensureReady();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android =
            _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >();
        final granted = await android?.requestNotificationsPermission();
        return granted ?? true;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios =
            _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >();
        final granted = await ios?.requestPermissions(
          alert: true,
          badge: false,
          sound: true,
        );
        return granted ?? false;
      }
    } catch (e) {
      debugPrint('NotificationService: permission failed – $e');
      return false;
    }
    return false;
  }

  Future<void> _ensureReady() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    final id = await _localTimezoneId();
    try {
      tz.setLocalLocation(tz.getLocation(id));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: _onTap,
    );
    _ready = true;

    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && response != null) {
        _onTap(response);
      }
    } catch (e) {
      debugPrint('NotificationService: launch details – $e');
    }
  }

  /// OS tap (foreground, background, or cold start). Deduped because some
  /// devices also deliver [getNotificationAppLaunchDetails] for the same tap.
  void _onTap(NotificationResponse response) {
    final key = '${response.id}|${response.payload}';
    final now = DateTime.now();
    if (_lastHandledKey == key &&
        _lastHandledAt != null &&
        now.difference(_lastHandledAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastHandledKey = key;
    _lastHandledAt = now;

    final user = HiveService.loadUser();
    user?.refreshDailyFlags(now);
    final streak = user?.dailyStreak ?? 0;
    final mistakeCount =
        HiveService.isInitialized ? HiveService.mistakeQuestionCount() : 0;
    final slot = NotificationPlanner.slotFromNotificationId(response.id);
    final open = response.payload;

    final copy = copyForTap(
      slot: slot,
      open: open,
      streak: streak,
      mistakeCount: mistakeCount,
      dayIndex: now.day,
      yesterdayWinner:
          HiveService.isInitialized
              ? NotificationWinnerSync.findYesterdayTopChampion(
                HiveService.cacheGetList(
                  HiveService.cacheChampions,
                ).map(ChampionModel.fromJson).toList(),
                now: now,
              )
              : null,
    );

    final id =
        response.id != null
            ? 'local_${response.id}'
            : 'local_${open ?? now.millisecondsSinceEpoch}';
    unawaited(
      NotificationInbox.instance.add(
        NotificationItem(
          id: id,
          kind: copy.kind,
          title: copy.title,
          body: copy.body,
          open: open,
          receivedAt: now,
        ),
      ),
    );
    onNotificationOpen?.call(open);
  }

  Future<String> _localTimezoneId() async {
    try {
      final dynamic result = await FlutterTimezone.getLocalTimezone();
      if (result is String && result.isNotEmpty) return result;
      final id = result.identifier;
      if (id is String && id.isNotEmpty) return id;
    } catch (e) {
      debugPrint('NotificationService: timezone plugin – $e');
    }
    return 'Asia/Kolkata';
  }

  Future<void> _scheduleWindow({
    required bool playedToday,
    required int streak,
    required bool vibrate,
    required int mistakeCount,
    required bool todayWinnerAnnounced,
    required ChampionModel? yesterdayWinner,
  }) async {
    final planned = NotificationPlanner.planSchedule(
      now: DateTime.now(),
      playedToday: playedToday,
      streak: streak,
      mistakeCount: mistakeCount,
      todayWinnerAnnounced: todayWinnerAnnounced,
    );

    const darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: false,
    );

    for (final item in planned) {
      final copy = copyForPlanned(
        item,
        streak: streak,
        mistakeCount: mistakeCount,
        yesterdayWinner: yesterdayWinner,
      );
      final android = AndroidNotificationDetails(
        copy.channelId,
        copy.channelName,
        channelDescription: copy.channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: vibrate,
        icon: '@mipmap/ic_launcher',
      );
      final details = NotificationDetails(android: android, iOS: darwin);
      final when = item.scheduledAt;
      final scheduled = tz.TZDateTime(
        tz.local,
        when.year,
        when.month,
        when.day,
        when.hour,
        when.minute,
      );
      await _plugin.zonedSchedule(
        id: item.id,
        title: copy.title,
        body: copy.body,
        scheduledDate: scheduled,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: item.open,
      );
    }
  }

  /// Resolves localized title/body/channel for a planned schedule entry.
  static ScheduledNotificationCopy copyForPlanned(
    PlannedNotification item, {
    required int streak,
    int mistakeCount = 0,
    ChampionModel? yesterdayWinner,
  }) {
    return _resolveCopy(
      slot: item.slot,
      dayIndex: item.dayIndex,
      engageTopic: item.engageTopic,
      streak: streak,
      mistakeCount: mistakeCount,
      yesterdayWinner: item.dayIndex == 0 ? yesterdayWinner : null,
    );
  }

  /// Resolves localized title/body/kind when an OS notification is tapped.
  static ScheduledNotificationCopy copyForTap({
    NotificationSlot? slot,
    String? open,
    required int streak,
    required int mistakeCount,
    int dayIndex = 0,
    ChampionModel? yesterdayWinner,
  }) {
    final resolvedSlot = slot ?? _inferSlotFromOpen(open);
    final topic = _inferTopicFromOpen(open);
    return _resolveCopy(
      slot: resolvedSlot,
      dayIndex: dayIndex,
      engageTopic: topic,
      streak: streak,
      mistakeCount: mistakeCount,
      yesterdayWinner:
          resolvedSlot == NotificationSlot.winnerReveal
              ? yesterdayWinner
              : null,
    );
  }

  static NotificationSlot _inferSlotFromOpen(String? open) {
    switch (open) {
      case 'winners':
        return NotificationSlot.winnerReveal;
      case 'battle':
      case 'online_battle':
      case 'practice':
      case 'chapters':
      case 'mistake_quiz':
        return NotificationSlot.afternoonEngage;
      default:
        return NotificationSlot.eveningPrime;
    }
  }

  static EngageTopic _inferTopicFromOpen(String? open) {
    switch (open) {
      case 'mistake_quiz':
        return EngageTopic.mistakeRevision;
      case 'battle':
      case 'online_battle':
        return EngageTopic.battleArena;
      case 'practice':
        return EngageTopic.freePractice;
      case 'chapters':
        return EngageTopic.chapterChallenge;
      default:
        return EngageTopic.battleArena;
    }
  }

  static ScheduledNotificationCopy _resolveCopy({
    required NotificationSlot slot,
    required int dayIndex,
    required EngageTopic? engageTopic,
    required int streak,
    required int mistakeCount,
    ChampionModel? yesterdayWinner,
  }) {
    switch (slot) {
      case NotificationSlot.winnerReveal:
        final winnerName =
            yesterdayWinner != null
                ? NotificationWinnerSync.displayNameFor(yesterdayWinner)
                : '';
        final hasRealWinner = yesterdayWinner != null && winnerName.isNotEmpty;
        return ScheduledNotificationCopy(
          title:
              hasRealWinner
                  ? S.notifWinnerTitle(name: winnerName)
                  : S.notifWinnerMorningTitle,
          body:
              hasRealWinner
                  ? S.notifWinnerBody(score: yesterdayWinner.score)
                  : S.notifWinnerMorningBody,
          kind: NotificationItem.kindWinner,
          channelId: _channelWinnersId,
          channelName: S.notifChannelWinnersName,
          channelDesc: S.notifChannelWinnersDesc,
        );

      case NotificationSlot.morningKickoff:
        if (streak > 0) {
          return ScheduledNotificationCopy(
            title: S.notifMorningStreakTitle(n: streak),
            body: S.notifMorningStreakBody,
            kind: NotificationItem.kindReminder,
            channelId: _channelRemindersId,
            channelName: S.notifChannelName,
            channelDesc: S.notifChannelDesc,
          );
        }
        switch (dayIndex % 3) {
          case 1:
            return ScheduledNotificationCopy(
              title: S.notifMorningTitle2,
              body: S.notifMorningBody2,
              kind: NotificationItem.kindReminder,
              channelId: _channelRemindersId,
              channelName: S.notifChannelName,
              channelDesc: S.notifChannelDesc,
            );
          case 2:
            return ScheduledNotificationCopy(
              title: S.notifMorningTitle3,
              body: S.notifMorningBody3,
              kind: NotificationItem.kindReminder,
              channelId: _channelRemindersId,
              channelName: S.notifChannelName,
              channelDesc: S.notifChannelDesc,
            );
          default:
            return ScheduledNotificationCopy(
              title: S.notifMorningTitle1,
              body: S.notifMorningBody1,
              kind: NotificationItem.kindReminder,
              channelId: _channelRemindersId,
              channelName: S.notifChannelName,
              channelDesc: S.notifChannelDesc,
            );
        }

      case NotificationSlot.afternoonEngage:
        final topic = engageTopic ?? EngageTopic.battleArena;
        switch (topic) {
          case EngageTopic.mistakeRevision:
            final count = mistakeCount > 0 ? mistakeCount : 1;
            return ScheduledNotificationCopy(
              title: S.notifMistakeTitle(n: count),
              body: S.notifMistakeBody,
              kind: NotificationItem.kindEngage,
              channelId: _channelEngageId,
              channelName: S.notifChannelEngageName,
              channelDesc: S.notifChannelEngageDesc,
            );
          case EngageTopic.battleArena:
            return ScheduledNotificationCopy(
              title: S.notifBattleTitle,
              body: S.notifBattleBody,
              kind: NotificationItem.kindEngage,
              channelId: _channelEngageId,
              channelName: S.notifChannelEngageName,
              channelDesc: S.notifChannelEngageDesc,
            );
          case EngageTopic.freePractice:
            return ScheduledNotificationCopy(
              title: S.notifPracticeTitle,
              body: S.notifPracticeBody,
              kind: NotificationItem.kindEngage,
              channelId: _channelEngageId,
              channelName: S.notifChannelEngageName,
              channelDesc: S.notifChannelEngageDesc,
            );
          case EngageTopic.chapterChallenge:
            return ScheduledNotificationCopy(
              title: S.notifChapterTitle,
              body: S.notifChapterBody,
              kind: NotificationItem.kindEngage,
              channelId: _channelEngageId,
              channelName: S.notifChannelEngageName,
              channelDesc: S.notifChannelEngageDesc,
            );
        }

      case NotificationSlot.eveningPrime:
        if (streak > 0) {
          return ScheduledNotificationCopy(
            title: S.notifStreakTitle,
            body: S.notifStreakBody(n: streak),
            kind: NotificationItem.kindReminder,
            channelId: _channelRemindersId,
            channelName: S.notifChannelName,
            channelDesc: S.notifChannelDesc,
          );
        }
        switch (dayIndex % 3) {
          case 1:
            return ScheduledNotificationCopy(
              title: S.notifDailyTitle2,
              body: S.notifDailyBody2,
              kind: NotificationItem.kindReminder,
              channelId: _channelRemindersId,
              channelName: S.notifChannelName,
              channelDesc: S.notifChannelDesc,
            );
          case 2:
            return ScheduledNotificationCopy(
              title: S.notifDailyTitle3,
              body: S.notifDailyBody3,
              kind: NotificationItem.kindReminder,
              channelId: _channelRemindersId,
              channelName: S.notifChannelName,
              channelDesc: S.notifChannelDesc,
            );
          default:
            return ScheduledNotificationCopy(
              title: S.notifDailyTitle,
              body: S.notifDailyBody,
              kind: NotificationItem.kindReminder,
              channelId: _channelRemindersId,
              channelName: S.notifChannelName,
              channelDesc: S.notifChannelDesc,
            );
        }

      case NotificationSlot.streakRescue:
        final safeStreak = streak > 0 ? streak : 1;
        return ScheduledNotificationCopy(
          title: S.notifRescueTitle(n: safeStreak),
          body: S.notifRescueBody,
          kind: NotificationItem.kindReminder,
          channelId: _channelRemindersId,
          channelName: S.notifChannelName,
          channelDesc: S.notifChannelDesc,
        );
    }
  }
}
