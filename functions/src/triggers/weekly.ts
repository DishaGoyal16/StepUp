import { COL } from '../config';
import { nowMs } from '../lib/clock';
import { db } from '../lib/firebase';
import { addDays, dayKeyOf, weekKeyOfDay } from '../lib/time';

/** Hourly: set publicProfiles.weeklyVerifiedSteps for the current IST week (and reset stale values at week change). */
export async function runRefreshWeeklySteps(): Promise<{ updated: number }> {
  const firestore = db();
  const today = dayKeyOf(nowMs());
  const weekStart = weekKeyOfDay(today);
  const weekEnd = addDays(weekStart, 6);
  const snap = await firestore.collection(COL.dailyStepSummaries).where('dayKey', '>=', weekStart).where('dayKey', '<=', weekEnd).get();
  const sums = new Map<string, number>();
  for (const d of snap.docs) {
    const x = d.data();
    sums.set(String(x.uid), (sums.get(String(x.uid)) ?? 0) + Number(x.verifiedSteps ?? 0));
  }
  let updated = 0;
  const uids = [...sums.keys()];
  for (let i = 0; i < uids.length; i += 200) {
    const chunk = uids.slice(i, i + 200);
    const users = await firestore.getAll(...chunk.map((u) => firestore.collection(COL.users).doc(u)));
    const pubs = await firestore.getAll(...chunk.map((u) => firestore.collection(COL.publicProfiles).doc(u)));
    for (let j = 0; j < chunk.length; j++) {
      if (!users[j].exists || !pubs[j].exists) continue;
      const show = users[j].data()?.privacy?.showWeeklySteps !== false;
      const value = show ? (sums.get(chunk[j]) as number) : null;
      if (pubs[j].data()?.weeklyVerifiedSteps !== value) {
        await pubs[j].ref.update({ weeklyVerifiedSteps: value });
        updated++;
      }
    }
  }
  // Week rollover: anyone with a positive value who has no steps this week goes back to 0.
  const stale = await firestore.collection(COL.publicProfiles).where('weeklyVerifiedSteps', '>', 0).get();
  for (const p of stale.docs) {
    if (!sums.has(p.id)) {
      await p.ref.update({ weeklyVerifiedSteps: 0 });
      updated++;
    }
  }
  return { updated };
}
