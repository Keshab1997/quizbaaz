// ============================================================================
// QuizBaaz 3D — Firestore rules test matrix (P0 R02 / R03)
// ----------------------------------------------------------------------------
// Positive + negative cases for guest / student / admin actors against
// firestore.rules (v2.0.0). Run with `npm test` in this directory (the
// Firestore emulator is started automatically by scripts/ensure_emulator.mjs).
//
// "Done when" (PROJECT_REVIEW.md):
//   * emulator negative tests deny sensitive writes            ✔ section 1-2
//   * valid profile edits / content reads work                 ✔ section 1-2
//   * a modified client cannot surface arbitrary rank/reward/
//     admin state                                              ✔ section 3-8
// ============================================================================
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  withSecurityRulesDisabled,
} from '@firebase/rules-unit-testing';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RULES = readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8');
const PROJECT = 'quizbaaz-740bd';
const HOST = process.env.FIRESTORE_EMULATOR_HOST ?? 'localhost:8080';

const STUDENT = 'student-a';
const OTHER = 'student-b';
const ADMIN = 'admin-a';

const PROFILE = {
  user_id: STUDENT,
  username: 'kesab',
  full_name: 'Keshab',
  avatar_path: 'assets/images/avatars/quizbaaz_avatar_boy.png',
  gender: 'male',
  is_guest: false,
};

/** Fresh namespace per environment — isolated data between tests. */
async function makeEnv(uid, claims) {
  return initializeTestEnvironment({
    projectId: PROJECT,
    rules: RULES,
    localHost: HOST,
    auth: uid ? { uid, token: claims ?? {} } : null,
  });
}

async function seed(env, docs) {
  await withSecurityRulesDisabled(async (ctx) => {
    for (const [ref, data] of Object.entries(docs)) {
      const [col, doc] = ref.split('/');
      await ctx.firestore.collection(col).doc(doc).set(data);
    }
  });
}

const ROOM_ID = 'room_student-a_student-b';
const roomData = (status = 'active', winner = null) => ({
  difficulty: 'normal',
  status,
  created_at: 1_757_000_000_000,
  questions: [{ id: 'q1', options: ['a', 'b'] }],
  state: { phase: 'countdown', q_index: 0 },
  players: {
    a: { uid: STUDENT, name: 'K', avatar: 'x', score: 10, correct: 1, streak: 1, ready_for_next: 0, last_seen: 1, answers: {} },
    b: { uid: OTHER, name: 'B', avatar: 'y', score: 20, correct: 2, streak: 2, ready_for_next: 0, last_seen: 1, answers: {} },
  },
  winner,
});

const challengeData = {
  from_uid: STUDENT,
  from_name: 'K',
  from_avatar: 'x',
  from_avatar_url: '',
  from_level: 1,
  to_uid: OTHER,
  to_name: 'B',
  to_avatar: 'y',
  to_avatar_url: '',
  difficulty: 'normal',
  status: 'pending',
  created_at: 1_757_000_000_000,
  expires_at: 1_757_000_3600_000,
};

// ---------------------------------------------------------------------------
// 1. Guest (unauthenticated)
// ---------------------------------------------------------------------------
test('guest: cannot read user profiles or content', async () => {
  const env = await makeEnv(null);
  await seed(env, {
    'users/student-a': PROFILE,
    'question_banks/ch1': { title: 'Ch 1' },
    'config/app': { daily_question_count: 10 },
  });
  await assertFails(env.firestore.collection('users').doc('student-a').get());
  await assertFails(env.firestore.collection('users').listDocs());
  await assertFails(env.firestore.collection('question_banks').doc('ch1').get());
  await assertFails(env.firestore.collection('config').doc('app').get());
  await assertFails(env.firestore.collection('users').doc('student-a').set(PROFILE));
  await env.cleanup();
});

// ---------------------------------------------------------------------------
// 2. Profile writes — the client-authority wall (R02)
// ---------------------------------------------------------------------------
test('profile: owner create with profile fields only -> allowed', async () => {
  const env = await makeEnv(STUDENT);
  await assertSucceeds(env.firestore.collection('users').doc(STUDENT).set(PROFILE));
  await env.cleanup();
});

