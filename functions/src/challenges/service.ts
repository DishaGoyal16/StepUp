import { COL } from '../config';
import { db, FieldValue } from '../lib/firebase';
import { getSettings } from '../lib/settings';
import { dayKeyOf } from '../lib/time';
import { notify } from '../notifications/notify';
import { applyPoints, loadPoints, rewardOp } from '../lib/points';
import { computeProgress, Metric } from './progress';

export function participantDocId(challengeId: string, uid: string): string {
  return `${challengeId}_${uid}`;
}

/** Inclusive [startKey, endKey] day window of a participation, or null when it has not started. */
export function windowKeys(
  ch: FirebaseFirestore.DocumentData,
  p: FirebaseFirestore.DocumentData,
): [string, string] | null {
  if (ch.windowMode === 'ROLLING') {
    return p.windowStart && p.windowEnd ? [String(p.windowStart), String(p.windowEnd)] : null;
  }
  const s = ch.startAt?.toMillis?.() as number | undefined;
  const e = ch.endAt?.toMillis?.() as number | undefined;
  if (s === undefined || e === undefined) return null;
  return [dayKeyOf(s), dayKeyOf(e - 1)];
}

export function progressFor(ch: FirebaseFirestore.DocumentData, p: FirebaseFirestore.DocumentData, days: ReadonlyMap<string, number>): number {
  const w = windowKeys(ch, p);
  if (!w) return 0;
  return computeProgress(ch.metric as Metric, (ch.dailyTarget as number | null) ?? null, days, w[0], w[1]);
}

/**
 * Recompute progress of every JOINED participation of this user from `dailyStepSummaries` (via `days`).
 * Idempotent. INDIVIDUAL challenges complete (and pay once) when the target is reached; group challenges keep
 * accumulating and are decided by `finalizeChallenges`.
 */
export async function updateChallengeProgressForUser(uid: string, days: ReadonlyMap<string, number>): Promise<void> {
  const firestore = db();
  const parts = await firestore.collection(COL.challengeParticipants).where('uid', '==', uid).where('status', '==', 'JOINED').get();
  if (parts.empty) return;
  const challengeIds = [...new Set(parts.docs.map((p) => String(p.data().challengeId)))];
  const chSnaps = await firestore.getAll(...challengeIds.map((c) => firestore.collection(COL.challenges).doc(c)));
  const chById = new Map(chSnaps.filter((s) => s.exists).map((s) => [s.id, s.data() as FirebaseFirestore.DocumentData]));
  const settings = await getSettings();

  for (const pDoc of parts.docs) {
    const p = pDoc.data();
    const ch = chById.get(String(p.challengeId));
    if (!ch || ch.status === 'CANCELLED' || ch.status === 'COMPLETED' || ch.status === 'PENDING') continue;
    const progress = progressFor(ch, p, days);
    if (ch.type === 'INDIVIDUAL' && ch.target > 0 && progress >= ch.target) {
      const reward = typeof ch.rewardPoints === 'number' ? ch.rewardPoints : settings.pointsChallengeComplete;
      const done = await completeIndividual(pDoc.ref, String(p.challengeId), uid, progress, reward, String(ch.title ?? 'Challenge'));
      if (done) {
        await notify({
          uid,
          type: 'CHALLENGE_DONE',
          title: 'Challenge completed',
          body: `You completed "${ch.title}"${reward > 0 ? ` and earned ${reward} points` : ''}.`,
          data: { challengeId: String(p.challengeId) },
          dedupeKey: `chdone_${p.challengeId}_${uid}`,
        });
      }
    } else if (progress !== p.progress) {
      await pDoc.ref.update({ progress, progressUpdatedAt: FieldValue.serverTimestamp() });
    }
  }
}

async function completeIndividual(
  partRef: FirebaseFirestore.DocumentReference,
  challengeId: string,
  uid: string,
  progress: number,
  reward: number,
  title: string,
): Promise<boolean> {
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(partRef);
    if (snap.data()?.status !== 'JOINED') return false;
    const ops = reward > 0 ? [rewardOp(uid, 'CHALLENGE', challengeId, reward, `Challenge completed: ${title}`)] : [];
    const state = ops.length ? await loadPoints(tx, ops) : null;
    tx.update(partRef, {
      status: 'COMPLETED',
      progress,
      progressUpdatedAt: FieldValue.serverTimestamp(),
      completedAt: FieldValue.serverTimestamp(),
      rewardPaid: true,
    });
    if (state) applyPoints(tx, state, ops);
    return true;
  });
}
