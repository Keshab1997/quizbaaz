// Trusted battle settlement (R02 — clients can never declare a remote winner).
import * as admin from 'firebase-admin';
import { https } from 'firebase-functions/v1';

const db = () => admin.firestore();

interface RoomPlayer {
  uid: string;
  score: number;
  correct: number;
}

/**
 * A player in the room calls this to close it. The server re-reads the room,
 * derives the winner from the reported scores (higher score wins; tie -> more
 * correct answers; still tied -> draw) and writes `status: finished`,
 * `winner` and the `resolved` marker — fields the client is not allowed to
 * set under the Firestore rules.
 *
 * The client sends the `matchId` of the session it just played. A rematch
 * reuses the deterministic room id, so idempotency is keyed on
 * **room + match**: the same match never settles twice, a *new* match in a
 * previously settled room is settled as its own match (R11).
 *
 * Returns a receipt the client can display/log:
 * `{ ok, winner, matchId, reason }` — `reason` is `resolved` or
 * `already-resolved`.
 */
export const resolveBattle = https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new https.HttpsError('unauthenticated', 'Sign in first.');
    }
    const callerUid = context.auth.uid;
    const roomId = typeof data?.roomId === 'string' ? data.roomId.trim() : '';
    if (!/^room_[a-zA-Z0-9_-]+_[a-zA-Z0-9_-]+$/.test(roomId)) {
      throw new https.HttpsError('invalid-argument', 'Bad roomId.');
    }

    const matchId =
      typeof data?.matchId === 'string' ? data.matchId.trim() : '';
    if (matchId.length > 128) {
      throw new https.HttpsError('invalid-argument', 'Bad matchId.');
    }

    const roomRef = db().collection('battle_rooms').doc(roomId);

    return db().runTransaction(async (tx) => {
      const snap = await tx.get(roomRef);
      if (!snap.exists) {
        throw new https.HttpsError('not-found', 'Room not found.');
      }
      const room = snap.data()!;
      const players = room['players'] as { a: RoomPlayer; b: RoomPlayer } | undefined;
      if (!players?.a?.uid || !players?.b?.uid) {
        throw new https.HttpsError('internal', 'Room is malformed.');
      }
      if (
        players.a.uid !== callerUid &&
        players.b.uid !== callerUid
      ) {
        throw new https.HttpsError(
          'permission-denied',
          'Only a player in this room may resolve it.',
        );
      }
      // Same match already settled → replay the receipt (idempotent).
      // A different matchId means a rematch in the same room: settle again.
      const settledMatchId =
        typeof room['match_id'] === 'string' ? room['match_id'] : '';
      if (room['resolved'] === true && settledMatchId === matchId) {
        return {
          ok: true,
          winner: room['winner'] ?? null,
          matchId,
          reason: 'already-resolved',
        };
      }

      const aScore = Number(players.a.score ?? 0);
      const bScore = Number(players.b.score ?? 0);
      const aCorrect = Number(players.a.correct ?? 0);
      const bCorrect = Number(players.b.correct ?? 0);

      let winner: string | null;
      if (aScore !== bScore) {
        winner = aScore > bScore ? players.a.uid : players.b.uid;
      } else if (aCorrect !== bCorrect) {
        winner = aCorrect > bCorrect ? players.a.uid : players.b.uid;
      } else {
        winner = null; // draw
      }

      tx.update(roomRef, {
        status: 'finished',
        winner,
        resolved: true,
        ...(matchId ? { match_id: matchId } : {}),
        resolved_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { ok: true, winner, matchId, reason: 'resolved' };
    });
  },
);