test('profile: owner create smuggling coins/is_admin/inventory -> denied', async () => {
  const env = await makeEnv(STUDENT);
  for (const extra of [
    { coins: 999999 },
    { is_admin: true },
    { inventory: { fiftyFifty: 99 } },
    { xp: 100000, level: 999 },
    { gems: 5000 },
    { daily_streak: 365, played_today_daily_quiz: true, last_streak_date: '2026-09-13' },
  ]) {
    await assertFails(
      env.firestore.collection('users').doc(STUDENT).set({ ...PROFILE, ...extra }),
      `create with ${Object.keys(extra).join(',')} must fail`,
    );
  }
  await env.cleanup();
});

test('profile: owner update of display fields -> allowed', async () => {
  const env = await makeEnv(STUDENT);
  await seed(env, { 'users/student-a': PROFILE });
  await assertSucceeds(
    env.firestore.collection('users').doc(STUDENT).set({ username: 'kesab2' }, { merge: true }),
  );
  await assertSucceeds(
    env.firestore.collection('users').doc(STUDENT).set({ avatar_url: 'https://example.com/a.png' }, { merge: true }),
  );
  await env.cleanup();
});

test('profile: owner update of sensitive fields -> denied (self-escalation blocked)', async () => {
  const env = await makeEnv(STUDENT);
  await seed(env, { 'users/student-a': PROFILE });
  for (const field of ['coins', 'gems', 'xp', 'level', 'daily_streak', 'inventory', 'is_admin', 'played_today_daily_quiz']) {
    await assertFails(
      env.firestore.collection('users').doc(STUDENT).set({ [field]: 1 }, { merge: true }),
      `self-update ${field} must fail`,
    );
  }
  await env.cleanup();
});

test('profile: another user cannot edit my document', async () => {
  const env = await makeEnv(OTHER);
  await seed(env, { 'users/student-a': PROFILE });
  await assertFails(
    env.firestore.collection('users').doc(STUDENT).set({ username: 'hacked' }, { merge: true }),
  );
  await assertFails(env.firestore.collection('users').doc(STUDENT).delete());
  await env.cleanup();
});

test('profile: admin (claim) may edit any field incl. wallet', async () => {
  const env = await makeEnv(ADMIN, { admin: true });
  await seed(env, { 'users/student-a': PROFILE });
  await assertSucceeds(
    env.firestore.collection('users').doc(STUDENT).set({ coins: 100, gems: 5 }, { merge: true }),
  );
  await env.cleanup();
});

// ---------------------------------------------------------------------------
// 3. Content collections — the R03 gap (reads denied, writes open)
// ---------------------------------------------------------------------------
test('content: signed-in reads allowed, non-admin writes denied, admin writes allowed', async () => {
  const content = [
    ['question_banks', 'ch1'],
    ['question_categories', 'science'],
    ['shop_items', 'fiftyFifty'],
    ['avatars', 'av1'],
  ];
  const student = await makeEnv(STUDENT);
  const admin = await makeEnv(ADMIN, { admin: true });
  // Seed in the student namespace (shared rules, separate data): reads are
  // evaluated per-namespace, so seed on each env as needed.
  await seed(student, Object.fromEntries(content.map(([c, d]) => [`${c}/${d}`, { name: 'x' }])));
  await seed(admin, Object.fromEntries(content.map(([c, d]) => [`${c}/${d}`, { name: 'x' }])));

  for (const [col, doc] of content) {
    await assertSucceeds(student.firestore.collection(col).doc(doc).get(), `read ${col}`);
    await assertFails(student.firestore.collection(col).doc(doc).set({ name: 'evil' }), `write ${col}`);
    await assertSucceeds(admin.firestore.collection(col).doc(doc).set({ name: 'ok' }), `admin write ${col}`);
  }
  // Subcollections
  await assertFails(student.firestore.collection('question_banks').doc('ch1').collection('questions').doc('q1').set({}));
  await assertSucceeds(admin.firestore.collection('question_banks').doc('ch1').collection('questions').doc('q1').set({ id: 'q1' }));
  await assertFails(student.firestore.collection('question_categories').doc('science').collection('chapters').doc('c1').set({}));
  await assertSucceeds(admin.firestore.collection('question_categories').doc('science').collection('chapters').doc('c1').set({}));
  await student.cleanup();
  await admin.cleanup();
});

