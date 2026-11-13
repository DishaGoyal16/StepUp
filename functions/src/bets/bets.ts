import { BET_LIMITS, COL, DAY_MS } from '../config';
import { areActiveBuddies } from '../buddies/buddies';
import { Req, requireEligibleUser } from '../lib/auth';
import { nowMs } from '../lib/clock';
import { fail } from '../lib/errors';
import { db, FieldValue, Timestamp, tsFromMs } from '../lib/firebase';
import { applyPoints, loadPoints, LedgerOp } from '../lib/points';
import { getSettings } from '../lib/settings';
import { dayKeyOf, nextIstMidnightMs } from '../lib/time';
import { asRecord, bool, id, int, optStr } from '../lib/validate';
import { notify } from '../notifications/notify';
import { betReleaseOp, betReserveOp } from './resolve';

export const REQUEST_ID_PATTERN = /^[A-Za-z0-9-]{8,40}$/;

export async function handleCreateStepBet(req: Req): Promise<{ betId: string; duplicate: boolean }> {
  const caller = await requireEligibleUser(req);
  const d = asRecord(req.data);
  const settings = await getSettings();
  const opponentUid = id(d, 'opponentUid');
  const targetSteps = int(d, 'targetSteps', BET_LIMITS.minTarget, BET_LIMITS.maxTarget);
  const durationDays = int(d, 'durationDays', BET_LIMITS.minDays, BET_LIMITS.maxDays);
  const stakePoints = int(d, 'stakePoints', settings.betMinStake, settings.betMaxStake);
  const requestId = optStr(d, 'requestId', { min: 8, max: 40, pattern: REQUEST_ID_PATTERN });
  if (opponentUid === caller.uid) fail('invalid-argument', 'CANNOT_BET_SELF');
  if (!(await areActiveBuddies(caller.uid, opponentUid))) fail('failed-precondition', 'NOT_BUDDIES', 'opponent must be an active buddy');

  const firestore = db();
  const betRef = requestId ? firestore.collection(COL.stepBets).doc(`${caller.uid}_${requestId}`) : firestore.collection(COL.stepBets).doc();
  const now = nowMs();
  const result = await firestore.runTransaction(async (tx) => {
    const [betSnap, oppSnap] = await tx.getAll(betRef, firestore.collection(COL.users).doc(opponentUid));
    if (betSnap.exists) return { duplicate: true, oppName: '' };
    if (!oppSnap.exists || oppSnap.data()?.status !== 'ACTIVE') fail('failed-precondition', 'OPPONENT_NOT_ACTIVE');
    const ops: LedgerOp[] = [betReserveOp(caller.uid, betRef.id, stakePoints)];
    const state = await loadPoints(tx, ops);
    // Fails with INSUFFICIENT_POINTS before anything is written.
    applyPoints(tx, state, ops);
    tx.create(betRef, {
      challengerUid: caller.uid,
      opponentUid,
      challengerName: caller.user.displayName,
      opponentName: oppSnap.data()?.displayName ?? '',
      targetSteps,
      durationDays,
      stakePoints,
      status: 'PENDING',
      startAt: null,
      endAt: null,
      challengerSteps: 0,
      opponentSteps: 0,
      winnerUid: null,
      resolution: null,
      createdAt: FieldValue.serverTimestamp(),
      respondedAt: null,
      settledAt: null,
      expiresAt: tsFromMs(now + settings.betExpiryHours * 3_600_000),
    });
    return { duplicate: false, oppName: String(oppSnap.data()?.displayName ?? '') };
  });
  if (!result.duplicate) {
    await notify({
      uid: opponentUid,
      type: 'BET_INVITE',
      title: 'Step bet invite',
      body: `${caller.user.displayName} bets ${stakePoints} points on ${targetSteps} steps in ${durationDays} day(s).`,
      data: { betId: betRef.id },
      dedupeKey: `betinv_${betRef.id}`,
    });
  }
  return { betId: betRef.id, duplicate: result.duplicate };
}

