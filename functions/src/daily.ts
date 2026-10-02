// Trusted daily-quiz credit (R02 — server-computed rewards, once per day).
import * as admin from 'firebase-admin';
import { https, logger } from 'firebase-functions/v1';
import { callable } from './options';

const db = () => admin.firestore();

/** Fixed UTC+05:30 — the app's home timezone. */
const KOLKATA_OFFSET_MINUTES = 330;

/**
 * Today's date key (yyyy-MM-dd) in Asia/Kolkata.
 *
 * Computed arithmetically rather than via `toLocaleDateString(..., {timeZone})`,
 * which depends on the Node ICU/locale database being present in the runtime —
 * a dependency that has bitten production runtimes before. This can never
 * silently fall back to UTC.
 */
function kolkataToday(now: Date = new Date()): string {
  const shifted = new Date(now.getTime() + KOLKATA_OFFSET_MINUTES * 60_000);
  return shifted.toISOString().slice(0, 10);
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

/** Points a correct daily answer is worth (client: fixed 10, ×2 with booster). */
const POINTS_PER_CORRECT = 10;
/** The double-points booster is the only multiplier the client can apply. */
const MAX_SCORE_MULTIPLIER = 2;

function normText(v: unknown): string {
  return typeof v === 'string' ? v.trim() : '';
}

/**
 * Whether a submitted option is the correct one. The client shuffles the option
 * order per device, so it cannot send a stable index — it sends the selected
 * option's localized text instead, and we match it against the answer key.
 */
function optionMatches(selected: unknown, correctOption: unknown): boolean {
  if (
    !selected ||
    typeof selected !== 'object' ||
    !correctOption ||
    typeof correctOption !== 'object'
  ) {
    return false;
  }
  const s = selected as Record<string, unknown>;
  const c = correctOption as Record<string, unknown>;
  for (const lang of ['en', 'bn', 'hi']) {
    const a = normText(s[lang]);
    const b = normText(c[lang]);
    if (a && b && a === b) return true;
  }
  return false;
}

interface VerifyResult {
  ok: boolean;
  correct: number;
  total: number;
  reason: string;
}

/**
 * Re-derives the player's correct count from the published packet and the
 * question bank, so a tampered client cannot claim a perfect run. The client
 * sends `answers: [{ question_id, selected }]` where `selected` is the chosen
 * option's localized text (or null on a timeout/skip).
 *
 * Best-effort by design: when the packet or a question doc cannot be read
 * (packet not published, offline replay, a question since deleted) the caller
 * falls back to the client-reported numbers rather than failing a real player.
 */
async function verifyAnswers(
  dateKey: string,
  raw: unknown,
): Promise<VerifyResult> {
  const fail = (reason: string): VerifyResult => ({
    ok: false,
    correct: 0,
    total: 0,
    reason,
  });

  if (!Array.isArray(raw) || raw.length === 0) return fail('no answers');

  const packetSnap = await db()
    .collection('daily_quiz_packets')
    .doc(dateKey)
    .get();
  if (!packetSnap.exists) return fail('no packet');
  const packet = packetSnap.data() ?? {};
  if (packet['approved'] !== true) return fail('packet not approved');

  const refs = Array.isArray(packet['questions']) ? packet['questions'] : [];
  const chapterByQid = new Map<string, string>();
  for (const entry of refs) {
    const cid = (entry as Record<string, unknown>)?.['chapter_id'];
    const qid = (entry as Record<string, unknown>)?.['question_id'];
    if (typeof cid === 'string' && typeof qid === 'string') {
      chapterByQid.set(qid, cid);
    }
  }
  if (chapterByQid.size === 0) return fail('empty packet');

  const submitted = raw as Array<Record<string, unknown>>;
  if (submitted.length !== chapterByQid.size) {
    return fail('answer count mismatch');
  }

  let correct = 0;
  for (const answer of submitted) {
    const qid = typeof answer?.['question_id'] === 'string'
      ? (answer['question_id'] as string)
      : '';
    const chapterId = chapterByQid.get(qid);
    if (!chapterId) return fail(`unknown question ${qid}`);

    const qSnap = await db()
      .collection('question_banks')
      .doc(chapterId)
      .collection('questions')
      .doc(qid)
      .get();
    if (!qSnap.exists) return fail(`missing question doc ${qid}`);

    const q = qSnap.data() ?? {};
    const options = Array.isArray(q['options']) ? q['options'] : [];
    const correctIndex = Number(q['correct_index']);
    if (
      !Number.isInteger(correctIndex) ||
      correctIndex < 0 ||
      correctIndex >= options.length
    ) {
      return fail(`bad answer key ${qid}`);
    }
    if (optionMatches(answer['selected'], options[correctIndex])) correct += 1;
  }

  return { ok: true, correct, total: chapterByQid.size, reason: 'verified' };
}

/**
 * The client submits its result for today's daily quiz; this function is the
 * one that credits the wallet. It:
 *   * accepts only today's (Asia/Kolkata) date,
 *   * bounds every input,
 *   * re-derives correctness from the published packet + question bank when the
 *     client sends its per-question answers (a tampered client cannot claim a
 *     perfect run),
 *   * re-derives coins/gems from the published `config/app`,
 *   * is idempotent per day via users/{uid}/daily_claims/{date},
 *   * advances the streak, xp and the leaderboard entry atomically.
 *
 * Booster items are intentionally NOT applied server-side in v1: the client
 * consumes them locally for the *displayed* session, and the credited wallet
 * delta is the plain config formula (no booster). This is stricter than the
 * old client path, never more generous.
 */
export const submitDailyResult = callable().https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new https.HttpsError('unauthenticated', 'Sign in first.');
    }
    const uid = context.auth.uid;

    const date = typeof data?.date === 'string' ? data.date : '';
    let correct = Number(data?.correct);
    let total = Number(data?.total);
    let score = Number(data?.score);
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
    if (!Number.isFinite(timeSeconds) || timeSeconds <= 0 || timeSeconds > 24 * 3600) {
      throw new https.HttpsError(
        'invalid-argument',
        'timeSeconds out of bounds.',
      );
    }

    // --- Server-side verification of the claimed result ---------------------
    const verified = await verifyAnswers(date, data?.answers);
    if (verified.ok) {
      correct = verified.correct;
      total = verified.total;
      logger.info('submitDailyResult: verified', { uid, date, correct, total });
    } else {
      // No answers, or the packet/question bank was unreadable. Fall back to
      // the client's numbers (previous behaviour) and record why.
      logger.warn('submitDailyResult: unverified submission', {
        uid,
        date,
        reason: verified.reason,
      });
    }

    // Score must be consistent with the (now authoritative) correct count:
    // POINTS_PER_CORRECT per correct answer, ×2 at most for the booster.
    const minScore = correct * POINTS_PER_CORRECT;
    const maxScore = minScore * MAX_SCORE_MULTIPLIER;
    if (!Number.isFinite(score) || score < minScore || score > maxScore) {
      logger.warn('submitDailyResult: score clamped to match answers', {
        uid,
        date,
        submitted: score,
        minScore,
        maxScore,
      });
      score = minScore;
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
        verified: verified.ok,
        credited_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      // Today's row is written once, here, on the first submission of the day
      // — which is the same "one counted score per day" rule the client
      // enforces (`DailyScoreLock`). A later submission returns
      // `already-credited` above and never touches the row, so a Score Shield
      // retry (a client-side push that replaces the locked score) cannot be
      // overwritten by the score the player was unhappy with.
      tx.set(
        db().collection'leaderboard').doc(date).collection('scores').doc(uid),
        {
          user_id: uid,
          username: u['username'] ?? '',
          name: u['full_name'] ?? '',
          avatar_path: u['avatar_path'] ?? '',
          name_effect: u['tname_effect'] ?? '',
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