test('content: admin_audit_logs is admin-only (read + write)', async () => {
  const student = await makeEnv(STUDENT);
  const admin = await makeEnv(ADMIN, { admin: true });
  await seed(admin, { 'admin_audit_logs/l1': { action: 'save' } });
  await assertFails(student.firestore.collection('admin_audit_logs').doc('l1').get());
  await assertSucceeds(admin.firestore.collection('admin_audit_logs').doc('l1').get());
  await assertSucceeds(admin.firestore.collection('admin_audit_logs').doc('l2').set({ action: 'x' }));
  await assertFails(student.firestore.collection('admin_audit_logs').doc('l3').set({ action: 'x' }));
  await student.cleanup();
  await admin.cleanup();
});

// ---------------------------------------------------------------------------
// 4. Config & champions — admin-only writes
// ---------------------------------------------------------------------------
test('config & champions: student reads, admin writes, student writes denied', async () => {
  const student = await makeEnv(STUDENT);
  const admin = await makeEnv(ADMIN, { admin: true });
  await seed(student, { 'config/app': { daily_question_count: 10 } });
  await seed(admin, { 'config/app': { daily_question_count: 10 } });

  await assertSucceeds(student.firestore.collection('config').doc('app').get());
  await assertFails(student.firestore.collection('config').doc('app').set({ daily_question_count: 999 }));
  await assertSucceeds(admin.firestore.collection('config').doc('app').set({ daily_question_count: 10 }));

  await assertFails(student.firestore.collection('champions').doc('2026-09-12').collection('winners').doc(STUDENT).set({ rank: 1 }));
  await assertSucceeds(admin.firestore.collection('champions').doc('2026-09-12').collection('winners').doc(STUDENT).set({ rank: 1 }));
  await assertSucceeds(student.firestore.collection('champions').doc('2026-09-12').collection('winners').doc(STUDENT).get());
  await student.cleanup();
  await admin.cleanup();
});

// ---------------------------------------------------------------------------
// 5. Battle challenges — legal transitions only
// ---------------------------------------------------------------------------
test('challenge: sender creates pending; impersonation & pre-accepted denied', async () => {
  const env = await makeEnv(STUDENT);
  await assertSucceeds(env.firestore.collection('battle_challenges').doc('ch1').set(challengeData));
  await assertFails(
    env.firestore.collection('battle_challenges').doc('ch2').set({ ...challengeData, from_uid: OTHER }),
  );
  await assertFails(
    env.firestore.collection('battle_challenges').doc('ch3').set({ ...challengeData, status: 'accepted' }),
  );
  await env.cleanup();
});

test('challenge: receiver accepts; sender may not accept own challenge', async () => {
  const receiver = await makeEnv(OTHER);
  const sender = await makeEnv(STUDENT);
  await seed(receiver, { 'battle_challenges/ch1': challengeData });
  await seed(sender, { 'battle_challenges/ch1': challengeData });

  await assertSucceeds(receiver.firestore.collection('battle_challenges').doc('ch1').update({ status: 'accepted' }));
  await assertFails(sender.firestore.collection('battle_challenges').doc('ch1').update({ status: 'accepted' }));
  await receiver.cleanup();
  await sender.cleanup();
});

test('challenge: sender cancels; receiver may not cancel', async () => {
  const sender = await makeEnv(STUDENT);
  const receiver = await makeEnv(OTHER);
  await seed(sender, { 'battle_challenges/ch1': challengeData });
  await seed(receiver, { 'battle_challenges/ch1': challengeData });

  await assertSucceeds(sender.firestore.collection('battle_challenges').doc('ch1').update({ status: 'cancelled' }));
  await assertFails(receiver.firestore.collection('battle_challenges').doc('ch1').update({ status: 'cancelled' }));
  await sender.cleanup();
  await receiver.cleanup();
});

