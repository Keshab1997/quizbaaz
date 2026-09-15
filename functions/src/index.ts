// ============================================================================
// QuizBaaz 3D — trusted backend entry point
// ----------------------------------------------------------------------------
// These callables are the SERVER-AUTHORITY path for economy and competitive
// state (P0 security fix, R02):
//
//   * setAdmin          — issue/revoke the `admin` custom claim (bootstrap).
//   * submitDailyResult — server-computed, once-per-day daily quiz credit.
//   * purchaseItem      — atomic server-side wallet check, deduct & grant.
//   * resolveBattle     — server-declared battle winner (clients can't).
//
// Clients remain offline-first: the game runs locally in Hive, and these
// operations fire when the player is signed in + online. Until this project
// is deployed, the client fail-softs and keeps its local behaviour.
//
// Deploy:
//   cd functions && npm install && npm run build
//   firebase deploy --only functions
//
// Bootstrap (once):
//   firebase functions:secrets:set INITIAL_ADMIN_UID
//   (paste your own Firebase uid) — then call setAdmin from that account.
// ============================================================================
import * as admin from 'firebase-admin';
import { setAdmin } from './admin';
import { submitDailyResult } from './daily';
import { purchaseItem } from './shop';
import { resolveBattle } from './battle';

if (!admin.apps.length) {
  admin.initializeApp();
}

export { setAdmin, submitDailyResult, purchaseItem, resolveBattle };
