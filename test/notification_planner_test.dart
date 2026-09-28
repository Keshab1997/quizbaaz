import 'package:flutter_test/flutter_test.dart';
import 'package:quizbaaz/data/services/notification_planner.dart';

void main() {
  group('NotificationPlanner', () {
    const hour = NotificationPlanner.hour;
    const minute = NotificationPlanner.minute;

    test('before 19:00 and not played → first fire is today', () {
      final now = DateTime(2026, 9, 6, 10, 15);
      final fires = NotificationPlanner.upcomingReminders(
        now: now,
        playedToday: false,
      );
      expect(fires, hasLength(NotificationPlanner.windowDays));
      expect(fires.first, DateTime(2026, 9, 6, hour, minute));
      expect(fires[1], DateTime(2026, 9, 7, hour, minute));
      expect(fires.last, DateTime(2026, 9, 19, hour, minute));
    });

    test('already played today → window starts tomorrow', () {
      final now = DateTime(2026, 9, 6, 10, 15);
      final fires = NotificationPlanner.upcomingReminders(
        now: now,
        playedToday: true,
      );
      expect(fires.first, DateTime(2026, 9, 7, hour, minute));
    });

    test('after 19:00 and not played → skip today (slot has passed)', () {
      final now = DateTime(2026, 9, 6, 19, 1);
      final fires = NotificationPlanner.upcomingReminders(
        now: now,
        playedToday: false,
      );
      expect(fires.first, DateTime(2026, 9, 7, hour, minute));
    });

    test('exactly 19:00 is not in the future, so skip today', () {
      final now = DateTime(2026, 9, 6, hour, minute);
      final fires = NotificationPlanner.upcomingReminders(
        now: now,
        playedToday: false,
      );
      expect(fires.first, DateTime(2026, 9, 7, hour, minute));
    });

    test('month rollover stays on the calendar', () {
      final now = DateTime(2026, 9, 30, 20, 0);
      final fires = NotificationPlanner.upcomingReminders(
        now: now,
        playedToday: false,
        days: 3,
      );
      expect(fires, [
        DateTime(2026, 10, 1, hour, minute),
        DateTime(2026, 10, 2, hour, minute),
        DateTime(2026, 10, 3, hour, minute),
      ]);
    });

    test('notification ids are unique per calendar day and stable', () {
      final a = DateTime(2026, 9, 6, hour, minute);
      final b = DateTime(2026, 9, 7, hour, minute);
      expect(
        NotificationPlanner.notificationIdFor(a),
        isNot(NotificationPlanner.notificationIdFor(b)),
      );
      expect(
        NotificationPlanner.notificationIdFor(a),
        NotificationPlanner.notificationIdFor(DateTime(2026, 9, 6, 23, 59)),
      );
      expect(NotificationPlanner.notificationIdFor(a), lessThan(1 << 31));
    });

    test('empty window when days is 0', () {
      expect(
        NotificationPlanner.upcomingReminders(
          now: DateTime(2026, 9, 6),
          playedToday: false,
          days: 0,
        ),
        isEmpty,
      );
    });
  });
}
