import { COL } from '../config';
import { nowMs } from '../lib/clock';
import { db, FieldValue, Timestamp, tsFromMs } from '../lib/firebase';
import { grantRewards } from '../lib/rewards';
import { getSettings } from '../lib/settings';
import { dayKeyOf } from '../lib/time';
import { notify } from '../notifications/notify';
import { loadUserDays } from '../steps/summaries';
import { ChallengeType, decideResult, metricLabel, Metric, ParticipantRow } from './progress';
import { participantDocId, progressFor } from './service';

export interface FinalizeReport {
  activated: number;
  finalized: number;
  rewardsPaid: number;
  participantsExpired: number;
}

/** Scheduled every 15 minutes (and callable from tests with an explicit clock). Fully idempotent. */
export async function runFinalizeChallenges(): Promise<FinalizeReport> {
  const firestore = db();
  const now = nowMs();
  const settings = await getSettings();
  const report: FinalizeReport = { activated: 0, finalized: 0, rewardsPaid: 0, participantsExpired: 0 };

  // 1) UPCOMING -> ACTIVE
  const upcoming = await firestore.collection(COL.challenges).where('status', '==', 'UPCOMING').where('startAt', '<=', tsFromMs(now)).get();
  for (const doc of upcoming.docs) {
    await doc.ref.update({ status: 'ACTIVE', updatedAt: FieldValue.serverTimestamp() });
    report.activated++;
  }

  // 2) finalize ended challenges after the settlement grace
  const cutoff = tsFromMs(now - settings.settlementGraceHours * 3_600_000);
  const ended = await firestore.collection(COL.challenges).where('status', '==', 'ACTIVE').where('endAt', '<=', cutoff).get();
  for (const doc of ended.docs) {
    if (await finalizeChallenge(doc.id)) report.finalized++;
  }

  // 3) pay (or finish paying) rewards of finalized challenges
  const pending = await firestore.collection(COL.challenges).where('rewardsPending', '==', true).get();
  for (const doc of pending.docs) report.rewardsPaid += await payChallengeRewards(doc.id);

  // 4) rolling participations whose window has passed without completion become LEFT (can re-join)
  const today = dayKeyOf(now);
  const expired = await firestore.collection(COL.challengeParticipants).where('status', '==', 'JOINED').where('windowEnd', '<', today).get();
  for (const p of expired.docs) {
    const chRef = firestore.collection(COL.challenges).doc(String(p.data().challengeId));
    await firestore.runTransaction(async (tx) => {
      const [pSnap, cSnap] = await tx.getAll(p.ref, chRef);
      if (pSnap.data()?.status !== 'JOINED') return;
      tx.update(p.ref, { status: 'LEFT', endedReason: 'WINDOW_ENDED', leftAt: FieldValue.serverTimestamp() });
      if (cSnap.exists) tx.update(chRef, { participantCount: FieldValue.increment(-1) });
    });
    report.participantsExpired++;
  }
  return report;
}

