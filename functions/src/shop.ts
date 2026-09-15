// Trusted shop purchase (R02 — server-side wallet ledger).
import * as admin from 'firebase-admin';
import { https } from 'firebase-functions/v1';

const db = () => admin.firestore();

/**
 * Atomic purchase:
 *   * the item's price/currency/quantity come from `shop_items` — a client
 *     never supplies its own price,
 *   * balance is checked inside a transaction,
 *   * deduct + inventory grant + purchase history happen atomically,
 *   * idempotent per client-generated purchase id (safe to retry).
 */
export const purchaseItem = https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new https.HttpsError('unauthenticated', 'Sign in first.');
    }
    const uid = context.auth.uid;

    const itemId = typeof data?.itemId === 'string' ? data.itemId.trim() : '';
    const purchaseId =
      typeof data?.purchaseId === 'string' ? data.purchaseId.trim() : '';
    if (!/^[a-z0-9_-]{1,64}$/.test(itemId)) {
      throw new https.HttpsError('invalid-argument', 'Bad itemId.');
    }
    if (!/^[a-zA-Z0-9_-]{6,64}$/.test(purchaseId)) {
      throw new https.HttpsError('invalid-argument', 'Bad purchaseId.');
    }

    const itemRef = db().collection('shop_items').doc(itemId);
    const userRef = db().collection('users').doc(uid);
    const historyRef = userRef.collection('purchase_history').doc(purchaseId);

    return db().runTransaction(async (tx) => {
      const previous = await tx.get(historyRef);
      if (previous.exists) {
        return { ok: true, credited: false, reason: 'already-purchased' };
      }

      const itemSnap = await tx.get(itemRef);
      if (!itemSnap.exists) {
        throw new https.HttpsError(
          'not-found',
          `Unknown shop item: ${itemId}.`,
        );
      }
      const item = itemSnap.data()!;
      if (item['is_active'] === false) {
        throw new https.HttpsError(
          'failed-precondition',
          'This item is not active.',
        );
      }
      const price = Number(item['price']);
      if (!Number.isFinite(price) || price < 0) {
        throw new https.HttpsError(
          'internal',
          'Shop item has an invalid price.',
        );
      }
      const currency = item['currency'] === 'gems' ? 'gems' : 'coins';
      const quantity =
        Number(item['quantity']) > 0 ? Math.floor(Number(item['quantity'])) : 1;

      const userSnap = await tx.get(userRef);
      if (!userSnap.exists) {
        throw new https.HttpsError(
          'failed-precondition',
          'Create your profile (users/{uid}) before purchasing.',
        );
      }
      const u = userSnap.data()!;
      const balance = Number(u[currency] ?? 0);
      if (balance < price) {
        throw new https.HttpsError(
          'failed-precondition',
          `Insufficient ${currency} (have ${balance}, need ${price}).`,
        );
      }

      const inventory = {
        ...((u['inventory'] as Record<string, number>) ?? {}),
      };
      inventory[itemId] = (inventory[itemId] ?? 0) + quantity;

      tx.update(userRef, {
        [currency]: admin.firestore.FieldValue.increment(-price),
        inventory,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      tx.set(historyRef, {
        item_id: itemId,
        item_name: (item['name'] as string) ?? itemId,
        price,
        currency,
        quantity,
        balance_after: balance - price,
        purchased_at: new Date().toISOString(),
      });

      return {
        ok: true,
        credited: true,
        itemId,
        price,
        currency,
        quantity,
        balanceAfter: balance - price,
      };
    });
  },
);
