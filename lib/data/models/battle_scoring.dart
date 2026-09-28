/// Pure scoring rules for 1-vs-1 battles — no Flutter dependencies.
///
/// ## Formula
///
/// ```text
/// correct answer  →  base (10)
///                  + speed bonus  (up to 10 — with reading grace)
///                  + first bonus  (2 — locked in before the opponent)
///                  + streak bonus (2 × streak, capped at 6)
/// wrong / timeout →  0
/// ```
///
/// ## Reading Grace (new — human-like fairness)
///
/// Nobody can read and answer a question in under ~3 seconds (especially
/// dual-language Bengali + English). The first 20% of the question window
/// is a "reading grace zone" — any answer within this zone pays the **full**
/// speed bonus. After grace, the bonus decays linearly to 0 at the deadline.
///
/// This prevents the bot (which answers at 4–8.5 s) from always outscoring
/// a human student (who needs 5–9 s to read + think). A 4/5 vs 4/5 match
/// now lands within a few points instead of a 26-point blowout.
class BattleScoring {
  const BattleScoring._();

  /// The four components of one answer.
  /// `total = base + speedBonus + firstBonus + streakBonus`
  static ({int base, int speedBonus, int firstBonus, int streakBonus}) compute({
    required bool correct,
    required int remainingMs, // ms left on the question clock when answered
    required int questionDurationMs, // full question window in ms
    required bool answeredBeforeOpponent, // true = this side locked in first
    required int streak, // consecutive correct count before this answer
    required int basePoints, // default 10
    required int maxSpeedBonus, // default 10 — full bonus for an instant answer
    required int firstBonus, // default 2 — flat race bonus
    required int streakBonusPerStreak, // default 2
    int maxStreakBonus = 6, // cap so long battles can't snowball forever
    int readingGraceMs = 0, // full-bonus zone: nobody reads faster than this
  }) {
    if (!correct) {
      return (base: 0, speedBonus: 0, firstBonus: 0, streakBonus: 0);
    }

    // Time-scaled speed bonus with reading grace.
    // Within the grace zone (first ~20% of window): full bonus.
    // After grace: linear decay to 0 at deadline.
    var speed = 0;
    if (questionDurationMs > 0 && remainingMs > 0 && maxSpeedBonus > 0) {
      final effectiveWindow = questionDurationMs - readingGraceMs;
      if (effectiveWindow <= 0 || remainingMs >= effectiveWindow) {
        // Within grace zone or grace covers entire window → full bonus.
        speed = maxSpeedBonus;
      } else {
        speed = (maxSpeedBonus * remainingMs / effectiveWindow).round().clamp(
              0,
              maxSpeedBonus,
            );
      }
    }

    final first = answeredBeforeOpponent ? firstBonus : 0;
    final streakB = streak >= 1
        ? (streak * streakBonusPerStreak).clamp(0, maxStreakBonus)
        : 0;

    return (
      base: basePoints,
      speedBonus: speed,
      firstBonus: first,
      streakBonus: streakB,
    );
  }

  /// Total for a component tuple.
  static int total(
    ({int base, int speedBonus, int firstBonus, int streakBonus}) parts,
  ) =>
      parts.base + parts.speedBonus + parts.firstBonus + parts.streakBonus;

  /// Human-readable breakdown, e.g. `10 + 8 + 2 + 4`
  static String breakdown(
    ({int base, int speedBonus, int firstBonus, int streakBonus}) parts,
  ) =>
      '${parts.base} + ${parts.speedBonus} + ${parts.firstBonus} + '
      '${parts.streakBonus}';
}
