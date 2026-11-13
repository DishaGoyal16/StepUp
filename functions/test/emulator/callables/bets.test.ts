import { handleCancelStepBet, handleCreateStepBet, handleRespondStepBet } from '../../../src/bets/bets';
import { expireBet, runSettleStepBets, settleBet } from '../../../src/bets/settle';
import { setClock } from '../../../src/lib/clock';
import { db } from '../../../src/lib/firebase';
import { authReq, DAY, expectError, freeze, getDoc, giveVerifiedSteps, givePoints, ledgerFor, makeBuddies, makeUser, resetAll, T0, userDoc } from '../helpers/env';

const D3 = Date.UTC(2026, 2, 2, 18, 30); // IST 2026-03-03 00:00 (first midnight after T0)
const H = 3_600_000;

beforeEach(async () => {
  await resetAll();
  freeze();
  await makeUser('alice');
  await makeUser('bob');
  await makeUser('carol');
  await makeBuddies('alice', 'bob');
  await givePoints('alice', 500);
  await givePoints('bob', 500);
});
afterAll(() => setClock(null));

const bal = async (uid: string) => {
  const u = await userDoc(uid);
  return { balance: u.pointsBalance as number, reserved: u.pointsReserved as number };
};
const create = (over: Record<string, unknown> = {}) => handleCreateStepBet(authReq('alice', { opponentUid: 'bob', targetSteps: 10_000, durationDays: 2, stakePoints: 100, ...over }));
const respond = (uid: string, betId: string, accept: boolean) => handleRespondStepBet(authReq(uid, { betId, accept }));
const betLedger = async (uid: string, betId: string) => (await ledgerFor(uid)).filter((l) => l.refType === 'BET' && l.refId === betId);
const notifs = async (uid: string, type: string) => (await db().collection('notifications').where('uid', '==', uid).where('type', '==', type).get()).docs.map((d) => d.data());

/** Create + accept a bet, then walk the given verified steps on the two bet days. */
async function activeBet(steps: { alice: [number, number]; bob: [number, number] }, over: Record<string, unknown> = {}): Promise<string> {
  const { betId } = await create(over);
  await respond('bob', betId, true);
  await giveVerifiedSteps('alice', '20260303', steps.alice[0]);
  await giveVerifiedSteps('alice', '20260304', steps.alice[1]);
  await giveVerifiedSteps('bob', '20260303', steps.bob[0]);
  await giveVerifiedSteps('bob', '20260304', steps.bob[1]);
  return betId;
}

