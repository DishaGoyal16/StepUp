import { betWindowSteps } from '../../src/bets/bets';
import { resolveBet, settlementOps, BetResolution } from '../../src/bets/resolve';
import { ledgerEntryId } from '../../src/lib/points';

describe('step bet resolution matrix (virtual points only)', () => {
  const T = 10_000;
  const cases: Array<[string, number, number, 'CHALLENGER' | 'OPPONENT' | null, BetResolution]> = [
    ['both reached, challenger higher', 12_000, 10_500, 'CHALLENGER', 'HIGHER_STEPS'],
    ['both reached, opponent higher', 10_100, 15_000, 'OPPONENT', 'HIGHER_STEPS'],
    ['both reached exactly equal => refund tie', 11_000, 11_000, null, 'REFUND_TIE'],
    ['both exactly at target and equal => tie', T, T, null, 'REFUND_TIE'],
    ['only challenger reached', 10_000, 9_999, 'CHALLENGER', 'ONLY_ONE_REACHED_TARGET'],
    ['only opponent reached (even with fewer steps than...)', 9_999, 10_000, 'OPPONENT', 'ONLY_ONE_REACHED_TARGET'],
    ['only one reached but other has more steps below target', 10_000, 9_990, 'CHALLENGER', 'ONLY_ONE_REACHED_TARGET'],
    ['none reached => refund', 9_000, 8_000, null, 'REFUND_NONE_REACHED'],
    ['none reached and equal => refund (none reached takes precedence)', 100, 100, null, 'REFUND_NONE_REACHED'],
    ['zero steps both', 0, 0, null, 'REFUND_NONE_REACHED'],
  ];
  test.each(cases)('%s', (_n, c, o, winner, resolution) => {
    expect(resolveBet({ targetSteps: T, challengerSteps: c, opponentSteps: o })).toEqual({ winner, resolution });
  });
});

describe('settlement ledger operations', () => {
  const bet = { challengerUid: 'alice', opponentUid: 'bob', stakePoints: 100 };

  test('winner receives BOTH stakes; loser loses only the reserved stake; total points are conserved', () => {
    const ops = settlementOps(bet, 'b1', { winner: 'CHALLENGER', resolution: 'HIGHER_STEPS' });
    const win = ops.find((o) => o.type === 'BET_WIN')!;
    const loss = ops.find((o) => o.type === 'BET_LOSS')!;
    expect(win).toMatchObject({ uid: 'alice', balanceDelta: 200, reservedDelta: -100 });
    expect(loss).toMatchObject({ uid: 'bob', balanceDelta: 0, reservedDelta: -100 });
    // Before: each had 100 reserved (200 total reserved). After: winner +200 balance, reserved -200 overall => conserved.
    const net = ops.reduce((s, o) => s + o.balanceDelta + o.reservedDelta, 0);
    expect(net).toBe(0);
    expect(win.balanceDelta + win.reservedDelta).toBe(100); // winner nets +stake
    expect(loss.balanceDelta + loss.reservedDelta).toBe(-100); // loser nets -stake
  });

  test('opponent win mirrors correctly', () => {
    const ops = settlementOps(bet, 'b1', { winner: 'OPPONENT', resolution: 'ONLY_ONE_REACHED_TARGET' });
    expect(ops.find((o) => o.type === 'BET_WIN')!.uid).toBe('bob');
    expect(ops.find((o) => o.type === 'BET_LOSS')!.uid).toBe('alice');
  });

  test.each<BetResolution>(['REFUND_TIE', 'REFUND_NONE_REACHED'])('%s releases both reservations with no gain or loss', (resolution) => {
    const ops = settlementOps(bet, 'b1', { winner: null, resolution });
    expect(ops).toHaveLength(2);
    for (const o of ops) {
      expect(o.type).toBe('RELEASE');
      expect(o.balanceDelta).toBe(100);
      expect(o.reservedDelta).toBe(-100);
    }
  });

  test('ledger entry ids are deterministic and unique per (ref, user, type) => a repeated settlement cannot pay twice', () => {
    const a = settlementOps(bet, 'b1', { winner: 'CHALLENGER', resolution: 'HIGHER_STEPS' }).map((o) => ledgerEntryId(o.refType, o.refId, o.uid, o.type));
    const b = settlementOps(bet, 'b1', { winner: 'CHALLENGER', resolution: 'HIGHER_STEPS' }).map((o) => ledgerEntryId(o.refType, o.refId, o.uid, o.type));
    expect(a).toEqual(b);
    expect(new Set(a).size).toBe(a.length);
    expect(a).toEqual(['BET_b1_alice_BET_WIN', 'BET_b1_bob_BET_LOSS']);
  });
});

describe('betWindowSteps', () => {
  const start = Date.UTC(2026, 0, 4, 18, 30); // IST 2026-01-05 00:00
  const end = start + 2 * 86_400_000; // exclusive => IST days 05 and 06
  test('sums only days inside [start, end)', () => {
    const days = new Map([
      ['20260104', 500],
      ['20260105', 4000],
      ['20260106', 6000],
      ['20260107', 9999],
    ]);
    expect(betWindowSteps(days, start, end)).toBe(10_000);
  });
});
