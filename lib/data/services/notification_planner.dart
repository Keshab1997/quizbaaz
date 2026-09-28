/// Pure date math for Daily Quiz reminders. No plugins, no Flutter — so the
/// unit tests can pin [now] without a device clock or timezone database.
///
/// Keep [hour]/[minute] in sync with the copy in `S.notifBellOn`.
class NotificationPlanner {
  NotificationPlanner._();

  /// Local wall-clock time the reminder aims for. 19:00 is after school /
  /// tuition for the Class-10 audience without being a late-night nag.
  static const int hour = 19;
  static const int minute = 0;

  /// How many future days to arm in one pass. Each app open refills the
  /// window; if they don't open for this long they have churned.
  static const int windowDays = 14;

  /// Base for per-day notification ids. Final id is
  /// [idBase] + `yyyymmdd` (fits in a 32-bit Android notification id).
  static const int idBase = 21000000;

  /// Next [windowDays] fire times at [hour]:[minute] local.
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

  /// Stable id so a reschedule replaces the same calendar day's slot.
  static int notificationIdFor(DateTime when) =>
      idBase + when.year * 10000 + when.month * 100 + when.day;
}
