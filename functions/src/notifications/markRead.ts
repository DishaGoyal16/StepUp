import { COL } from '../config';
import { Req, requireEligibleUser } from '../lib/auth';
import { fail } from '../lib/errors';
import { db } from '../lib/firebase';
import { asRecord } from '../lib/validate';

export async function handleMarkNotificationsRead(req: Req): Promise<{ ok: true; updated: number }> {
  const caller = await requireEligibleUser(req, { allowDeletionRequested: true });
  const d = asRecord(req.data ?? {});
  const firestore = db();
  let refs: FirebaseFirestore.DocumentReference[];
  if (d.ids !== undefined && d.ids !== null) {
    if (!Array.isArray(d.ids) || d.ids.length > 200 || d.ids.some((x) => typeof x !== 'string' || x.length < 1 || x.length > 300 || x.includes('/'))) {
      fail('invalid-argument', 'INVALID_IDS');
    }
    const snaps = await firestore.getAll(...(d.ids as string[]).map((i) => firestore.collection(COL.notifications).doc(i)));
    // Only the caller's own, still-unread notifications are touched; foreign ids are ignored.
    refs = snaps.filter((s) => s.exists && s.data()?.uid === caller.uid && s.data()?.read !== true).map((s) => s.ref);
  } else {
    const q = await firestore.collection(COL.notifications).where('uid', '==', caller.uid).where('read', '==', false).limit(500).get();
    refs = q.docs.map((x) => x.ref);
  }
  let updated = 0;
  for (let i = 0; i < refs.length; i += 400) {
    const batch = firestore.batch();
    for (const r of refs.slice(i, i + 400)) batch.update(r, { read: true });
    await batch.commit();
    updated += Math.min(400, refs.length - i);
  }
  return { ok: true, updated };
}