test('challenge: identities & difficulty are immutable', async () => {
  const env = await makeEnv(OTHER);
  await seed(env, { 'battle_challenges/ch1': challengeData });
  await assertFails(env.firestore.collection('battle_challenges').doc('ch1').update({ to_uid: STUDENT }));
  await assertFails(env.firestore.collection('battle_challenges').doc('ch1').update({ difficulty: 'hard' }));
  await env.cleanup();
});

// ---------------------------------------------------------------------------
// 6. Battle rooms — own-side only; winner is server-owned
// ---------------------------------------------------------------------------
test('room: creator must be a player; winner must be null at create', async () => {
  const env = await makeEnv(STUDENT);
  const outsider = await makeEnv('outsider-x');
  await assertSucceeds(env.firestore.collection('battle_rooms').doc(ROOM_ID).set(roomData()));
  // outsider-x is NOT one of the two players in this room -> denied
  await assertFails(
    outsider.firestore.collection('battle_rooms').doc('room_other-z_third-zed').set({
      ...roomData(),
      players: { a: { uid: 'other-z' }, b: { uid: 'third-zed' } },
    }),
  );
  await assertFails(env.firestore.collection('battle_rooms').doc('room_x_y').set({ ...roomData(), winner: 'x' }));
  await env.cleanup();
  await outsider.cleanup();
});

test('room: player updates own side; opponent side is frozen', async () => {
  const env = await makeEnv(STUDENT);
  await seed(env, { [`battle_rooms/${ROOM_ID}`]: roomData() });
  // Own side (a):
  await assertSucceeds(env.firestore.collection('battle_rooms').doc(ROOM_ID).set({ players: { a: { score: 20, correct: 2 } } }, { merge: true }));
  // Opponent side (b) frozen for me:
  await assertFails(env.firestore.collection('battle_rooms').doc(ROOM_ID).set({ players: { b: { score: 999 } } }, { merge: true }));
  await assertFails(env.firestore.collection('battle_rooms').doc(ROOM_ID).set({ 'players.b.score': 999 }, { merge: true }));
  await env.cleanup();
});

test('room: winner/questions/difficulty immutable; only active->finished allowed', async () => {
  const env = await makeEnv(STUDENT);
  await seed(env, { [`battle_rooms/${ROOM_ID}`]: roomData() });
  await assertFails(env.firestore.collection('battle_rooms').doc(ROOM_ID).set({ winner: STUDENT }, { merge: true }));
  await assertFails(env.firestore.collection('battle_rooms').doc(ROOM_ID).set({ questions: [] }, { merge: true }));
  await assertFails(env.firestore.collection('battle_rooms').doc(ROOM_ID).set({ difficulty: 'hard' }, { merge: true }));
  await assertSucceeds(env.firestore.collection('battle_rooms').doc(ROOM_ID).set({ status: 'finished' }, { merge: true }));
  // Reversing finished -> active must be denied.
  await assertFails(env.firestore.collection('battle_rooms').doc(ROOM_ID).set({ status: 'active' }, { merge: true }));
  await env.cleanup();
});

test('room: only players can read/update; finished room deletable by player', async () => {
  const player = await makeEnv(STUDENT);
  const outsider = await makeEnv('outsider-x');
  await seed(player, { [`battle_rooms/${ROOM_ID}`]: roomData('finished') });
  await seed(outsider, { [`battle_rooms/${ROOM_ID}`]: roomData('finished') });
  await assertSucceeds(player.firestore.collection('battle_rooms').doc(ROOM_ID).get());
  await assertFails(outsider.firestore.collection('battle_rooms').doc(ROOM_ID).get());
  await assertFails(outsider.firestore.collection('battle_rooms').doc(ROOM_ID).delete());
  await assertSucceeds(player.firestore.collection('battle_rooms').doc(ROOM_ID).delete());
  await player.cleanup();
  await outsider.cleanup();
});

