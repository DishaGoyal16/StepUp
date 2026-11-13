import { COL } from '../config';
import { nowMs } from '../lib/clock';
import { db, FieldValue, Timestamp, tsFromMs } from '../lib/firebase';
import { applyPoints, loadPoints } from '../lib/points';
import { getSettings } from '../lib/settings';
import { notify } from '../notifications/notify';
import { loadUserDays } from '../steps/summaries';
import { betWindowSteps } from './bets';
import { betReleaseOp, resolveBet, settlementOps } from './resolve';

export interface SettleReport {
  expired: number;
  settled: number;
}

/** Scheduled every 15 minutes. Idempotent: status checks + deterministic ledger ids prevent double settlement. */
export async function runSettleStepBets(): Promise<SettleReport> {
  const firestore = db();
  const now = nowMs();
  const settings = await getSettings();
  const report: SettleReport = { expired: 0, settled: 0 };

  const stale = await firestore.collection(COL.stepBets).where('status', '==', 'PENDING').where('expiresAt', '<=', tsFromMs(now)).get();
  for (const doc of stale.docs) if (await expireBet(doc.id)) report.expired++;

  const cutoff = tsFromMs(now - settings.settlementGraceHours * 3_600_000);
  const ended = await firestore.collection(COL.stepBets).where('status', '==', 'ACTIVE').where('endAt', '<=', cutoff).get();
  for (const doc of ended.docs) if (await settleBet(doc.id)) report.settled++;
  return report;
}

/** PENDING bet past expiresAt: EXPIRED and the challenger's reserved stake is released. */
export async function expireBet(betId: string): Promise<boolean> {
  const firestore = db();
  const ref = firestore.collection(COL.stepBets).doc(betId);
  const now = nowMs();
  const done = await firestore.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const b = snap.data();
    if (!b || b.status !== 'PENDING' || (b.expiresAt as Timestamp).toMillis() > now) return null;
    const ops = [betReleaseOp(b.challengerUid, betId, b.stakePoints, 'Bet expired - stake released')];
    const state = await loadPoints(tx, ops);
    applyPoints(tx, state, ops);
    tx.update(ref, { status: 'EXPIRED', settledAt: FieldValue.serverTimestamp() });
    return b.challengerUid as string;
  });
  if (!done) return false;
  await notify({
    uid: done,
    type: 'BET_RESULT',
    title: 'Bet expired',
    body: 'Your step bet was not answered in time. Your stake was returned.',
    data: { betId },
    dedupeKey: `betexp_${betId}`,
  }).catch(() => undefined);
  return true;
}

/** ACTIVE bet whose window ended: final verified steps from summaries -> resolution -> payout, exactly once. */
export async function settleBet(betId: string): Promise<boolean> {
  const firestore = db();
  const ref = firestore.collection(COL.stepBets).doc(betId);
  const first = await ref.get();
  const b0 = first.data();
  if (!b0 || b0.status !== 'ACTIVE' || !b0.startAt || !b0.endAt) return false;
  const startMs = (b0.startAt as Timestamp).toMillis();
  const endMs = (b0.endAt as Timestamp).toMillis();
  const graceMs = (await getSettings()).settlementGraceHours * 3_600_000;
  if (nowMs() < endMs + graceMs) return false; // never settle before endAt + grace, whoever calls us
  const [cDays, oDays] = await Promise.all([loadUserDays(b0.challengerUid), loadUserDays(b0.opponentUid)]);
  const challengerSteps = betWindowSteps(cDays, startMs, endMs);
  const opponentSteps = betWindowSteps(oDays, startMs, endMs);

  const result = await firestore.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const b = snap.data();
    if (!b || b.status !== 'ACTIVE') return null; // already settled by a concurrent/previous run
    const outcome = resolveBet({ targetSteps: b.targetSteps, challengerSteps, opponentSteps });
    const ops = settlementOps(b as { challengerUid: string; opponentUid: string; stakePoints: number }, betId, outcome);
    const state = await loadPoints(tx, ops);
    applyPoints(tx, state, ops);
    const winnerUid = outcome.winner === null ? null : outcome.winner === 'CHALLENGER' ? b.challengerUid : b.opponentUid;
    tx.update(ref, {
      status: 'COMPLETED',
      challengerSteps,
      opponentSteps,
      winnerUid,
      resolution: outcome.resolution,
      settledAt: FieldValue.serverTimestamp(),
    });
    return { winnerUid, resolution: outcome.resolution, c: b.challengerUid as string, o: b.opponentUid as string, stake: b.stakePoints as number };
  });
  if (!result) return false;
  for (const uid of [result.c, result.o]) {
    const won = result.winnerUid === uid;
    await notify({
      uid,
      type: 'BET_RESULT',
      title: result.winnerUid === null ? 'Bet refunded' : won ? 'You won the bet!' : 'Bet lost',
      body:
        result.winnerUid === null
          ? `Nobody won (${result.resolution.toLowerCase().replace(/_/g, ' ')}). Your ${result.stake} points were returned.`
          : won
            ? `You won ${result.stake * 2} points.`
            : `You lost ${result.stake} points.`,
      data: { betId },
      dedupeKey: `betres_${betId}`,
    }).catch(() => undefined);
  }
  return true;
}

/** Keep ACTIVE bets' live step totals in sync (verified steps only). */
export async function updateBetProgressForUser(uid: string, days: ReadonlyMap<string, number>): Promise<void> {
  const firestore = db();
  const [asChallenger, asOpponent] = await Promise.all([
    firestore.collection(COL.stepBets).where('challengerUid', '==', uid).where('status', '==', 'ACTIVE').get(),
    firestore.collection(COL.stepBets).where('opponentUid', '==', uid).where('status', '==', 'ACTIVE').get(),
  ]);
  const apply = async (doc: FirebaseFirestore.QueryDocumentSnapshot, field: 'challengerSteps' | 'opponentSteps') => {
    const b = doc.data();
    if (!b.startAt || !b.endAt) return;
    const steps = betWindowSteps(days, (b.startAt as Timestamp).toMillis(), (b.endAt as Timestamp).toMillis());
    if (steps !== b[field]) await doc.ref.update({ [field]: steps });
  };
  for (const d of asChallenger.docs) await apply(d, 'challengerSteps');
  for (const d of asOpponent.docs) await apply(d, 'opponentSteps');
}
