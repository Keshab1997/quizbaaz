// Release & Daily Winner broadcasts via OneSignal.
//
// HTTP hooks are guarded by a shared secret instead of App Check (they are
// called by publish pipelines or owner terminals, which have no App Check
// token). Both secrets live in Secret Manager, never in the repo:
//
//   firebase functions:secrets:set BROADCAST_HOOK_SECRET
//   firebase functions:secrets:set ONESIGNAL_REST_KEY
//
//   POST  https://<region>-<project>.cloudfunctions.net/broadcastAppUpdate
//   POST  https://<region>-<project>.cloudfunctions.net/broadcastDailyWinner
//   headers: { 'x-qb-broadcast-secret': <BROADCAST_HOOK_SECRET> }
//
// `scheduledDailyWinnerPush` also runs daily at 08:15 IST to announce
// yesterday's Daily Quiz #1 champion to all subscribers automatically.
import { timingSafeEqual } from 'crypto';

import * as admin from 'firebase-admin';
import { logger, runWith } from 'firebase-functions/v1';
import { defineSecret } from 'firebase-functions/params';

import { REGION } from './options';

const broadcastHookSecret = defineSecret('BROADCAST_HOOK_SECRET');
const oneSignalRestKey = defineSecret('ONESIGNAL_REST_KEY');

const DEFAULT_ONESIGNAL_APP_ID = '578dc90c-b87a-4be4-afe8-004aecd8b1e6';
const KOLKATA_OFFSET_MINUTES = 330;

const VERSION_RE = /^\d+\.\d+\.\d+$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const APP_ID_RE = /^[0-9a-fA-F-]{36}$/;
const LANGS = ['en', 'bn', 'hi'] as const;
type Lang = (typeof LANGS)[number];

interface BroadcastBody {
  app_id?: unknown;
  version?: unknown;
  notes?: unknown;
  include_all?: unknown;
}

interface WinnerBroadcastBody {
  app_id?: unknown;
  date?: unknown;
  force?: unknown;
}

interface ResolvedWinner {
  name: string;
  score: number;
  giftName: string;
}

/** Headings are version-templated; contents fall back to per-language copy. */
const HEADINGS: Record<Lang, (v: string) => string> = {
  en: (v) => `QuizBaaz ${v} is here 🚀`,
  bn: (v) => `QuizBaaz ${v} এসেছে 🚀`,
  hi: (v) => `QuizBaaz ${v} आ गया है 🚀`,
};

const CONTENT_FALLBACK: Record<Lang, string> = {
  en: "See what's changed and update to the latest version.",
  bn: 'কী নতুন হয়েছে দেখুন আর সর্বশেষ ভার্সনে আপডেট করুন।',
  hi: 'देखिए क्या नया है और सबसे नए वर्शन में अपडेट करिए।',
};

/** Release notes are short — trim hard so no locale hits a wall. */
function contentFor(notes: Record<string, unknown>, lang: Lang): string {
  const raw = (notes[lang] ?? '').toString().trim();
  if (!raw) return CONTENT_FALLBACK[lang];
  return raw.length > 480 ? `${raw.slice(0, 477)}…` : raw;
}

function secretMatches(provided: string | undefined, expected: string): boolean {
  if (!expected) return false;
  const a = Buffer.from(provided ?? '', 'utf8');
  const b = Buffer.from(expected, 'utf8');
  // A length leak is irrelevant for a shared hook secret; keep it simple and
  // constant-time for equal lengths.
  return a.length === b.length && timingSafeEqual(a, b);
}

function kolkataYesterday(now: Date = new Date()): string {
  const shifted = new Date(
    now.getTime() + KOLKATA_OFFSET_MINUTES * 60_000 - 86_400_000,
  );
  return shifted.toISOString().slice(0, 10);
}

