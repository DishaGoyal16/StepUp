import { COL } from '../config';
import { db, FieldValue } from '../lib/firebase';
import { summarizeDay, DaySummary, StoredBucketLite, BucketState } from './validateBatch';

export function bucketDocId(uid: string, deviceId: string, startMs: number): string {
  return `${uid}_${deviceId}_${startMs}`;
}

export function summaryDocId(uid: string, dayKey: string): string {
  return `${uid}_${dayKey}`;
}

export function toLite(d: FirebaseFirestore.DocumentData): StoredBucketLite {
  return {
    rawDelta: Number(d.rawDelta ?? 0),
    serverCredited: Number(d.serverCredited ?? 0),
    state: d.state as BucketState,
    rewardEligible: d.rewardEligible === true,
  };
}

/**
 * Idempotent recomputation of a user's day summary from the STORED buckets (never blind increments).
 * Writes the summary only if it differs, so a re-run is a no-op (and does not re-fire the trigger).
 */
export async function recomputeDailySummary(
  uid: string,
  dayKey: string,
  hostelId?: string | null,
): Promise<DaySummary & { changed: boolean }> {
  const firestore = db();
  const snap = await firestore.collection(COL.stepBuckets).where('uid', '==', uid).where('dayKey', '==', dayKey).get();
  const summary = summarizeDay(snap.docs.map((d) => toLite(d.data())));
  const ref = firestore.collection(COL.dailyStepSummaries).doc(summaryDocId(uid, dayKey));
  const changed = await firestore.runTransaction(async (tx) => {
    const cur = await tx.get(ref);
    const c = cur.data();
    if (
      cur.exists &&
      c &&
      c.rawSteps === summary.rawSteps &&
      c.verifiedSteps === summary.verifiedSteps &&
      c.rejectedSteps === summary.rejectedSteps &&
      c.unwitnessedSteps === summary.unwitnessedSteps
    ) {
      return false;
    }
    let hid = hostelId;
    if (hid === undefined) hid = (c?.hostelId as string | undefined) ?? null;
    tx.set(ref, { uid, dayKey, hostelId: hid, ...summary, updatedAt: FieldValue.serverTimestamp() });
    return true;
  });
  return { ...summary, changed };
}

/** dayKey -> verifiedSteps for every stored summary of the user (one query; derive all periods from it). */
export async function loadUserDays(uid: string): Promise<Map<string, number>> {
  const snap = await db().collection(COL.dailyStepSummaries).where('uid', '==', uid).get();
  const m = new Map<string, number>();
  for (const d of snap.docs) {
    const x = d.data();
    m.set(String(x.dayKey), Number(x.verifiedSteps ?? 0));
  }
  return m;
}
