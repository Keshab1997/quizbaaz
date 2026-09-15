# P0 Security Fixes — Owner's Playbook

> **Date:** 2026-09-13 · **Branch:** `fix/p0-security`
> **Scope:** PROJECT_REVIEW.md findings **R01, R02, R03** (the three P0 items)
> **Companion test matrix:** `tool/security/` (`npm test`)

## TL;DR — what changed

| Item | Before | After |
|---|---|---|
| **R01** Upload secret | ImgBB API key hardcoded in `lib/data/services/imgbb_service.dart`, shipped in every build | **Key removed from source.** Admin avatar/shop uploads go to **Firebase Storage** (`content/avatars`, `content/shop`) authorized by storage rules (admin claim + image + < 5 MB). No secret in the client. |
| **R02** Wallet/admin authority | Any signed-in client could write `coins`, `gems`, `xp`, `level`, `daily_streak`, `inventory`, `is_admin` on its own `users/{uid}` doc; set itself winner in battle rooms; accept its own challenges | **`firestore.rules` v2.0.0** denies client writes that touch any sensitive field (create *and* update). Admin authority = **Firebase custom claim `admin: true`** (never a profile field). Battle room: opponent side / questions / difficulty / `winner` frozen for clients. Challenges: legal transitions only. Leaderboard: own entry, bounded score. Gifts: server-dispatched only. **New trusted backend** in `/functions` owns the actual credits (see below). |
| **R03** Rules ≠ features | `question_banks`, `question_categories`, `shop_items`, `avatars`, `admin_audit_logs`, `quiz_history`, `purchase_history`, `config`, `champions` had no or wrong contracts (reads denied for signed-in users, writes open to everyone) | Full **collection × actor × operation contract** in `firestore.rules` (v2.0.0): signed-in reads, admin-claim-only writes, admin-only audit logs. |

### Client changes (fail-soft — app behaviour unchanged until you deploy)

- `FirestoreService.saveUser` now pushes **profile fields only** (`UserModel.profileToJson()`). Sending wallet/admin fields would fail under the new rules, so the client no longer sends them.
- `BattleRoomService.finishRoom` no longer writes a remote `winner` (server-set). It fires `TrustedOpsService.resolveBattle` (no-op until the functions are deployed).
- `SyncService.pushGift` is a no-op (gifts are server-dispatched; queued gift writes could never succeed and would clog the outbox — R14).
- `TrustedOpsService` (new) wraps the four callables. Every call is best-effort and logged, never blocking.
- Admin screens (`avatar_manager_screen`, `shop_manager_screen`) upload via `ImageUploadService` (Firebase Storage) instead of ImgBB.

### Trusted backend (`/functions`, TypeScript)

| Callable | What it does |
|---|---|
| `setAdmin` | Grants/revokes the `admin` custom claim. Access: existing admin, or the **bootstrap account** whose uid matches the `INITIAL_ADMIN_UID` secret. |
| `submitDailyResult` | Server-computed daily credit (config-driven coins/gems, streak, xp, leaderboard entry), **idempotent per day** via `users/{uid}/daily_claims/{date}`, Asia/Kolkata date, bounded inputs. |
| `purchaseItem` | Atomic purchase: price/currency/quantity read from `shop_items` (client never supplies price), balance checked in a transaction, deduct + grant + `purchase_history`, idempotent per `purchaseId`. |
| `resolveBattle` | Re-reads the room, derives winner from reported scores (score → correct → draw), writes `status`/`winner`/`resolved` (Admin SDK), idempotent via `resolved`. |

> Note: `submitDailyResult` v1 credits the **plain config formula** (no booster
> multiplier) — strictly no more generous than the old client path.

## ⚠️ YOUR actions (in this order)

1. **Rotate the exposed ImgBB key NOW.**
   `3c43...7aa` was committed in public source (and remains in git history).
   In the ImageBB console → *My account → API key* → generate a new key.
   The app no longer uses it. If you want it gone from **history** too, that's
   a force-push rewrite (BFG / `git filter-repo`) — decide separately; the key
   itself is useless after rotation.
2. **Deploy the rules** (they are the wall — do this before anything else):
   ```bash
   firebase use quizbaaz-740bd
   firebase deploy --only firestore:rules,storage
   ```
3. **Deploy the functions** (from `functions/`):
   ```bash
   cd functions && npm install && npm run build && cd ..
   firebase functions:secrets:set INITIAL_ADMIN_UID   # paste YOUR Firebase uid
   firebase deploy --only functions
   ```
4. **Grant yourself the admin claim** (one time):
   - sign in as the bootstrap account and call `setAdmin({ uid: '<your-uid>', admin: true })`
     (e.g. a tiny Dart snippet or Firebase console → *Authentication → Users →
     set custom claims*), or set the claim directly in the console.
   - After you have an admin, `firebase functions:secrets:clear INITIAL_ADMIN_UID`.
   - Claims appear in client tokens within ~5 minutes (token refresh).
5. **Verify:**
   - `cd tool/security && npm test` (starts the Firestore emulator locally and
     runs the positive/negative matrix).
   - In the app: admin panel content writes (question bank, shop, config)
     should work for the admin account; a normal account trying to write
     `coins` directly (e.g. via a patched client or Firestore console test)
     must be denied.
6. **Re-deploy the client** (Android build) so the shipped app matches the
   rules.

## Rollback

Everything is fail-soft: if you deploy the rules **without** the functions,
the app still runs (local economy unchanged; remote wallet mirroring is just
not written). If something misbehaves, `firebase deploy --only firestore:rules`
with the previous `firestore.rules` (tag `e74fb6e`) restores the old policy.

## Verification evidence (this branch)

- `flutter analyze` — clean (Flutter 3.47.4 / Dart 3.13.3).
- `flutter test` — 92 passed / 2 failed = **identical to the pre-fix
  baseline** (the 2 failures are the pre-existing R06 Firebase-bootstrap
  widget tests, unchanged).
- `functions` — `tsc --noEmit` clean.
- `tool/security` — 20-test matrix covering the review's R02/R03
  "Done when" criteria (self-escalation, wallet writes, winner
  declaration, challenge transitions, content/admin separation).

## Known follow-ups (P1/P2, not part of this fix)

- R04/R05 — UID-based account linking & logout isolation.
- R06 — Firebase-free constructors (the 2 failing widget tests).
- R13 — `max()` merge of consumables; R14 — outbox hygiene.
- Trusted **gift settlement** (claim state server-confirmed).
- Profile visibility: `users` list is readable by any signed-in user (pre-
  existing); tighten per-field (P2) once a display-view collection exists.
- Booster multipliers in server-side daily credit (v1 deliberately credits
  the plain formula).