async function sendOneSignalNotification(
  restKey: string,
  payload: Record<string, unknown>,
): Promise<{ ok: boolean; status: number; body: Record<string, unknown> }> {
  const resp = await fetch('https://onesignal.com/api/v1/notifications', {
    method: 'POST',
    headers: {
      Authorization: `Key ${restKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  const body = (await resp.json().catch(() => ({}))) as Record<string, unknown>;
  return { ok: resp.ok, status: resp.status, body };
}

async function resolveWinnerForDate(
  dateKey: string,
): Promise<ResolvedWinner | null> {
  const db = admin.firestore();
  const champsSnap = await db
    .collection('champions')
    .doc(dateKey)
    .collection('winners')
    .orderBy('rank')
    .limit(1)
    .get();

  let row: Record<string, unknown> | null = null;
  if (!champsSnap.empty) {
    row = champsSnap.docs[0].data();
  } else {
    const scoresSnap = await db
      .collection('leaderboard')
      .doc(dateKey)
      .collection('scores')
      .orderBy('score', 'desc')
      .orderBy('time_seconds', 'asc')
      .limit(1)
      .get();
    if (!scoresSnap.empty) {
      row = scoresSnap.docs[0].data();
    }
  }

  if (!row) return null;
  const fullName = typeof row['name'] === 'string' ? row['name'].trim() : '';
  const username =
    typeof row['username'] === 'string' ? row['username'].trim() : '';
  const name = fullName || (username ? `@${username}` : '');
  if (!name) return null;

  const rawScore = Number(row['score']);
  const score = Number.isFinite(rawScore) ? Math.round(rawScore) : 0;
  const giftName =
    typeof row['gift_name'] === 'string' ? row['gift_name'].trim() : '';

  return { name, score, giftName };
}

function buildWinnerPushPayload(
  appId: string,
  dateKey: string,
  winner: ResolvedWinner,
): Record<string, unknown> {
  const { name, score, giftName } = winner;
  const enBody = giftName
    ? `${name} won with ${score} pts & unlocked ${giftName}! Tap to see the Winners podium.`
    : `${name} topped Yesterday's Daily Quiz with ${score} pts! Can you beat them today?`;
  const bnBody = giftName
    ? `${name} ${score} পয়েন্টে জয়ী হয়ে ${giftName} জিতেছেন! বিজয়ীদের মঞ্চ দেখতে ট্যাপ করুন।`
    : `${name} গতকালের ডেইলি কুইজে ${score} পয়েন্ট নিয়ে প্রথম! আজ কি আপনি তাকে হারাতে পারবেন?`;
  const hiBody = giftName
    ? `${name} ने ${score} अंक से जीतकर ${giftName} पाया! विजेता मंच देखने के लिए टैप करें।`
    : `${name} ने कल की डेली क्विज़ में ${score} अंक के साथ टॉप किया! क्या आप आज उन्हें हरा पाएंगे?`;

  return {
    app_id: appId,
    included_segments: ['All'],
    headings: {
      en: `🏆 Yesterday's Winner: ${name}`,
      bn: `🏆 গতকালের বিজয়ী: ${name}`,
      hi: `🏆 कल के विजेता: ${name}`,
    },
    contents: {
      en: enBody,
      bn: bnBody,
      hi: hiBody,
    },
    data: { open: 'winners', date: dateKey },
    ttl: 43200,
  };
}

export const broadcastAppUpdate = runWith({
  secrets: [broadcastHookSecret, oneSignalRestKey],
  memory: '256MB',
  timeoutSeconds: 60,
  maxInstances: 2,
})
  .region(REGION)
  .https.onRequest(async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'POST only' });
      return;
    }
    const provided = req.get('x-qb-broadcast-secret') ?? undefined;
    if (!secretMatches(provided, broadcastHookSecret.value())) {
      logger.warn('broadcastAppUpdate: bad or missing secret');
      res.status(401).json({ error: 'unauthorized' });
      return;
    }

    const body = (req.body ?? {}) as BroadcastBody;
    const appId = typeof body.app_id === 'string' ? body.app_id.trim() : '';
    const version = typeof body.version === 'string' ? body.version.trim() : '';
    if (!APP_ID_RE.test(appId)) {
      res.status(400).json({ error: 'app_id must be the OneSignal App ID UUID' });
      return;
    }
    if (!VERSION_RE.test(version)) {
      res.status(400).json({ error: 'version must look like 1.0.14' });
      return;
    }
    const notes = (body.notes ?? {}) as Record<string, unknown>;

    const filters: Array<Record<string, string>> = body.include_all === true
        ? []
        : [{ field: 'app_version', relation: '!=', value: version }];

    const payload: Record<string, unknown> = {
      app_id: appId,
      headings: {
        en: HEADINGS.en(version),
        bn: HEADINGS.bn(version),
        hi: HEADINGS.hi(version),
      },
      contents: {
        en: contentFor(notes, 'en'),
        bn: contentFor(notes, 'bn'),
        hi: contentFor(notes, 'hi'),
      },
      data: { open: 'app_update', version },
      // A release push is worth a day of queueing on a killed app.
      ttl: 86400,
      ...(filters.length > 0 ? { filters } : {}),
    };

    try {
      const resp = await sendOneSignalNotification(
        oneSignalRestKey.value(),
        payload,
      );
      logger.info('broadcastAppUpdate', {
        version,
        status: resp.status,
        recipients: resp.body.recipients ?? 0,
        id: resp.body.id ?? null,
      });
      res.status(resp.ok ? 200 : 502).json({ ok: resp.ok, ...resp.body });
    } catch (err) {
      logger.error('broadcastAppUpdate: OneSignal call failed', err);
      res.status(502).json({ error: 'onesignal request failed' });
    }
  });

