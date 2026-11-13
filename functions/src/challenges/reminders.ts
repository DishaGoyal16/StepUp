import { COL } from '../config';
import { nowMs } from '../lib/clock';
import { db } from '../lib/firebase';
import { dayInRange, dayKeyOf } from '../lib/time';
import { notify } from '../notifications/notify';
import { windowKeys } from './service';

/** Dedupe key: at most ONE reminder per user / challenge / IST day. */
export function reminderDedupeKey(challengeId: string, dayKey: string): string {
  return `reminder_${challengeId}_${dayKey}`;
}

/** Daily 18:00 IST. Re-running (retries, double scheduling) creates nothing new because of the dedupeKey. */
export async function runChallengeReminders(): Promise<{ considered: number; sent: number }> {
  const firestore = db();
  const today = dayKeyOf(nowMs());
  let considered = 0;
  let sent = 0;
  const chCache = new Map<string, FirebaseFirestore.DocumentData | null>();
  let last: string | null = null;
  for (;;) {
    let q = firestore.collection(COL.challengeParticipants).where('status', '==', 'JOINED').orderBy('__name__').limit(300);
    if (last) q = q.startAfter(last);
    const page = await q.get();
    if (page.empty) break;
    for (const p of page.docs) {
      last = p.id;
      const d = p.data();
      const cid = String(d.challengeId);
      if (!chCache.has(cid)) {
        const c = await firestore.collection(COL.challenges).doc(cid).get();
        chCache.set(cid, c.exists ? (c.data() as FirebaseFirestore.DocumentData) : null);
      }
      const ch = chCache.get(cid);
      if (!ch || ch.status !== 'ACTIVE') continue;
      const w = windowKeys(ch, d);
      if (!w || !dayInRange(today, w)) continue;
      if (Number(d.progress ?? 0) >= Number(ch.target)) continue;
      considered++;
      const u = await firestore.collection(COL.users).doc(String(d.uid)).get();
      const ud = u.data();
      if (!ud || ud.status !== 'ACTIVE' || ud.notificationPrefs?.reminders === false) continue;
      const created = await notify({
        uid: String(d.uid),
        type: 'CHALLENGE_REMINDER',
        title: 'Keep going!',
        body: `"${ch.title}": you are at ${d.progress ?? 0} / ${ch.target}.`,
        data: { challengeId: cid },
        dedupeKey: reminderDedupeKey(cid, today),
      });
      if (created) sent++;
    }
    if (page.size < 300) break;
  }
  return { considered, sent };
}