/** Returns true if THIS call performed the finalization (false if it already happened). */
export async function finalizeChallenge(challengeId: string): Promise<boolean> {
  const firestore = db();
  const chRef = firestore.collection(COL.challenges).doc(challengeId);
  const chSnap = await chRef.get();
  if (!chSnap.exists) return false;
  const ch = chSnap.data() as FirebaseFirestore.DocumentData;
  if (ch.status !== 'ACTIVE') return false;
  const endMs = (ch.endAt as Timestamp | null)?.toMillis();
  const graceMs = (await getSettings()).settlementGraceHours * 3_600_000;
  if (endMs === undefined || nowMs() < endMs + graceMs) return false; // never finalize before endAt + grace

  // Final progress from stored summaries (never from client numbers).
  const partSnap = await firestore
    .collection(COL.challengeParticipants)
    .where('challengeId', '==', challengeId)
    .where('status', 'in', ['JOINED', 'COMPLETED'])
    .get();
  const rows: ParticipantRow[] = [];
  for (const p of partSnap.docs) {
    const d = p.data();
    const days = await loadUserDays(String(d.uid));
    const progress = progressFor(ch, d, days);
    if (progress !== d.progress) await p.ref.update({ progress, progressUpdatedAt: FieldValue.serverTimestamp() });
    rows.push({
      uid: String(d.uid),
      name: String(d.displayName ?? ''),
      hostelId: (d.hostelId as string | null) ?? null,
      progress,
      progressUpdatedAtMs: progress !== d.progress ? nowMs() : ((d.progressUpdatedAt as Timestamp | null)?.toMillis() ?? 0),
    });
  }
  const hostelSnap = await firestore.collection(COL.hostels).get();
  const names = new Map(hostelSnap.docs.map((h) => [h.id, String(h.data().displayName ?? h.id)]));
  const decision = decideResult({
    type: ch.type as ChallengeType,
    target: Number(ch.target),
    aggregation: ch.hostelAggregation === 'TOTAL' ? 'TOTAL' : 'AVERAGE_PER_PARTICIPANT',
    participants: rows,
    hostelNames: names,
    hostelIds: (ch.hostelIds as string[]) ?? [],
  });

  const resRef = firestore.collection(COL.challengeResults).doc(challengeId);
  const performed = await firestore.runTransaction(async (tx) => {
    const [c, r] = await tx.getAll(chRef, resRef);
    if (r.exists || c.data()?.status !== 'ACTIVE') return false; // existence of challengeResults makes finalize idempotent
    tx.create(resRef, {
      challengeId,
      type: ch.type,
      winnerUid: decision.winnerUid,
      winnerHostelId: decision.winnerHostelId,
      ranking: decision.ranking,
      participantCount: rows.length,
      finalizedAt: FieldValue.serverTimestamp(),
      metricLabel: metricLabel(ch.metric as Metric, ch.dailyTarget ?? null, ch.type === 'INTER_HOSTEL' ? (ch.hostelAggregation ?? 'AVERAGE_PER_PARTICIPANT') : undefined),
      ...(ch.type === 'BUDDY' ? { participantUids: ch.participantUids ?? [] } : {}),
    });
    tx.update(chRef, {
      status: 'COMPLETED',
      winnerUid: decision.winnerUid,
      winnerHostelId: decision.winnerHostelId,
      finalizedAt: FieldValue.serverTimestamp(),
      rewardsPending: true,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (!performed) return false;

  // Mark participants that reached the target as COMPLETED (display only; rewards below are winner-based).
  for (const p of partSnap.docs) {
    const row = rows.find((r) => r.uid === p.data().uid);
    if (row && row.progress >= Number(ch.target) && Number(ch.target) > 0 && p.data().status === 'JOINED') {
      await p.ref.update({ status: 'COMPLETED', completedAt: FieldValue.serverTimestamp() });
    }
  }
  await payChallengeRewards(challengeId);
  return true;
}

/**
 * Pays the winner reward(s) exactly once (deterministic ledger id CHALLENGE_{id}_{uid}_REWARD) and clears
 * `rewardsPending`. Safe to run any number of times. Returns the number of NEW reward payments.
 */
export async function payChallengeRewards(challengeId: string): Promise<number> {
  const firestore = db();
  const chRef = firestore.collection(COL.challenges).doc(challengeId);
  const chSnap = await chRef.get();
  const ch = chSnap.data();
  if (!ch || ch.rewardsPending !== true) return 0;
  const settings = await getSettings();
  const points = typeof ch.rewardPoints === 'number' ? ch.rewardPoints : settings.pointsChallengeWin;
  const title = String(ch.title ?? 'Challenge');
  let paid = 0;

  type Recipient = { uid: string; badges: string[] };
  const recipients: Recipient[] = [];
  if (ch.winnerUid) {
    recipients.push({ uid: ch.winnerUid, badges: ch.type === 'CAMPUS' ? ['CHALLENGE_CHAMPION', 'CAMPUS_FITNESS_STAR'] : ['CHALLENGE_CHAMPION'] });
  }
  if (ch.winnerHostelId) {
    const members = await firestore
      .collection(COL.challengeParticipants)
      .where('challengeId', '==', challengeId)
      .where('hostelId', '==', ch.winnerHostelId)
      .get();
    for (const m of members.docs) {
      const d = m.data();
      if ((d.status === 'JOINED' || d.status === 'COMPLETED') && Number(d.progress) > 0) recipients.push({ uid: String(d.uid), badges: ['HOSTEL_CHAMPION'] });
    }
  }

  for (const r of recipients) {
    const res = await grantRewards({
      uid: r.uid,
      reward: { refType: 'CHALLENGE', refId: challengeId, points, note: `Challenge reward: ${title}` },
      badges: r.badges.map((b) => ({ badgeId: b, refId: challengeId })),
    });
    if (res.rewardApplied) paid++;
    await firestore.collection(COL.challengeParticipants).doc(participantDocId(challengeId, r.uid)).update({ rewardPaid: true }).catch(() => undefined);
    await notify({
      uid: r.uid,
      type: ch.winnerHostelId ? 'HOSTEL_RESULT' : 'CHALLENGE_DONE',
      title: ch.winnerHostelId ? 'Your hostel won!' : 'You won the challenge!',
      body: `"${title}" is over${points > 0 ? ` - you earned ${points} points` : ''}.`,
      data: { challengeId },
      dedupeKey: `chwin_${challengeId}`,
    }).catch(() => undefined);
  }

  // Everyone else just hears the result once.
  const all = await firestore.collection(COL.challengeParticipants).where('challengeId', '==', challengeId).where('status', 'in', ['JOINED', 'COMPLETED']).get();
  const winners = new Set(recipients.map((r) => r.uid));
  for (const p of all.docs) {
    const uid = String(p.data().uid);
    if (winners.has(uid)) continue;
    await notify({
      uid,
      type: ch.type === 'INTER_HOSTEL' ? 'HOSTEL_RESULT' : 'CHALLENGE_DONE',
      title: 'Challenge finished',
      body: `"${title}" has ended. See the final ranking.`,
      data: { challengeId },
      dedupeKey: `chend_${challengeId}`,
    }).catch(() => undefined);
  }

  await chRef.update({ rewardsPending: false, rewardsPaidAt: FieldValue.serverTimestamp() });
  return paid;
}
