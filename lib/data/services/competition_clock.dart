/// One clock for everything competitive.
///
/// The daily quiz, the leaderboard bucket and the reward window all have to be
/// dated the same way on every device, otherwise two players in different
/// timezones play "the same" daily quiz in different day buckets, and a player
/// who travels can submit twice (R12).
///
/// The competition day is defined in a single fixed timezone (UTC+5:30 — the
/// audience this app ships for), not in the device's local time and not in
/// device-local midnight. Nothing here reads `DateTime.now()` on its own: the
/// caller passes the instant, so tests can pin the clock.
library;

class CompetitionClock {
  CompetitionClock._();

  /// The one timezone the competition runs in.
  static const Duration utcOffset = Duration(hours: 5, minutes: 30);

  /// `yyyy-MM-dd` of the competition day that [now] falls in.
  static String dateKey([DateTime? now]) {
    final shifted = (now ?? DateTime.now()).toUtc().add(utcOffset);
    final month = shifted.month.toString().padLeft(2, '0');
    final day = shifted.day.toString().padLeft(2, '0');
    return '${shifted.year}-$month-$day';
  }

  /// The instant a competition day starts, in UTC.
  static DateTime dayStart(String dateKey) {
    final parts = dateKey.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);
    return DateTime.utc(year, month, day).subtract(utcOffset);
  }

  /// The instant a competition day closes (start of the next day). Scores can
  /// no longer be submitted after this.
  static DateTime dayEnd(String dateKey) =>
      dayStart(dateKey).add(const Duration(days: 1));

  /// The previous competition day's key.
  static String previousDateKey(String dateKey) =>
      dateKeyOf(dayStart(dateKey).subtract(utcOffset));

  /// Helper for [previousDateKey]: passes an already-shifted instant through.
  static String dateKeyOf(DateTime instant) => dateKey(instant);

  /// Milliseconds remaining until [dateKey] closes (never negative).
  static int msUntilClose(String dateKey, DateTime now) {
    final remaining = dayEnd(dateKey).difference(now.toUtc()).inMilliseconds;
    return remaining < 0 ? 0 : remaining;
  }
}