// ---------------------------------------------------------------------------
// 7. Leaderboard — own entry, bounded score
// ---------------------------------------------------------------------------
test('leaderboard: own bounded entry allowed; huge scores & other-user docs denied', async () => {
  const env = await makeEnv(STUDENT);
  const entry = {
    user_id: STUDENT,
    username: 'kesab',
    name: 'Keshab',
    avatar_path: 'x',
    name_effect: '',
    score: 80,
    time_seconds: 95.5,
    streak: 3,
  };
  await assertSucceeds(env.firestore.collection('leaderboard').doc('2026-09-13').collection('scores').doc(STUDENT).set(entry));
  await assertFails(env.firestore.collection('leaderboard').doc('2026-09-13').collection('scores').doc(STUDENT).set({ ...entry, score: 5000 }));
  await assertFails(env.firestore.collection('leaderboard').doc('2026-09-13').collection('scores').doc(OTHER).set({ ...entry, user_id: OTHER }));
  await assertFails(env.firestore.collection('leaderboard').doc('2026-09-13').collection('scores').doc(STUDENT).set({ ...entry, score: -5 }));
  await env.cleanup();
});

// ---------------------------------------------------------------------------
// 8. User subcollections — gifts server-owned; history owner-owned
// ---------------------------------------------------------------------------
test('gifts: client cannot mint or delete; admin can dispatch', async () => {
  const student = await makeEnv(STUDENT);
  const admin = await makeEnv(ADMIN, { admin: true });
  const giftRef = (env) => env.firestore.collection('users').doc(STUDENT).collection('gifts').doc('g1');
  await assertFails(giftRef(student).set({ name: 'free-5000-coins' }));
  await assertSucceeds(giftRef(admin).set({ name: 'champion-gift', status: 'pending' }));
  await assertSucceeds(giftRef(student).get());
  await assertFails(giftRef(student).delete());
  await student.cleanup();
  await admin.cleanup();
});

test('history & meta: owner read/write; non-owner denied; daily_claims read-only for all clients', async () => {
  const owner = await makeEnv(STUDENT);
  const other = await makeEnv(OTHER);
  await seed(owner, {
    'users/student-a': PROFILE,
    'users/student-a/quiz_history/h1': { score: 40 },
  });
  await seed(other, { 'users/student-a': PROFILE });
  await assertSucceeds(owner.firestore.collection('users').doc(STUDENT).collection('quiz_history').doc('h1').set({ score: 50 }, { merge: true }));
  await assertSucceeds(owner.firestore.collection('users').doc(STUDENT).collection('quiz_history').doc('h1').get());
  await assertFails(other.firestore.collection('users').doc(STUDENT).collection('quiz_history').doc('h1').set({ score: 1 }));
  await assertFails(other.firestore.collection('users').doc(STUDENT).collection('meta').doc('stats').set({ total: 1 }));
  await assertSucceeds(owner.firestore.collection('users').doc(STUDENT).collection('meta').doc('stats').set({ total: 1 }));
  await assertFails(owner.firestore.collection('users').doc(STUDENT).collection('daily_claims').doc('2026-09-13').set({ coins: 1 }));
  await assertFails(other.firestore.collection('users').doc(STUDENT).collection('purchase_history').doc('p1').set({}));
  await assertSucceeds(owner.firestore.collection('users').doc(STUDENT).collection('purchase_history').doc('p1').set({ item_id: 'x' }));
  await owner.cleanup();
  await other.cleanup();
});

// ---------------------------------------------------------------------------
// 9. Presence & queue — owner-only writes
// ---------------------------------------------------------------------------
test('online_users & battle_queue: owner writes allowed, impersonation denied', async () => {
  const env = await makeEnv(STUDENT);
  const other = await makeEnv(OTHER);
  await assertSucceeds(env.firestore.collection('online_users').doc(STUDENT).set({ last_seen: 1 }));
  await assertFails(other.firestore.collection('online_users').doc(STUDENT).set({ last_seen: 1 }));
  await assertSucceeds(env.firestore.collection('battle_queue').doc(STUDENT).set({ difficulty: 'normal', created_at: 1 }));
  await assertFails(other.firestore.collection('battle_queue').doc(STUDENT).set({ difficulty: 'normal', created_at: 1 }));
  await assertFails(env.firestore.collection('battle_queue').doc(STUDENT).set({ difficulty: 'nightmare', created_at: 1 }));
  await env.cleanup();
  await other.cleanup();
});
