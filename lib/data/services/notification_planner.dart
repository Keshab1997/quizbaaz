/// Pure date math for QuizBaaz's scheduled local notifications.
///
/// Kept free of Flutter and platform plugins so unit tests can pin [now]
/// without a device clock or timezone database.
enum NotificationSlot {
  /// 08:15 — Yesterday's Daily Quiz Winner announcement / podium check.
  winnerReveal,

  /// 10:00 — Fresh Daily Quiz drop / early-bird reminder.
  morningKickoff,

  /// 16:00 — Personalized engagement hook (Mistake Notebook, 1v1 Battle,
  /// Free Practice, or Chapter Challenge).
  afternoonEngage,

  /// 19:00 — Signature evening Daily Quiz / streak anchor.
  eveningPrime,

  /// 21:30 — Last-chance streak rescue (armed only while `streak > 0`).
  streakRescue,
}

enum EngageTopic {
  mistakeRevision,
  battleArena,
  freePractice,
  chapterChallenge,
}

class PlannedNotification {
  final int id;
  final DateTime scheduledAt;
  final NotificationSlot slot;
  final int dayIndex;
  final EngageTopic? engageTopic;
  final String open;

  const PlannedNotification({
    required this.id,
    required this.scheduledAt,
    required this.slot,
    required this.dayIndex,
    this.engageTopic,
    required this.open,
  });
}

class NotificationPlanner {
  NotificationPlanner._();

  /// Local wall-clock time the primary evening reminder aims for. 19:00 is
  /// after school / tuition for the Class-10 audience without being a late nag.
  static const int hour = 19;
  static const int minute = 0;

  static const int winnerHour = 8;
  static const int winnerMinute = 15;

  static const int morningHour = 10;
  static const int morningMinute = 0;

  static const int afternoonHour = 16;
  static const int afternoonMinute = 0;

  static const int rescueHour = 21;
  static const int rescueMinute = 30;

  /// Legacy single-slot horizon (kept for existing callers/tests).
  static const int windowDays = 14;

  /// Multi-slot horizon: 7 days × up to 5 slots = max 35 OS alarms, staying
  /// comfortably below Android OEM queued-alarm caps (commonly 50).
  static const int multiSlotWindowDays = 7;

  /// Base for per-day evening reminder ids. Final id is [idBase] + `yyyymmdd`
  /// (fits in a 32-bit Android notification id).
  static const int idBase = 21000000;

  static const int _slotStride = 100000000;
  static const int _winnerBase = 100000000;
  static const int _morningBase = 200000000;
  static const int _afternoonBase = 300000000;
  static const int _rescueBase = 400000000;

  /// Next [days] fire times at [hour]:[minute] local.
  ///
  /// Today is included only when they have **not** already played the Daily
  /// Quiz *and* 19:00 has not yet passed. Otherwise the window starts
  /// tomorrow, so a 10:00 finish does not still ping at 19:00.
  static List<DateTime> upcomingReminders({
    required DateTime now,
    required bool playedToday,
    int hour = NotificationPlanner.hour,
    int minute = NotificationPlanner.minute,
    int days = windowDays,
  }) {
    if (days <= 0) return const [];
    final todayAt = DateTime(now.year, now.month, now.day, hour, minute);
    final start =
        (!playedToday && now.isBefore(todayAt))
            ? todayAt
            : todayAt.add(const Duration(days: 1));
    return List<DateTime>.generate(days, (i) => start.add(Duration(days: i)));
  }

