// Trusted daily-quiz credit (R02 — server-computed rewards, once per day).
import * as admin from 'firebase-admin';
import { https } from 'firebase-functions/v1';

const db = () => admin.firestore();

/** Today's date key (yyyy-MM-dd) in Asia/Kolkata — the app's home timezone. */
function kolkataToday(): string {
  return new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });
}

function shiftDay(dateKey: string, days: number): string {
  const [y, m, d] = dateKey.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() + days);
  return dt.toISOString().slice(0, 10);
}

function num(value: unknown, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0
    ? value
    : fallback;
}

async function loadConfig(): Promise<{
  coinsPerCorrectDaily: number;
  perfectBonusCoins: number;
  gemsPerfect: number;
  gemsHighScore: number;
  highScoreThreshold: number;
  dailyQuestionCount: number;
}> {
  const snap = await db().collection('config').doc('app').get();
  const d = snap.data() ?? {};
  return {
    coinsPerCorrectDaily: num(d['coins_per_correct_daily'], 10),
    perfectBonusCoins: num(d['perfect_bonus_coins'], 50),
    gemsPerfect: num(d['gems_perfect'], 10),
    gemsHighScore: num(d['gems_high_score'], 5),
    highScoreThreshold: num(d['high_score_threshold'], 8),
    dailyQuestionCount: num(d['daily_question_count'], 10),
  };
}

/**
 * The client submits its result for today's daily quiz; this function is the
 * one that credits the wallet. It:
 *   * accepts only today's (Asia/Kolkata) date,
 *   * bounds every input,
 *   * re-derives coins/gems from the published `config/app`,
 *   * is idempotent per day via users/{uid}/daily_claims/{date},
 *   * advances the streak, xp and the leaderboard entry atomically.
 *
 * Booster items are intentionally NOT applied server-side in v1: the client
 * consumes them locally for the *displayed* session, and the credited wallet
 * delta is the plain config formula (no booster). This is stricter than the
 * old client path, never more generous.
 */
export const submitDailyResult = https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new https.HttpsError('unauthenticated', 'Sign in first.');
    }
    const uid = context.auth.uid;

    const date = typeof data?.date === 'string' ? data.date : '';
    const correct = Number(data?.correct);
    const total = Number(data?.total);
    const score = Number(data?.score);
    const timeSeconds = Number(data?.timeSeconds);
    const today = kolkataToday();

    if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || date !== today) {
      throw new https.HttpsError(
        'invalid-argument',
        "Only today's result (Asia/Kolkata) may be submitted.",
      );
    }
    if (
      !Number.isInteger(correct) ||
      !Number.isInteger(total) ||
      correct < 0 ||
      total < 1 ||
      correct > total
    ) {
      throw new https.HttpsError(
        'invalid-argument',
        'correct/total must be sane integers (0 <= correct <= total).',
      );
    }
    const cfg = await loadConfig();
    if (total > cfg.dailyQuestionCount) {
      throw new https.HttpsError(
        'invalid-argument',
        'total exceeds the configured daily question count.',
      );
    }
    if (!Number.isFinite(score) || score < 0 || score > 1000) {
      throw new https.HttpsError(
        'invalid-argument',
        'score out of bounds (0..1000).',
      );
    }
    if (!Number.isFinite(timeSeconds) || timeSeconds <= 0 || timeSeconds > 24 * 3600) {
      throw new https.HttpsError(
        'invalid-argument',
        'timeSeconds out of bounds.',
      );
    }

    const userRef = db().collection('users').doc(uid);
    const claimRef = userRef.collection('daily_claims').doc(date);

    return db().runTransaction(async (tx) => {
      const existing = await tx.get(claimRef);
      if (existing.exists) {
        return { ok: true, credited: false, reason: 'already-credited' };
      }

      const userSnap = await tx.get(userRef);
      if (!userSnap.exists) {
        throw new https.HttpsError(
          'failed-precondition',
          'Create your profile (users/{uid}) before submitting a daily result.',
        );
      }
      const u = userSnap.data()!;
      const isPerfect = correct === total;
      const coins =
        correct * cfg.coinsPerCorrectDaily + (isPerfect ? cfg.perfectBonusCoins : 0);
      const gems = isPerfect
        ? cfg.gemsPerfect
        : correct >= cfg.highScoreThreshold
          ? cfg.gemsHighScore
          : 0;

      const lastStreakDate = (u['last_streak_date'] as string | null) ?? null;
      const dailyStreak =
        lastStreakDate === shiftDay(date, -1)
          ? ((u['daily_streak'] as number) ?? 0) + 1
          : 1;
      const xp = ((u['xp'] as number) ?? 0) + Math.round(score);

      tx.update(userRef, {
        coins: admin.firestore.FieldValue.increment(coins),
        gems: admin.firestore.FieldValue.increment(gems),
        xp,
        daily_streak: dailyStreak,
        last_streak_date: date,
        played_today_daily_quiz: true,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      tx.set(
        userRef.collection('quiz_history').doc(`daily_${date}`),
        {
          mode: 'daily',
          date,
          score,
          correct,
          total,
          time_seconds: timeSeconds,
          coins_earned: coins,
          gems_earned: gems,
          played_at: date,
        },
        { merge: true },
      );
      tx.set(claimRef, {
        coins,
        gems,
        score,
        correct,
        total,
        credited_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      tx.set(
        db().collection('leaderboard').doc(date).collection('scores').doc(uid),
        {
          user_id: uid,
          username: u['username'] ?? '',
          name: u['full_name'] ?? '',
          avatar_path: u['avatar_path'] ?? '',
          name_effect: u['name_effect'] ?? '',
          score,
          time_seconds: timeSeconds,
          streak: dailyStreak,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      return { ok: true, credited: true, coins, gems, xp, daily_streak: dailyStreak };
    });
  },
);