export async function handleRespondStepBet(req: Req): Promise<{ ok: true }> {
  const caller = await requireEligibleUser(req);
  const d = asRecord(req.data);
  const betId = id(d, 'betId');
  const accept = bool(d, 'accept');
  const firestore = db();
  const betRef = firestore.collection(COL.stepBets).doc(betId);
  const now = nowMs();

  const outcome = await firestore.runTransaction(async (tx) => {
    const snap = await tx.get(betRef);
    if (!snap.exists) fail('not-found', 'BET_NOT_FOUND');
    const b = snap.data() as FirebaseFirestore.DocumentData;
    if (b.opponentUid !== caller.uid) fail('permission-denied', 'NOT_BET_OPPONENT');
    if (b.status !== 'PENDING') {
      if (accept && b.status === 'ACTIVE') return 'NOOP';
      if (!accept && b.status === 'DECLINED') return 'NOOP';
      fail('failed-precondition', 'BET_NOT_PENDING');
    }
    const expired = (b.expiresAt as Timestamp).toMillis() <= now;
    if (expired || !accept) {
      const ops = [betReleaseOp(b.challengerUid, betId, b.stakePoints, expired ? 'Bet expired - stake released' : 'Bet declined - stake released')];
      const state = await loadPoints(tx, ops);
      applyPoints(tx, state, ops);
      tx.update(betRef, { status: expired ? 'EXPIRED' : 'DECLINED', respondedAt: FieldValue.serverTimestamp(), settledAt: FieldValue.serverTimestamp() });
      return expired ? 'EXPIRED' : 'DECLINED';
    }
    const ops = [betReserveOp(caller.uid, betId, b.stakePoints)];
    const state = await loadPoints(tx, ops);
    applyPoints(tx, state, ops); // INSUFFICIENT_POINTS aborts the whole accept
    const startMs = nextIstMidnightMs(now);
    tx.update(betRef, {
      status: 'ACTIVE',
      respondedAt: FieldValue.serverTimestamp(),
      startAt: tsFromMs(startMs),
      endAt: tsFromMs(startMs + b.durationDays * DAY_MS),
    });
    return 'ACCEPTED';
  });
  if (outcome === 'EXPIRED') fail('failed-precondition', 'BET_EXPIRED', 'this bet has expired');
  if (outcome === 'ACCEPTED' || outcome === 'DECLINED') {
    const snap = await betRef.get();
    await notify({
      uid: String(snap.data()?.challengerUid),
      type: 'BET_INVITE',
      title: outcome === 'ACCEPTED' ? 'Bet accepted' : 'Bet declined',
      body: `${caller.user.displayName} ${outcome === 'ACCEPTED' ? 'accepted' : 'declined'} your step bet.`,
      data: { betId },
      dedupeKey: `betresp_${betId}`,
    });
  }
  return { ok: true };
}

export async function handleCancelStepBet(req: Req): Promise<{ ok: true }> {
  const caller = await requireEligibleUser(req);
  const d = asRecord(req.data);
  const betId = id(d, 'betId');
  const betRef = db().collection(COL.stepBets).doc(betId);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(betRef);
    if (!snap.exists) fail('not-found', 'BET_NOT_FOUND');
    const b = snap.data() as FirebaseFirestore.DocumentData;
    if (b.challengerUid !== caller.uid) fail('permission-denied', 'NOT_BET_CHALLENGER');
    if (b.status === 'CANCELLED') return;
    if (b.status !== 'PENDING') fail('failed-precondition', 'BET_NOT_PENDING', 'only pending bets can be cancelled');
    const ops = [betReleaseOp(caller.uid, betId, b.stakePoints, 'Bet cancelled - stake released')];
    const state = await loadPoints(tx, ops);
    applyPoints(tx, state, ops);
    tx.update(betRef, { status: 'CANCELLED', respondedAt: FieldValue.serverTimestamp(), settledAt: FieldValue.serverTimestamp() });
  });
  return { ok: true };
}

/** Sum of verified steps of a user inside a bet window [startAt, endAt). Pure over the day map. */
export function betWindowSteps(days: ReadonlyMap<string, number>, startAtMs: number, endAtMs: number): number {
  const a = dayKeyOf(startAtMs);
  const b = dayKeyOf(endAtMs - 1);
  let s = 0;
  for (const [k, v] of days) if (k >= a && k <= b) s += v;
  return s;
}
