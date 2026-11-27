// One-time, bounded local → server progress seed.
//
// P0 (R02) made the wallet/streak server-owned, but the client never wrote
// those fields — so a device that earned coins before the trusted backend
// existed had no server balance at all. That breaks `purchaseItem` (its
// balance check fails) and leaves a reinstall with nothing to restore.
//
// This callable is the guarded escape hatch: once per account, before any
// server-side daily claim or purchase exists, it copies the device's progress
// into the server-owned fields. Afterwards the normal trusted callables own
// them. Bounds keep a single claim from minting an unbounded economy.
import * as admin from 'firebase-admin';
import { https } from 'firebase-functions/v1';
import { callable } from './options';

const MAX_COINS = 10000;
const MAX_GEMS = 500;
const MAX_ITEMS = 50;
const MAX_QTY = 100;
const MAX_STREAK = 365;
const MAX_DATES = 35;
const ID = /^[a-zA-Z0-9_-]{1,64}$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

function boundedInt(value: unknown, max: number): number {
  const n = Number(value);
  if (!Number.isFinite(n)) {
    throw new https.HttpsError('invalid-argument', 'Bad progress value.');
  }
  return Math.min(Math.max(Math.floor(n), 0), max);
}

function dateOrNull(value: unknown): string | null {
  if (typeof value !== 'string' || value.length === 0) return null;
  if (!DATE.test(value)) {
    throw new https.HttpsError('invalid-argument', 'Bad streak date.');
  }
  return value;
}

export const seedLocalProgress = callable().https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new https.HttpsError('unauthenticated', 'Sign in first.');
  }
  const uid = context.auth.uid;

  const coins = boundedInt(data?.coins, MAX_COINS);
  const gems = boundedInt(data?.gems, MAX_GEMS);
  const dailyStreak = boundedInt(data?.dailyStreak, MAX_STREAK);
  const lastStreakDate = dateOrNull(data?.lastStreakDate);

  const inventory: Record<string, number> = {};
  const rawInventory: unknown = data?.inventory;
  if (rawInventory && typeof rawInventory === 'object' && !Array.isArray(rawInventory)) {
    for (const [key, value] of Object.entries(rawInventory as Record<string, unknown>)) {
      if (!ID.test(key)) {
        throw new https.HttpsError('invalid-argument', 'Bad item id.');
      }
      if (Object.keys(inventory).length >= MAX_ITEMS) break;
      inventory[key] = boundedInt(value, MAX_QTY);
    }
  }

  const streakDates: string[] = [];
  const rawDates: unknown = data?.streakDates;
  if (Array.isArray(rawDates)) {
    for (const value of rawDates) {
      const date = dateOrNull(value);
      if (date !== null && !streakDates.includes(date) && streakDates.length < MAX_DATES) {
        streakDates.push(date);
      }
    }
    streakDates.sort();
  }

  const db = admin.firestore();
  const userRef = db.collection('users').doc(uid);
  const seedRef = userRef.collection('meta').doc('local_progress_seed');

  return db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    if (!userSnap.exists) {
      throw new https.HttpsError(
        'failed-precondition',
        'Create your profile (users/{uid}) before seeding progress.',
      );
    }

    // All reads before any write: Firestore transactions require that order.
    const seedSnap = await tx.get(seedRef);
    const claimsSnap = await tx.get(userRef.collection('daily_claims').limit(1));
    const historySnap = await tx.get(userRef.collection('purchase_history').limit(1));

    if (seedSnap.exists) {
      return { ok: true, credited: false, reason: 'already-seeded' };
    }
    const u = userSnap.data()!;
    if (u['coins'] !== undefined || u['daily_streak'] !== undefined) {
      // The trusted backend has already taken ownership — never overwrite it.
      return { ok: true, credited: false, reason: 'remote-wallet-exists' };
    }
    if (!claimsSnap.empty || !historySnap.empty) {
      return { ok: true, credited: false, reason: 'remote-progress-exists' };
    }

    tx.update(userRef, {
      coins,
      gems,
      inventory,
      daily_streak: dailyStreak,
      last_streak_date: lastStreakDate,
      streak_dates: streakDates,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.set(seedRef, {
      seeded_at: admin.firestore.FieldValue.serverTimestamp(),
      coins,
      gems,
      daily_streak: dailyStreak,
    });

    return { ok: true, credited: true, coins, gems, dailyStreak };
  });
});
