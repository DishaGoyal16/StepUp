import { COL } from '../config';
import { fail } from './errors';
import { db, FieldValue } from './firebase';

/**
 * Virtual-points engine. ALL balance mutations go through here, inside a Firestore transaction that also creates a
 * ledger document with a deterministic id `{refType}_{refId}_{uid}_{type}`. An op whose ledger doc already exists is
 * skipped (idempotent: no double pay / double spend), and the ledger doc is written with `tx.create` as a second guard.
 *
 * `delta` in the ledger is the change of `pointsBalance` (available). `reservedDelta` is the change of
 * `pointsReserved`. RESERVE: delta=-stake, reservedDelta=+stake. RELEASE: the reverse. BET_WIN: delta=+2*stake,
 * reservedDelta=-stake. BET_LOSS: delta=0, reservedDelta=-stake. VIRTUAL POINTS ONLY - no currency anywhere.
 */

export type LedgerType = 'RESERVE' | 'RELEASE' | 'BET_WIN' | 'BET_LOSS' | 'REWARD' | 'ADJUSTMENT';
export type LedgerRefType = 'BET' | 'CHALLENGE' | 'DAILY_GOAL' | 'STREAK' | 'BADGE' | 'ADMIN';

export interface LedgerOp {
  uid: string;
  type: LedgerType;
  refType: LedgerRefType;
  refId: string;
  balanceDelta: number;
  reservedDelta: number;
  note?: string;
}

export function ledgerEntryId(refType: string, refId: string, uid: string, type: string): string {
  return `${refType}_${refId}_${uid}_${type}`;
}

export interface PointsState {
  users: Map<string, { ref: FirebaseFirestore.DocumentReference; balance: number; reserved: number }>;
  existing: Set<string>;
}

export interface PointsResult {
  entryId: string;
  applied: boolean;
  balanceAfter: number;
  reservedAfter: number;
}

/** READ phase (must be called before any write in the transaction). */
export async function loadPoints(tx: FirebaseFirestore.Transaction, ops: LedgerOp[]): Promise<PointsState> {
  const firestore = db();
  const uids = [...new Set(ops.map((o) => o.uid))];
  const userRefs = uids.map((u) => firestore.collection(COL.users).doc(u));
  const ledgerRefs = ops.map((o) => firestore.collection(COL.ledger).doc(ledgerEntryId(o.refType, o.refId, o.uid, o.type)));
  const snaps = await tx.getAll(...userRefs, ...ledgerRefs);
  const users: PointsState['users'] = new Map();
  uids.forEach((uid, i) => {
    const s = snaps[i];
    if (!s.exists) fail('not-found', 'USER_NOT_FOUND');
    const d = s.data() as FirebaseFirestore.DocumentData;
    users.set(uid, { ref: userRefs[i], balance: Number(d.pointsBalance ?? 0), reserved: Number(d.pointsReserved ?? 0) });
  });
  const existing = new Set<string>();
  ledgerRefs.forEach((r, i) => {
    if (snaps[uids.length + i].exists) existing.add(r.id);
  });
  return { users, existing };
}

/** WRITE phase. Ops are applied in order against running balances. */
export function applyPoints(tx: FirebaseFirestore.Transaction, state: PointsState, ops: LedgerOp[]): PointsResult[] {
  const results: PointsResult[] = [];
  for (const op of ops) {
    const entryId = ledgerEntryId(op.refType, op.refId, op.uid, op.type);
    const u = state.users.get(op.uid);
    if (!u) fail('internal', 'POINTS_STATE_MISSING');
    if (state.existing.has(entryId)) {
      results.push({ entryId, applied: false, balanceAfter: u.balance, reservedAfter: u.reserved });
      continue;
    }
    const balance = u.balance + op.balanceDelta;
    const reserved = u.reserved + op.reservedDelta;
    if (!Number.isInteger(op.balanceDelta) || !Number.isInteger(op.reservedDelta)) fail('internal', 'NON_INTEGER_POINTS');
    if (balance < 0 || reserved < 0) fail('failed-precondition', 'INSUFFICIENT_POINTS', 'not enough points');
    u.balance = balance;
    u.reserved = reserved;
    state.existing.add(entryId);
    tx.update(u.ref, { pointsBalance: balance, pointsReserved: reserved, updatedAt: FieldValue.serverTimestamp() });
    tx.create(db().collection(COL.ledger).doc(entryId), {
      uid: op.uid,
      delta: op.balanceDelta,
      reservedDelta: op.reservedDelta,
      type: op.type,
      refType: op.refType,
      refId: op.refId,
      balanceAfter: balance,
      reservedAfter: reserved,
      note: op.note ?? '',
      createdAt: FieldValue.serverTimestamp(),
    });
    results.push({ entryId, applied: true, balanceAfter: balance, reservedAfter: reserved });
  }
  return results;
}

/** Convenience: apply ops in their own transaction. Returns per-op results (applied=false when it already existed). */
export async function awardPoints(ops: LedgerOp[]): Promise<PointsResult[]> {
  return db().runTransaction(async (tx) => {
    const state = await loadPoints(tx, ops);
    return applyPoints(tx, state, ops);
  });
}

export function rewardOp(
  uid: string,
  refType: LedgerRefType,
  refId: string,
  points: number,
  note: string,
): LedgerOp {
  return { uid, type: 'REWARD', refType, refId, balanceDelta: points, reservedDelta: 0, note };
}
