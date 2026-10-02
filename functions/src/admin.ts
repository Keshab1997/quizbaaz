// Admin claim bootstrap & management (R02 — server-issued authority).
import * as admin from 'firebase-admin';
import { https, logger } from 'firebase-functions/v1';
import { callable } from './options';

const UID_PATTERN = /^[a-zA-Z0-9_-]{6,128}$/;

/**
 * Grants or revokes the `admin` custom claim on a Firebase user.
 *
 * Access:
 *  - callers that already hold the `admin` claim, or
 *  - the bootstrap caller whose uid matches the INITIAL_ADMIN_UID secret
 *    (set with `firebase functions:secrets:set INITIAL_ADMIN_UID`). The secret
 *    is bound to this function through `callable({ secrets: [...] })`, without
 *    which `process.env.INITIAL_ADMIN_UID` would be undefined and the bootstrap
 *    path would silently never fire.
 *
 * Custom claims appear in client ID tokens after the next token refresh
 * (up to ~5 minutes); they are visible immediately in the Firebase console.
 *
 * NOTE: a claim is a *label*, not a password — only promote trusted,
 * long-lived accounts (ideally a dedicated admin account, not your
 * everyday login). Every change is written to `admin_audit_logs`.
 */
export const setAdmin = callable({ secrets: ['INITIAL_ADMIN_UID'] }).https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new https.HttpsError(
        'unauthenticated',
        'Sign in before managing admin claims.',
      );
    }

    const callerUid = context.auth.uid;
    const callerIsAdmin = context.auth.token.admin === true;
    const bootstrapUid = process.env.INITIAL_ADMIN_UID;
    const isBootstrap =
      !callerIsAdmin && !!bootstrapUid && callerUid === bootstrapUid;

    if (!callerIsAdmin && !isBootstrap) {
      throw new https.HttpsError(
        'permission-denied',
        'Only an admin (or the configured bootstrap account) may change admin claims.',
      );
    }

    const uid = typeof data?.uid === 'string' ? data.uid.trim() : '';
    const grant = data?.admin === true;
    if (!UID_PATTERN.test(uid)) {
      throw new https.HttpsError(
        'invalid-argument',
        'uid must be a valid Firebase user id.',
      );
    }

    // Guard against an admin locking themselves (and everyone) out by mistake.
    if (uid === callerUid && !grant) {
      throw new https.HttpsError(
        'failed-precondition',
        'You cannot revoke your own admin claim.',
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

    // Audit trail — best-effort: a log write must never fail the claim change.
    await admin
      .firestore()
      .collection('admin_audit_logs')
      .add({
        action: grant ? 'grant_admin' : 'revoke_admin',
        target_uid: uid,
        by_uid: callerUid,
        via_bootstrap: isBootstrap,
        at: admin.firestore.FieldValue.serverTimestamp(),
      })
      .catch((e) => logger.warn('setAdmin: audit write failed', { error: String(e) }));

    logger.info('setAdmin', { by: callerUid, uid, grant, bootstrap: isBootstrap });
    return { ok: true, uid, admin: grant };
  },
);