/**
 * Announces yesterday's (or specified `date`'s) Daily Quiz #1 champion via
 * OneSignal push (`open: 'winners'`). Idempotent per day unless `force: true`.
 */
export const broadcastDailyWinner = runWith({
  secrets: [broadcastHookSecret, oneSignalRestKey],
  memory: '256MB',
  timeoutSeconds: 60,
  maxInstances: 2,
})
  .region(REGION)
  .https.onRequest(async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'POST only' });
      return;
    }
    const provided = req.get('x-qb-broadcast-secret') ?? undefined;
    if (!secretMatches(provided, broadcastHookSecret.value())) {
      logger.warn('broadcastDailyWinner: bad or missing secret');
      res.status(401).json({ error: 'unauthorized' });
      return;
    }

    const body = (req.body ?? {}) as WinnerBroadcastBody;
    const rawAppId = typeof body.app_id === 'string' ? body.app_id.trim() : '';
    const appId = rawAppId || DEFAULT_ONESIGNAL_APP_ID;
    if (!APP_ID_RE.test(appId)) {
      res.status(400).json({ error: 'app_id must be the OneSignal App ID UUID' });
      return;
    }

    const rawDate = typeof body.date === 'string' ? body.date.trim() : '';
    const dateKey = rawDate || kolkataYesterday();
    if (!DATE_RE.test(dateKey)) {
      res.status(400).json({ error: 'date must look like yyyy-MM-dd' });
      return;
    }

    const markerRef = admin
      .firestore()
      .collection('meta')
      .doc(`winner_broadcast_${dateKey}`);
    if (body.force !== true) {
      const marker = await markerRef.get();
      if (marker.exists) {
        res.status(200).json({
          ok: true,
          skipped: true,
          reason: 'already-broadcast',
          date: dateKey,
        });
        return;
      }
    }

    const winner = await resolveWinnerForDate(dateKey);
    if (!winner) {
      res.status(200).json({
        ok: true,
        skipped: true,
        reason: 'no-winner-for-date',
        date: dateKey,
      });
      return;
    }

    try {
      const payload = buildWinnerPushPayload(appId, dateKey, winner);
      const resp = await sendOneSignalNotification(
        oneSignalRestKey.value(),
        payload,
      );
      if (resp.ok) {
        await markerRef.set({
          date: dateKey,
          winner_name: winner.name,
          score: winner.score,
          onesignal_id: resp.body.id ?? null,
          sent_at: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      logger.info('broadcastDailyWinner', {
        date: dateKey,
        winner: winner.name,
        status: resp.status,
        recipients: resp.body.recipients ?? 0,
      });
      res.status(resp.ok ? 200 : 502).json({
        ok: resp.ok,
        date: dateKey,
        winner: winner.name,
        ...resp.body,
      });
    } catch (err) {
      logger.error('broadcastDailyWinner: OneSignal call failed', err);
      res.status(502).json({ error: 'onesignal request failed' });
    }
  });

/**
 * Scheduled 08:15 IST push announcing yesterday's Daily Quiz #1 champion.
 * Fails soft if ONESIGNAL_REST_KEY is empty or no scores were recorded.
 */
export const scheduledDailyWinnerPush = runWith({
  secrets: [oneSignalRestKey],
  memory: '256MB',
  timeoutSeconds: 60,
  maxInstances: 1,
})
  .region(REGION)
  .pubsub.schedule('15 8 * * *')
  .timeZone('Asia/Kolkata')
  .onRun(async () => {
    const restKey = oneSignalRestKey.value().trim();
    if (!restKey) {
      logger.info('scheduledDailyWinnerPush: ONESIGNAL_REST_KEY empty, skipping');
      return;
    }

    const dateKey = kolkataYesterday();
    const markerRef = admin
      .firestore()
      .collection('meta')
      .doc(`winner_broadcast_${dateKey}`);
    if ((await markerRef.get()).exists) {
      logger.info('scheduledDailyWinnerPush: already sent', { date: dateKey });
      return;
    }

    const winner = await resolveWinnerForDate(dateKey);
    if (!winner) {
      logger.info('scheduledDailyWinnerPush: no winner yet', { date: dateKey });
      return;
    }

    const payload = buildWinnerPushPayload(
      DEFAULT_ONESIGNAL_APP_ID,
      dateKey,
      winner,
    );
    const resp = await sendOneSignalNotification(restKey, payload);
    if (resp.ok) {
      await markerRef.set({
        date: dateKey,
        winner_name: winner.name,
        score: winner.score,
        onesignal_id: resp.body.id ?? null,
        sent_at: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    logger.info('scheduledDailyWinnerPush', {
      date: dateKey,
      winner: winner.name,
      status: resp.status,
      recipients: resp.body.recipients ?? 0,
    });
  });