describe('createStepBet', () => {
  test('reserves the challenger stake with a deterministic ledger entry and invites the buddy', async () => {
    const before = await bal('alice');
    const { betId, duplicate } = await create();
    expect(duplicate).toBe(false);
    expect(await bal('alice')).toEqual({ balance: before.balance - 100, reserved: 100 });
    const bet = await getDoc(`stepBets/${betId}`);
    expect(bet).toMatchObject({ challengerUid: 'alice', opponentUid: 'bob', targetSteps: 10_000, durationDays: 2, stakePoints: 100, status: 'PENDING', startAt: null, winnerUid: null, resolution: null, challengerSteps: 0, opponentSteps: 0 });
    expect((bet?.expiresAt as { toMillis(): number }).toMillis()).toBe(T0 + 48 * H);
    const l = await getDoc(`virtualPointsLedger/BET_${betId}_alice_RESERVE`);
    expect(l).toMatchObject({ uid: 'alice', type: 'RESERVE', refType: 'BET', refId: betId, delta: -100, reservedDelta: 100, balanceAfter: 400, reservedAfter: 100 });
    expect(await notifs('bob', 'BET_INVITE')).toHaveLength(1);
    expect(await bal('bob')).toEqual({ balance: 500, reserved: 0 }); // opponent not charged yet
  });

  test('insufficient points: rejected, nothing created, balance unchanged', async () => {
    await expectError(create({ stakePoints: 600 }), 'failed-precondition', 'INSUFFICIENT_POINTS');
    expect((await db().collection('stepBets').get()).size).toBe(0);
    expect(await bal('alice')).toEqual({ balance: 500, reserved: 0 });
    expect((await ledgerFor('alice')).filter((l) => l.refType === 'BET')).toHaveLength(0);
  });

  test('cannot reserve the same points twice: the second bet fails once available points are used up', async () => {
    await create({ stakePoints: 400 });
    await expectError(create({ stakePoints: 200 }), 'failed-precondition', 'INSUFFICIENT_POINTS');
    expect(await bal('alice')).toEqual({ balance: 100, reserved: 400 });
  });

  test.each([
    ['stake below minimum', { stakePoints: 5 }, 'INVALID_STAKE_POINTS'],
    ['stake above maximum', { stakePoints: 1001 }, 'INVALID_STAKE_POINTS'],
    ['non-integer stake', { stakePoints: 10.5 }, 'INVALID_STAKE_POINTS'],
    ['target too small', { targetSteps: 10 }, 'INVALID_TARGET_STEPS'],
    ['duration too long', { durationDays: 31 }, 'INVALID_DURATION_DAYS'],
    ['duration zero', { durationDays: 0 }, 'INVALID_DURATION_DAYS'],
    ['self bet', { opponentUid: 'alice' }, 'CANNOT_BET_SELF'],
  ])('validation: %s', async (_n, over, reason) => {
    await expectError(create(over), 'invalid-argument', reason);
  });

  test('opponent must be an active buddy', async () => {
    await expectError(create({ opponentUid: 'carol' }), 'failed-precondition', 'NOT_BUDDIES');
  });

  test('requestId makes retries idempotent: same bet, a single reservation', async () => {
    const a = await create({ requestId: 'req-12345678' });
    const b = await create({ requestId: 'req-12345678' });
    expect(b).toEqual({ betId: a.betId, duplicate: true });
    expect(await bal('alice')).toEqual({ balance: 400, reserved: 100 });
    expect((await db().collection('stepBets').get()).size).toBe(1);
    expect(await notifs('bob', 'BET_INVITE')).toHaveLength(1);
  });

  test('wrong domain / unverified callers are rejected', async () => {
    await expectError(handleCreateStepBet(authReq('alice', { opponentUid: 'bob', targetSteps: 10_000, durationDays: 2, stakePoints: 100 }, { email: 'a@gmail.com' })), 'permission-denied', 'INVALID_EMAIL_DOMAIN');
  });
});

describe('respond / cancel / expire', () => {
  test('accept reserves the opponent stake, activates, starts at the next IST midnight; repeat is a no-op', async () => {
    const { betId } = await create();
    await respond('bob', betId, true);
    await respond('bob', betId, true);
    expect(await bal('bob')).toEqual({ balance: 400, reserved: 100 });
    const bet = await getDoc(`stepBets/${betId}`);
    expect(bet?.status).toBe('ACTIVE');
    expect((bet?.startAt as { toMillis(): number }).toMillis()).toBe(D3);
    expect((bet?.endAt as { toMillis(): number }).toMillis()).toBe(D3 + 2 * DAY);
    expect(await betLedger('bob', betId)).toHaveLength(1);
  });

  test('only the opponent can respond; unknown bet; non-pending', async () => {
    const { betId } = await create();
    await expectError(respond('alice', betId, true), 'permission-denied', 'NOT_BET_OPPONENT');
    await expectError(respond('carol', betId, true), 'permission-denied', 'NOT_BET_OPPONENT');
    await expectError(respond('bob', 'nope', true), 'not-found', 'BET_NOT_FOUND');
    await respond('bob', betId, false);
    await expectError(respond('bob', betId, true), 'failed-precondition', 'BET_NOT_PENDING');
  });

  test('accept with insufficient opponent points fails atomically: bet stays PENDING, nobody is double charged', async () => {
    await db().collection('users').doc('bob').update({ pointsBalance: 50 });
    const { betId } = await create();
    await expectError(respond('bob', betId, true), 'failed-precondition', 'INSUFFICIENT_POINTS');
    expect((await getDoc(`stepBets/${betId}`))?.status).toBe('PENDING');
    expect(await bal('bob')).toEqual({ balance: 50, reserved: 0 });
    expect(await bal('alice')).toEqual({ balance: 400, reserved: 100 });
    expect(await betLedger('bob', betId)).toHaveLength(0);
  });

  test('decline releases the challenger stake', async () => {
    const { betId } = await create();
    await respond('bob', betId, false);
    await respond('bob', betId, false);
    expect((await getDoc(`stepBets/${betId}`))?.status).toBe('DECLINED');
    expect(await bal('alice')).toEqual({ balance: 500, reserved: 0 });
    expect(await betLedger('alice', betId)).toHaveLength(2); // RESERVE + RELEASE, once each
  });

  test('cancel by the challenger releases the stake; only while PENDING; only by the challenger', async () => {
    const { betId } = await create();
    await expectError(handleCancelStepBet(authReq('bob', { betId })), 'permission-denied', 'NOT_BET_CHALLENGER');
    await handleCancelStepBet(authReq('alice', { betId }));
    await handleCancelStepBet(authReq('alice', { betId })); // idempotent
    expect((await getDoc(`stepBets/${betId}`))?.status).toBe('CANCELLED');
    expect(await bal('alice')).toEqual({ balance: 500, reserved: 0 });
    const b2 = (await create()).betId;
    await respond('bob', b2, true);
    await expectError(handleCancelStepBet(authReq('alice', { betId: b2 })), 'failed-precondition', 'BET_NOT_PENDING');
    expect(await bal('alice')).toEqual({ balance: 400, reserved: 100 });
  });

  test('PENDING bets expire after 48 h: stake released exactly once, even if the job runs repeatedly', async () => {
    const { betId } = await create();
    setClock(T0 + 47 * H);
    expect(await runSettleStepBets()).toEqual({ expired: 0, settled: 0 });
    setClock(T0 + 49 * H);
    expect(await runSettleStepBets()).toEqual({ expired: 1, settled: 0 });
    expect(await runSettleStepBets()).toEqual({ expired: 0, settled: 0 });
    expect(await expireBet(betId)).toBe(false);
    expect((await getDoc(`stepBets/${betId}`))?.status).toBe('EXPIRED');
    expect(await bal('alice')).toEqual({ balance: 500, reserved: 0 });
    expect(await betLedger('alice', betId)).toHaveLength(2);
    expect(await notifs('alice', 'BET_RESULT')).toHaveLength(1);
  });

  test('responding to an expired bet fails with BET_EXPIRED and still releases the stake', async () => {
    const { betId } = await create();
    setClock(T0 + 49 * H);
    await expectError(respond('bob', betId, true), 'failed-precondition', 'BET_EXPIRED');
    expect((await getDoc(`stepBets/${betId}`))?.status).toBe('EXPIRED');
    expect(await bal('alice')).toEqual({ balance: 500, reserved: 0 });
    expect(await bal('bob')).toEqual({ balance: 500, reserved: 0 });
  });
});

