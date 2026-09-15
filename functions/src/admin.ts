// Admin claim bootstrap & management (R02 — server-issued authority).
import * as admin from 'firebase-admin';
import { https } from 'firebase-functions/v1';

/**
 * Grants or revokes the `admin` custom claim on a Firebase user.
 *
 * Access:
 *  - callers that already hold the `admin` claim, or
 *  - the bootstrap caller whose uid matches the INITIAL_ADMIN_UID secret
 *    (set with `firebase functions:secrets:set INITIAL_ADMIN_UID`).
 *
 * Custom claims appear in client ID tokens after the next token refresh
 * (up to ~5 minutes); they are visible immediately in the Firebase console.
 *
 * NOTE: a claim is a *label*, not a password — only promote trusted,
 * long-lived accounts (ideally a dedicated admin account, not your
 * everyday login).
 */
export const setAdmin = https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new https.HttpsError(
        'unauthenticated',
        'Sign in before managing admin claims.',
      );
    }

    const callerIsAdmin = context.auth.token.admin === true;
    const bootstrapUid = process.env.INITIAL_ADMIN_UID;
    const isBootstrap =
      !callerIsAdmin && !!bootstrapUid && context.auth.uid === bootstrapUid;

    if (!callerIsAdmin && !isBootstrap) {
      throw new https.HttpsError(
        'permission-denied',
        'Only an admin (or the configured bootstrap account) may change admin claims.',
      );
    }

    const uid = typeof data?.uid === 'string' ? data.uid.trim() : '';
    const grant = data?.admin === true;
    if (!/^[a-zA-Z0-9_-]{6,128}$/.test(uid)) {
      throw new https.HttpsError(
        'invalid-argument',
        'uid must be a valid Firebase user id.',
      );
    }

    const user = await admin.auth().getUser(uid).catch(() => null);
    if (!user) {
      throw new https.HttpsError(
        'not-found',
        `No Firebase user with uid ${uid}.`,
      );
    }

    await admin.auth().setCustomUserClaims(uid, grant ? { admin: true } : null);
    return { ok: true, uid, admin: grant };
  },
);
