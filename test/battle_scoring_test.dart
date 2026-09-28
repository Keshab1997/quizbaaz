import 'package:flutter_test/flutter_test.dart';
import 'package:quizbaaz/data/models/battle_scoring.dart';

void main() {
  const base = 10;
  const maxSpeed = 10;
  const firstBonus = 3;
  const streakPer = 2;
  const maxStreak = 10;
  const questionMs = 15000;

  ({int base, int speedBonus, int firstBonus, int streakBonus}) compute({
    required bool correct,
    required int remainingMs,
    bool answeredBeforeOpponent = false,
    int streak = 0,
  }) => BattleScoring.compute(
    correct: correct,
    remainingMs: remainingMs,
    questionDurationMs: questionMs,
    answeredBeforeOpponent: answeredBeforeOpponent,
    streak: streak,
    basePoints: base,
    maxSpeedBonus: maxSpeed,
    firstBonus: firstBonus,
    streakBonusPerStreak: streakPer,
    maxStreakBonus: maxStreak,
  );

  group('BattleScoring — formula (10 + speed + first + streak)', () {
    test('wrong answer pays nothing, even with time left', () {
      final parts = compute(
        correct: false,
        remainingMs: questionMs,
        answeredBeforeOpponent: true,
        streak: 3,
      );
      expect(BattleScoring.total(parts), 0);
      expect(parts.base, 0);
      expect(parts.speedBonus, 0);
      expect(parts.firstBonus, 0);
      expect(parts.streakBonus, 0);
    });

    test('instant correct answer (full time left) → full speed bonus', () {
      final parts = compute(
        correct: true,
        remainingMs: questionMs,
        answeredBeforeOpponent: true,
      );
      expect(parts.base, 10);
      expect(parts.speedBonus, 10);
      expect(parts.firstBonus, 3);
      expect(parts.streakBonus, 0);
      expect(BattleScoring.total(parts), 23);
    });

    test('last-second correct answer → almost no speed bonus', () {
      final parts = compute(
        correct: true,
        remainingMs: 100, // 0.1 s left of 15 s
      );
      expect(parts.base, 10);
      expect(parts.speedBonus, 0); // round(10 × 100/15000) = 0
      expect(parts.firstBonus, 0); // opponent already answered
      expect(BattleScoring.total(parts), 10);
    });

    test('speed bonus scales linearly with remaining time', () {
      final half = compute(correct: true, remainingMs: questionMs ~/ 2);
      expect(half.speedBonus, 5); // half the clock left → half the bonus

      final fifth = compute(correct: true, remainingMs: questionMs ~/ 5);
      expect(fifth.speedBonus, 2); // 10 × 3000/15000 = 2
    });

    test('answering after the opponent still pays the speed bonus', () {
      // The core fix: speed is rewarded even when you are second to answer.
      final parts = compute(
        correct: true,
        remainingMs: questionMs - 2000, // answered fast, but second
        answeredBeforeOpponent: false,
      );
      expect(parts.speedBonus, 9); // round(10 × 13000/15000) = 9
      expect(parts.firstBonus, 0);
    });

    test('streak=1 → +2×1, streak=3 → +2×3', () {
      final s1 = compute(correct: true, remainingMs: 0, streak: 1);
      expect(s1.streakBonus, 2);

      final s3 = compute(
        correct: true,
        remainingMs: 0,
        streak: 3,
        answeredBeforeOpponent: true,
      );
      expect(s3.streakBonus, 6);
      expect(BattleScoring.total(s3), 10 + 0 + 3 + 6);
    });

    test('streak bonus is capped', () {
      final parts = compute(correct: true, remainingMs: 0, streak: 7);
      expect(parts.streakBonus, 10); // 2×7 = 14 → capped at 10
    });

    test('answer exactly at the deadline (0 ms left) → base only', () {
      final parts = compute(
        correct: true,
        remainingMs: 0,
        answeredBeforeOpponent: true,
      );
      expect(parts.base, 10);
      expect(parts.speedBonus, 0);
      expect(parts.firstBonus, 3);
    });

    test('breakdown string format', () {
      final parts = compute(
        correct: true,
        remainingMs: 12000, // speed 8
        answeredBeforeOpponent: true,
        streak: 2, // streak 4
      );
      expect(BattleScoring.breakdown(parts), '10 + 8 + 3 + 4');
    });
  });
}