describe('settlement (virtual points only)', () => {
  test('live step totals follow verified steps inside the bet window only', async () => {
    const { betId } = await create();
    await respond('bob', betId, true);
    await giveVerifiedSteps('alice', '20260302', 9000); // before the window
    await giveVerifiedSteps('alice', '20260303', 3000);
    await giveVerifiedSteps('bob', '20260304', 2000);
    await giveVerifiedSteps('bob', '20260305', 9999); // after the window
    expect(await getDoc(`stepBets/${betId}`)).toMatchObject({ challengerSteps: 3000, opponentSteps: 2000 });
  });

  test('only one reached the target: that one wins BOTH stakes; loser loses the stake; points are conserved', async () => {
    const betId = await activeBet({ alice: [6000, 5000], bob: [4000, 3000] });
    const a0 = await bal('alice');
    const b0 = await bal('bob');
    setClock(D3 + 2 * DAY + H);
    expect((await runSettleStepBets()).settled).toBe(0); // grace period
    setClock(D3 + 2 * DAY + 7 * H);
    expect(await runSettleStepBets()).toEqual({ expired: 0, settled: 1 });
    const bet = await getDoc(`stepBets/${betId}`);
    expect(bet).toMatchObject({ status: 'COMPLETED', winnerUid: 'alice', resolution: 'ONLY_ONE_REACHED_TARGET', challengerSteps: 11_000, opponentSteps: 7000 });
    expect(await bal('alice')).toEqual({ balance: a0.balance + 200, reserved: a0.reserved - 100 });
    expect(await bal('bob')).toEqual({ balance: b0.balance, reserved: b0.reserved - 100 });
    const total = (await bal('alice')).balance + (await bal('alice')).reserved + (await bal('bob')).balance + (await bal('bob')).reserved;
    expect(total).toBe(a0.balance + a0.reserved + b0.balance + b0.reserved);
    expect((await getDoc(`virtualPointsLedger/BET_${betId}_alice_BET_WIN`))).toMatchObject({ delta: 200, reservedDelta: -100, type: 'BET_WIN' });
    expect((await getDoc(`virtualPointsLedger/BET_${betId}_bob_BET_LOSS`))).toMatchObject({ delta: 0, reservedDelta: -100, type: 'BET_LOSS' });
    expect(await notifs('alice', 'BET_RESULT')).toHaveLength(1);
    expect(await notifs('bob', 'BET_RESULT')).toHaveLength(1);
  });

  test('duplicate settlement is prevented: repeated and concurrent runs pay exactly once', async () => {
    const betId = await activeBet({ alice: [6000, 5000], bob: [4000, 3000] });
    const a0 = await bal('alice');
    setClock(D3 + 2 * DAY + 7 * H);
    const results = await Promise.all([settleBet(betId), settleBet(betId), settleBet(betId)]);
    expect(results.filter(Boolean)).toHaveLength(1);
    await runSettleStepBets();
    await runSettleStepBets();
    expect(await settleBet(betId)).toBe(false);
    expect(await bal('alice')).toEqual({ balance: a0.balance + 200, reserved: a0.reserved - 100 });
    expect((await betLedger('alice', betId)).filter((l) => l.type === 'BET_WIN')).toHaveLength(1);
    expect(await notifs('alice', 'BET_RESULT')).toHaveLength(1);
  });

  test('both reached: higher verified steps wins (HIGHER_STEPS), even for the opponent', async () => {
    const betId = await activeBet({ alice: [5000, 5500], bob: [6000, 6500] }); // 10500 vs 12500
    setClock(D3 + 2 * DAY + 7 * H);
    await runSettleStepBets();
    expect(await getDoc(`stepBets/${betId}`)).toMatchObject({ winnerUid: 'bob', resolution: 'HIGHER_STEPS', status: 'COMPLETED' });
    expect((await betLedger('bob', betId)).map((l) => l.type).sort()).toEqual(['BET_WIN', 'RESERVE']);
    expect((await betLedger('alice', betId)).map((l) => l.type).sort()).toEqual(['BET_LOSS', 'RESERVE']);
  });

  test('both reached with exactly equal steps => REFUND_TIE: both stakes released, no winner', async () => {
    const betId = await activeBet({ alice: [5500, 5500], bob: [5500, 5500] });
    const a0 = await bal('alice');
    const b0 = await bal('bob');
    setClock(D3 + 2 * DAY + 7 * H);
    await runSettleStepBets();
    expect(await getDoc(`stepBets/${betId}`)).toMatchObject({ winnerUid: null, resolution: 'REFUND_TIE', status: 'COMPLETED' });
    expect(await bal('alice')).toEqual({ balance: a0.balance + 100, reserved: a0.reserved - 100 });
    expect(await bal('bob')).toEqual({ balance: b0.balance + 100, reserved: b0.reserved - 100 });
  });

  test('nobody reached the target => REFUND_NONE_REACHED', async () => {
    const betId = await activeBet({ alice: [1000, 2000], bob: [500, 0] });
    setClock(D3 + 2 * DAY + 7 * H);
    await runSettleStepBets();
    expect(await getDoc(`stepBets/${betId}`)).toMatchObject({ winnerUid: null, resolution: 'REFUND_NONE_REACHED' });
    expect((await bal('alice')).reserved).toBe(0);
    expect((await bal('bob')).reserved).toBe(0);
    expect((await betLedger('alice', betId)).map((l) => l.type).sort()).toEqual(['RELEASE', 'RESERVE']);
  });

  test('steps outside the window and non-verified steps do not decide the bet', async () => {
    const { betId } = await create();
    await respond('bob', betId, true);
    await giveVerifiedSteps('bob', '20260302', 50_000); // yesterday-ish: before the window
    await giveVerifiedSteps('bob', '20260305', 50_000); // after the window
    await giveVerifiedSteps('alice', '20260303', 10_000);
    setClock(D3 + 2 * DAY + 7 * H);
    await runSettleStepBets();
    expect(await getDoc(`stepBets/${betId}`)).toMatchObject({ winnerUid: 'alice', resolution: 'ONLY_ONE_REACHED_TARGET', opponentSteps: 0 });
  });

  test('a bet that is still ACTIVE before its end + grace is never settled, not even by a direct call', async () => {
    const betId = await activeBet({ alice: [6000, 5000], bob: [4000, 3000] });
    setClock(D3 + 2 * DAY + H);
    expect(await settleBet(betId)).toBe(false);
    expect((await runSettleStepBets()).settled).toBe(0);
    expect((await getDoc(`stepBets/${betId}`))?.status).toBe('ACTIVE');
    setClock(D3 + 2 * DAY + 7 * H);
    expect(await settleBet(betId)).toBe(true);
  });
});
