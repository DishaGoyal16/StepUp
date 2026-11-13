import { LedgerOp } from '../lib/points';

/** Pure step-bet logic. VIRTUAL POINTS ONLY - there is no currency anywhere in this system. */

export type BetResolution = 'HIGHER_STEPS' | 'ONLY_ONE_REACHED_TARGET' | 'REFUND_NONE_REACHED' | 'REFUND_TIE';

export interface BetOutcome {
  winner: 'CHALLENGER' | 'OPPONENT' | null;
  resolution: BetResolution;
}

/**
 * At endAt + grace:
 *  - both reached the target => higher verified steps wins (equal => REFUND_TIE)
 *  - exactly one reached     => that one wins
 *  - none reached            => REFUND_NONE_REACHED
 */
export function resolveBet(b: { targetSteps: number; challengerSteps: number; opponentSteps: number }): BetOutcome {
  const c = b.challengerSteps >= b.targetSteps;
  const o = b.opponentSteps >= b.targetSteps;
  if (c && o) {
    if (b.challengerSteps === b.opponentSteps) return { winner: null, resolution: 'REFUND_TIE' };
    return { winner: b.challengerSteps > b.opponentSteps ? 'CHALLENGER' : 'OPPONENT', resolution: 'HIGHER_STEPS' };
  }
  if (c) return { winner: 'CHALLENGER', resolution: 'ONLY_ONE_REACHED_TARGET' };
  if (o) return { winner: 'OPPONENT', resolution: 'ONLY_ONE_REACHED_TARGET' };
  return { winner: null, resolution: 'REFUND_NONE_REACHED' };
}

export function betReserveOp(uid: string, betId: string, stake: number): LedgerOp {
  return { uid, type: 'RESERVE', refType: 'BET', refId: betId, balanceDelta: -stake, reservedDelta: stake, note: 'Stake reserved for step bet' };
}

export function betReleaseOp(uid: string, betId: string, stake: number, note: string): LedgerOp {
  return { uid, type: 'RELEASE', refType: 'BET', refId: betId, balanceDelta: stake, reservedDelta: -stake, note };
}

/** Ledger operations that settle an ACTIVE bet. Winner receives BOTH stakes; refunds release both reservations. */
export function settlementOps(
  bet: { challengerUid: string; opponentUid: string; stakePoints: number },
  betId: string,
  outcome: BetOutcome,
): LedgerOp[] {
  const s = bet.stakePoints;
  if (outcome.winner === null) {
    return [
      betReleaseOp(bet.challengerUid, betId, s, `Bet refunded (${outcome.resolution})`),
      betReleaseOp(bet.opponentUid, betId, s, `Bet refunded (${outcome.resolution})`),
    ];
  }
  const winnerUid = outcome.winner === 'CHALLENGER' ? bet.challengerUid : bet.opponentUid;
  const loserUid = outcome.winner === 'CHALLENGER' ? bet.opponentUid : bet.challengerUid;
  return [
    { uid: winnerUid, type: 'BET_WIN', refType: 'BET', refId: betId, balanceDelta: 2 * s, reservedDelta: -s, note: 'Won step bet (both stakes)' },
    { uid: loserUid, type: 'BET_LOSS', refType: 'BET', refId: betId, balanceDelta: 0, reservedDelta: -s, note: 'Lost step bet stake' },
  ];
}
