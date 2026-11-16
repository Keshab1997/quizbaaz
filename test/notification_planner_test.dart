import 'package:flutter_test/flutter_test.dart';
import 'package:quizbaaz/data/services/notification_planner.dart';

void main() {
  group('NotificationPlanner (legacy 19:00 API)', () {
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

  group('NotificationPlanner.planSchedule (multi-slot)', () {
    test('early morning, unplayed, no streak → 4 slots today, no rescue', () {
      final now = DateTime(2026, 11, 16, 7, 30);
      final plan = NotificationPlanner.planSchedule(
        now: now,
        playedToday: false,
        streak: 0,
        days: 1,
      );
      expect(plan.map((p) => p.slot), [
        NotificationSlot.winnerReveal,
        NotificationSlot.morningKickoff,
        NotificationSlot.afternoonEngage,
        NotificationSlot.eveningPrime,
      ]);
      expect(plan.map((p) => p.open), [
        'winners',
        'daily_quiz',
        'battle',
        'daily_quiz',
      ]);
    });

    test('active streak adds 21:30 rescue slot when unplayed', () {
      final now = DateTime(2026, 11, 16, 7, 30);
      final plan = NotificationPlanner.planSchedule(
        now: now,
        playedToday: false,
        streak: 5,
        days: 1,
      );
      expect(plan.map((p) => p.slot), [
        NotificationSlot.winnerReveal,
        NotificationSlot.morningKickoff,
        NotificationSlot.afternoonEngage,
        NotificationSlot.eveningPrime,
        NotificationSlot.streakRescue,
      ]);
      expect(plan.last.scheduledAt, DateTime(2026, 11, 16, 21, 30));
    });

    test('playing today cancels daily quiz & streak slots for today only', () {
      final now = DateTime(2026, 11, 16, 10, 30);
      final plan = NotificationPlanner.planSchedule(
        now: now,
        playedToday: true,
        streak: 5,
        todayWinnerAnnounced: true,
        days: 2,
      );
      final todaySlots = plan.where((p) => p.dayIndex == 0).toList();
      expect(todaySlots.map((p) => p.slot), [NotificationSlot.afternoonEngage]);

      final tomorrowSlots = plan.where((p) => p.dayIndex == 1).toList();
      expect(tomorrowSlots.map((p) => p.slot), [
        NotificationSlot.winnerReveal,
        NotificationSlot.morningKickoff,
        NotificationSlot.afternoonEngage,
        NotificationSlot.eveningPrime,
        NotificationSlot.streakRescue,
      ]);
    });

    test('todayWinnerAnnounced suppresses 08:15 winner slot for today', () {
      final now = DateTime(2026, 11, 16, 7, 0);
      final plan = NotificationPlanner.planSchedule(
        now: now,
        playedToday: false,
        streak: 0,
        todayWinnerAnnounced: true,
        days: 1,
      );
      expect(
        plan.where((p) => p.slot == NotificationSlot.winnerReveal),
        isEmpty,
      );
    });

    test('afternoon topic prioritizes mistakes when present, else rotates', () {
      final now = DateTime(2026, 11, 16, 7, 0);
      final withoutMistakes =
          NotificationPlanner.planSchedule(
            now: now,
            playedToday: false,
            streak: 0,
            mistakeCount: 0,
            days: 4,
          ).where((p) => p.slot == NotificationSlot.afternoonEngage).toList();

      expect(withoutMistakes.map((p) => p.engageTopic), [
        EngageTopic.battleArena,
        EngageTopic.freePractice,
        EngageTopic.chapterChallenge,
        EngageTopic.battleArena,
      ]);

      final withMistakes =
          NotificationPlanner.planSchedule(
            now: now,
            playedToday: false,
            streak: 0,
            mistakeCount: 4,
            days: 4,
          ).where((p) => p.slot == NotificationSlot.afternoonEngage).toList();

      expect(withMistakes.map((p) => p.engageTopic), [
        EngageTopic.mistakeRevision,
        EngageTopic.battleArena,
        EngageTopic.mistakeRevision,
        EngageTopic.freePractice,
      ]);
      expect(withMistakes.first.open, 'mistake_quiz');
    });

    test(
      'full window stays <= 35 alarms and ids round-trip via slot lookup',
      () {
        final now = DateTime(2026, 11, 16, 0, 1);
        final plan = NotificationPlanner.planSchedule(
          now: now,
          playedToday: false,
          streak: 10,
        );
        expect(plan.length, lessThanOrEqualTo(35));

        final ids = plan.map((p) => p.id).toSet();
        expect(ids, hasLength(plan.length));

        for (final item in plan) {
          expect(item.id, greaterThan(0));
          expect(item.id, lessThan(1 << 31));
          expect(
            NotificationPlanner.slotFromNotificationId(item.id),
            item.slot,
          );
        }
      },
    );
  });
}