  /// Plans the full multi-slot engagement schedule for the next [days]
  /// calendar days (strictly after [now]), sorted chronologically.
  ///
  /// - Today's `daily_quiz` reminders (`morningKickoff`, `eveningPrime`,
  ///   `streakRescue`) are suppressed when [playedToday] is true.
  /// - `streakRescue` (21:30) is scheduled only while [streak] > 0.
  /// - Today's `winnerReveal` (08:15) is suppressed when
  ///   [todayWinnerAnnounced] is already true, avoiding duplicate alerts.
  static List<PlannedNotification> planSchedule({
    required DateTime now,
    required bool playedToday,
    required int streak,
    int mistakeCount = 0,
    bool todayWinnerAnnounced = false,
    int days = multiSlotWindowDays,
  }) {
    if (days <= 0) return const [];
    final plan = <PlannedNotification>[];
    final todayMidnight = DateTime(now.year, now.month, now.day);

    for (var dayIndex = 0; dayIndex < days; dayIndex++) {
      final day = todayMidnight.add(Duration(days: dayIndex));
      final isToday = dayIndex == 0;

      // 1. 08:15 — Yesterday's Daily Quiz Winner reveal.
      if (!(isToday && todayWinnerAnnounced)) {
        final when = DateTime(
          day.year,
          day.month,
          day.day,
          winnerHour,
          winnerMinute,
        );
        if (when.isAfter(now)) {
          plan.add(
            PlannedNotification(
              id: slotNotificationId(when, NotificationSlot.winnerReveal),
              scheduledAt: when,
              slot: NotificationSlot.winnerReveal,
              dayIndex: dayIndex,
              open: 'winners',
            ),
          );
        }
      }

      // 2. 10:00 — Morning Daily Quiz kickoff.
      if (!(isToday && playedToday)) {
        final when = DateTime(
          day.year,
          day.month,
          day.day,
          morningHour,
          morningMinute,
        );
        if (when.isAfter(now)) {
          plan.add(
            PlannedNotification(
              id: slotNotificationId(when, NotificationSlot.morningKickoff),
              scheduledAt: when,
              slot: NotificationSlot.morningKickoff,
              dayIndex: dayIndex,
              open: 'daily_quiz',
            ),
          );
        }
      }

      // 3. 16:00 — Afternoon engagement hook (Mistakes / Battle / Practice / Chapters).
      final afternoonAt = DateTime(
        day.year,
        day.month,
        day.day,
        afternoonHour,
        afternoonMinute,
      );
      if (afternoonAt.isAfter(now)) {
        final topic = _engageTopicFor(
          dayIndex: dayIndex,
          mistakeCount: mistakeCount,
        );
        plan.add(
          PlannedNotification(
            id: slotNotificationId(
              afternoonAt,
              NotificationSlot.afternoonEngage,
            ),
            scheduledAt: afternoonAt,
            slot: NotificationSlot.afternoonEngage,
            dayIndex: dayIndex,
            engageTopic: topic,
            open: openTargetForTopic(topic),
          ),
        );
      }

      // 4. 19:00 — Evening Daily Quiz prime time.
      if (!(isToday && playedToday)) {
        final when = DateTime(day.year, day.month, day.day, hour, minute);
        if (when.isAfter(now)) {
          plan.add(
            PlannedNotification(
              id: slotNotificationId(when, NotificationSlot.eveningPrime),
              scheduledAt: when,
              slot: NotificationSlot.eveningPrime,
              dayIndex: dayIndex,
              open: 'daily_quiz',
            ),
          );
        }
      }

      // 5. 21:30 — Last-chance streak rescue (active streaks only).
      if (streak > 0 && !(isToday && playedToday)) {
        final when = DateTime(
          day.year,
          day.month,
          day.day,
          rescueHour,
          rescueMinute,
        );
        if (when.isAfter(now)) {
          plan.add(
            PlannedNotification(
              id: slotNotificationId(when, NotificationSlot.streakRescue),
              scheduledAt: when,
              slot: NotificationSlot.streakRescue,
              dayIndex: dayIndex,
              open: 'daily_quiz',
            ),
          );
        }
      }
    }

    plan.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return plan;
  }

  static EngageTopic _engageTopicFor({
    required int dayIndex,
    required int mistakeCount,
  }) {
    const rotating = [
      EngageTopic.battleArena,
      EngageTopic.freePractice,
      EngageTopic.chapterChallenge,
    ];
    if (mistakeCount > 0) {
      if (dayIndex.isEven) return EngageTopic.mistakeRevision;
      return rotating[(dayIndex ~/ 2) % rotating.length];
    }
    return rotating[dayIndex % rotating.length];
  }

  static String openTargetForTopic(EngageTopic topic) {
    switch (topic) {
      case EngageTopic.mistakeRevision:
        return 'mistake_quiz';
      case EngageTopic.battleArena:
        return 'battle';
      case EngageTopic.freePractice:
        return 'practice';
      case EngageTopic.chapterChallenge:
        return 'chapters';
    }
  }

  /// Stable id so a reschedule replaces the same calendar day's slot.
  static int notificationIdFor(DateTime when) => idBase + _ymd(when);

  /// Stable, collision-free 32-bit Android notification id for ([when], [slot]).
  static int slotNotificationId(DateTime when, NotificationSlot slot) {
    final ymd = _ymd(when);
    switch (slot) {
      case NotificationSlot.winnerReveal:
        return _winnerBase + ymd;
      case NotificationSlot.morningKickoff:
        return _morningBase + ymd;
      case NotificationSlot.afternoonEngage:
        return _afternoonBase + ymd;
      case NotificationSlot.eveningPrime:
        return idBase + ymd;
      case NotificationSlot.streakRescue:
        return _rescueBase + ymd;
    }
  }

  /// Resolves the slot back from a scheduled notification id, or null.
  static NotificationSlot? slotFromNotificationId(int? id) {
    if (id == null) return null;
    if (id >= _rescueBase && id < _rescueBase + _slotStride) {
      return NotificationSlot.streakRescue;
    }
    if (id >= _afternoonBase && id < _afternoonBase + _slotStride) {
      return NotificationSlot.afternoonEngage;
    }
    if (id >= _morningBase && id < _morningBase + _slotStride) {
      return NotificationSlot.morningKickoff;
    }
    if (id >= _winnerBase && id < _winnerBase + _slotStride) {
      return NotificationSlot.winnerReveal;
    }
    if (id >= idBase && id < _winnerBase) {
      return NotificationSlot.eveningPrime;
    }
    return null;
  }

  static int _ymd(DateTime when) =>
      when.year * 10000 + when.month * 100 + when.day;
}
