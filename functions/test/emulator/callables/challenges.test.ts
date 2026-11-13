import {
  handleCreateBuddyChallenge,
  handleGetChallengeLeaderboard,
  handleJoinChallenge,
  handleLeaveChallenge,
  handleRespondChallengeInvite,
} from '../../../src/challenges/callables';
import { finalizeChallenge, payChallengeRewards, runFinalizeChallenges } from '../../../src/challenges/finalize';
import { runChallengeReminders } from '../../../src/challenges/reminders';
import { setClock } from '../../../src/lib/clock';
import { db, tsFromMs } from '../../../src/lib/firebase';
import { handleUpdateProfile } from '../../../src/profile/profile';
import { processDailySummary } from '../../../src/triggers/dailySummary';
import { authReq, DAY, expectError, freeze, getDoc, giveVerifiedSteps, ledgerFor, makeBuddies, makeUser, resetAll, T0, userDoc } from '../helpers/env';

const D2 = Date.UTC(2026, 2, 1, 18, 30); // IST 2026-03-02 00:00
const D3 = D2 + DAY;
const D4 = D2 + 2 * DAY;
const D5 = D2 + 3 * DAY;

beforeEach(async () => {
  await resetAll();
  freeze();
  await makeUser('alice', { hostelId: 'agira' });
  await makeUser('bob', { hostelId: 'ira' });
  await makeUser('carol', { hostelId: 'agira' });
});
afterAll(() => setClock(null));

const join = (uid: string, challengeId: string) => handleJoinChallenge(authReq(uid, { challengeId }));
const leave = (uid: string, challengeId: string) => handleLeaveChallenge(authReq(uid, { challengeId }));
const notifs = async (uid: string, type: string) => (await db().collection('notifications').where('uid', '==', uid).where('type', '==', type).get()).docs.map((d) => d.data());

async function mkChallenge(id: string, over: Record<string, unknown> = {}): Promise<void> {
  await db()
    .collection('challenges')
    .doc(id)
    .set({
      type: 'CAMPUS',
      title: `Challenge ${id}`,
      description: '',
      metric: 'TOTAL_STEPS',
      target: 1000,
      dailyTarget: null,
      windowMode: 'FIXED',
      startAt: tsFromMs(D2),
      endAt: tsFromMs(D4),
      durationDays: 2,
      status: 'ACTIVE',
      createdBy: 'admin',
      hostelIds: [],
      hostelAggregation: 'AVERAGE_PER_PARTICIPANT',
      maxParticipants: null,
      participantCount: 0,
      rewardPoints: 100,
      isTemplate: false,
      winnerUid: null,
      winnerHostelId: null,
      finalizedAt: null,
      rewardsPending: false,
      ...over,
    });
}

const challengeLedger = async (uid: string, challengeId: string) => (await ledgerFor(uid)).filter((l) => l.refType === 'CHALLENGE' && l.refId === challengeId);

describe('buddy challenge flow', () => {
  test('requires an active buddy connection', async () => {
    await expectError(handleCreateBuddyChallenge(authReq('alice', { buddyUid: 'bob', durationDays: 3, targetSteps: 5000 })), 'failed-precondition', 'NOT_BUDDIES');
  });

  test('input validation', async () => {
    await makeBuddies('alice', 'bob');
    for (const [over, reason] of [
      [{ durationDays: 0 }, 'INVALID_DURATION_DAYS'],
      [{ durationDays: 31 }, 'INVALID_DURATION_DAYS'],
      [{ targetSteps: 10 }, 'INVALID_TARGET_STEPS'],
      [{ buddyUid: 'alice' }, 'INVALID_BUDDY_UID'],
    ] as const) {
      await expectError(handleCreateBuddyChallenge(authReq('alice', { ...{ buddyUid: 'bob', durationDays: 3, targetSteps: 5000 }, ...over })), 'invalid-argument', reason);
    }
  });

  test('invite -> PENDING with creator JOINED and buddy INVITED; duplicate pending invite is blocked; invitee notified', async () => {
    await makeBuddies('alice', 'bob');
    const { challengeId } = await handleCreateBuddyChallenge(authReq('alice', { buddyUid: 'bob', durationDays: 2, targetSteps: 5000 }));
    expect(await getDoc(`challenges/${challengeId}`)).toMatchObject({ type: 'BUDDY', status: 'PENDING', target: 5000, durationDays: 2, participantUids: ['alice', 'bob'], createdBy: 'alice', startAt: null, participantCount: 1 });
    expect(await getDoc(`challengeParticipants/${challengeId}_alice`)).toMatchObject({ status: 'JOINED', progress: 0 });
    expect(await getDoc(`challengeParticipants/${challengeId}_bob`)).toMatchObject({ status: 'INVITED' });
    expect(await notifs('bob', 'CHALLENGE_NEW')).toHaveLength(1);
    await expectError(handleCreateBuddyChallenge(authReq('alice', { buddyUid: 'bob', durationDays: 2, targetSteps: 5000 })), 'already-exists', 'PENDING_INVITE_EXISTS');
  });

  test('accept starts the challenge at the next IST midnight for durationDays; both are JOINED', async () => {
    await makeBuddies('alice', 'bob');
    const { challengeId } = await handleCreateBuddyChallenge(authReq('alice', { buddyUid: 'bob', durationDays: 2, targetSteps: 5000 }));
    await handleRespondChallengeInvite(authReq('bob', { challengeId, accept: true }));
    await handleRespondChallengeInvite(authReq('bob', { challengeId, accept: true })); // idempotent
    const ch = (await getDoc(`challenges/${challengeId}`)) as Record<string, { toMillis(): number } | unknown>;
    expect(ch.status).toBe('UPCOMING');
    expect((ch.startAt as { toMillis(): number }).toMillis()).toBe(D3);
    expect((ch.endAt as { toMillis(): number }).toMillis()).toBe(D5);
    expect(ch.participantCount).toBe(2);
    expect(await getDoc(`challengeParticipants/${challengeId}_bob`)).toMatchObject({ status: 'JOINED' });
  });

  test('only the invited buddy can respond; decline cancels the challenge', async () => {
    await makeBuddies('alice', 'bob');
    const { challengeId } = await handleCreateBuddyChallenge(authReq('alice', { buddyUid: 'bob', durationDays: 2, targetSteps: 5000 }));
    await expectError(handleRespondChallengeInvite(authReq('carol', { challengeId, accept: true })), 'permission-denied', 'NOT_INVITED');
    await expectError(handleRespondChallengeInvite(authReq('alice', { challengeId, accept: true })), 'permission-denied', 'NOT_INVITED');
    await handleRespondChallengeInvite(authReq('bob', { challengeId, accept: false }));
    expect(await getDoc(`challenges/${challengeId}`)).toMatchObject({ status: 'CANCELLED' });
    expect(await getDoc(`challengeParticipants/${challengeId}_bob`)).toMatchObject({ status: 'LEFT' });
    await expectError(handleRespondChallengeInvite(authReq('bob', { challengeId, accept: true })), 'failed-precondition', 'INVITE_NOT_PENDING');
  });

  test('buddy challenges cannot be joined directly or left', async () => {
    await makeBuddies('alice', 'bob');
    const { challengeId } = await handleCreateBuddyChallenge(authReq('alice', { buddyUid: 'bob', durationDays: 2, targetSteps: 5000 }));
    await expectError(join('carol', challengeId), 'failed-precondition', 'USE_INVITE_FLOW');
    await handleRespondChallengeInvite(authReq('bob', { challengeId, accept: true }));
    await expectError(leave('bob', challengeId), 'failed-precondition', 'CANNOT_LEAVE_BUDDY_CHALLENGE');
  });

  test('full lifecycle: activate, progress from verified steps only, finalize after the grace, ONE winner reward + badge', async () => {
    await makeBuddies('alice', 'bob');
    const { challengeId } = await handleCreateBuddyChallenge(authReq('alice', { buddyUid: 'bob', durationDays: 2, targetSteps: 5000 }));
    await handleRespondChallengeInvite(authReq('bob', { challengeId, accept: true }));

    setClock(D3 + 3_600_000);
    expect(await runFinalizeChallenges()).toMatchObject({ activated: 1, finalized: 0 });
    expect((await getDoc(`challenges/${challengeId}`))?.status).toBe('ACTIVE');

    await giveVerifiedSteps('alice', '20260302', 9000); // before the window: does NOT count
    await giveVerifiedSteps('alice', '20260303', 3000);
    await giveVerifiedSteps('alice', '20260304', 3500);
    await giveVerifiedSteps('bob', '20260303', 4000);
    expect(await getDoc(`challengeParticipants/${challengeId}_alice`)).toMatchObject({ progress: 6500 });
    expect(await getDoc(`challengeParticipants/${challengeId}_bob`)).toMatchObject({ progress: 4000 });

    // Inside the grace period nothing is finalized yet.
    setClock(D5 + 3_600_000);
    expect((await runFinalizeChallenges()).finalized).toBe(0);
    expect((await getDoc(`challenges/${challengeId}`))?.status).toBe('ACTIVE');

    setClock(D5 + 7 * 3_600_000);
    const rep = await runFinalizeChallenges();
    expect(rep).toMatchObject({ finalized: 1 });
    const ch = await getDoc(`challenges/${challengeId}`);
    expect(ch).toMatchObject({ status: 'COMPLETED', winnerUid: 'alice', rewardsPending: false });
    const res = await getDoc(`challengeResults/${challengeId}`);
    expect(res).toMatchObject({ type: 'BUDDY', winnerUid: 'alice', participantCount: 2, participantUids: ['alice', 'bob'] });
    expect(res?.ranking).toEqual([
      { rank: 1, uid: 'alice', name: 'User alice', value: 6500 },
      { rank: 2, uid: 'bob', name: 'User bob', value: 4000 },
    ]);

    const win = await challengeLedger('alice', challengeId);
    expect(win).toHaveLength(1);
    expect(win[0]).toMatchObject({ delta: 100, type: 'REWARD' });
    expect(await challengeLedger('bob', challengeId)).toHaveLength(0);
    expect(await getDoc('achievements/alice_CHALLENGE_CHAMPION')).toMatchObject({ uid: 'alice', refId: challengeId });
    expect((await notifs('alice', 'CHALLENGE_DONE')).length).toBeGreaterThan(0);

    // Re-running everything never pays twice.
    const balance = (await userDoc('alice')).pointsBalance;
    await runFinalizeChallenges();
    expect(await finalizeChallenge(challengeId)).toBe(false);
    expect(await payChallengeRewards(challengeId)).toBe(0);
    expect(await challengeLedger('alice', challengeId)).toHaveLength(1);
    expect((await userDoc('alice')).pointsBalance).toBe(balance);
    expect(await getDoc('achievements/alice_CHALLENGE_CHAMPION')).toBeDefined();
  });

  test('nobody reaching the target => no winner, no reward', async () => {
    await makeBuddies('alice', 'bob');
    const { challengeId } = await handleCreateBuddyChallenge(authReq('alice', { buddyUid: 'bob', durationDays: 2, targetSteps: 5000 }));
    await handleRespondChallengeInvite(authReq('bob', { challengeId, accept: true }));
    setClock(D3 + 3_600_000);
    await runFinalizeChallenges();
    await giveVerifiedSteps('alice', '20260303', 4000);
    await giveVerifiedSteps('bob', '20260303', 4500);
    setClock(D5 + 7 * 3_600_000);
    await runFinalizeChallenges();
    expect(await getDoc(`challenges/${challengeId}`)).toMatchObject({ status: 'COMPLETED', winnerUid: null });
    expect(await challengeLedger('alice', challengeId)).toHaveLength(0);
    expect(await challengeLedger('bob', challengeId)).toHaveLength(0);
  });
});

describe('join / leave / duplicate join', () => {
  test('joining an INDIVIDUAL template sets a rolling window starting today; duplicate join is rejected; count is exact', async () => {
    const r = await join('alice', 'tpl_steps-50k-weekly');
    expect(r.ok).toBe(true);
    expect(await getDoc('challengeParticipants/tpl_steps-50k-weekly_alice')).toMatchObject({ status: 'JOINED', windowStart: '20260302', windowEnd: '20260308', progress: 0, rewardPaid: false, hostelId: 'agira' });
    await expectError(join('alice', 'tpl_steps-50k-weekly'), 'already-exists', 'ALREADY_JOINED');
    expect((await getDoc('challenges/tpl_steps-50k-weekly'))?.participantCount).toBe(1);
    await join('bob', 'tpl_steps-50k-weekly');
    expect((await getDoc('challenges/tpl_steps-50k-weekly'))?.participantCount).toBe(2);
  });

  test('concurrent duplicate joins create exactly one participation', async () => {
    const results = await Promise.allSettled([join('alice', 'tpl_streak-7'), join('alice', 'tpl_streak-7'), join('alice', 'tpl_streak-7')]);
    expect(results.filter((x) => x.status === 'fulfilled')).toHaveLength(1);
    expect((await getDoc('challenges/tpl_streak-7'))?.participantCount).toBe(1);
  });

  test('leave sets LEFT and decrements the count; leaving again is idempotent; re-join is allowed', async () => {
    await join('alice', 'tpl_streak-7');
    await leave('alice', 'tpl_streak-7');
    await leave('alice', 'tpl_streak-7');
    expect(await getDoc('challengeParticipants/tpl_streak-7_alice')).toMatchObject({ status: 'LEFT' });
    expect((await getDoc('challenges/tpl_streak-7'))?.participantCount).toBe(0);
    await join('alice', 'tpl_streak-7');
    expect(await getDoc('challengeParticipants/tpl_streak-7_alice')).toMatchObject({ status: 'JOINED', progress: 0 });
    expect((await getDoc('challenges/tpl_streak-7'))?.participantCount).toBe(1);
  });

  test('unknown challenge, never-joined leave, ended and cancelled challenges', async () => {
    await expectError(join('alice', 'nope'), 'not-found', 'CHALLENGE_NOT_FOUND');
    await expectError(leave('alice', 'tpl_streak-7'), 'not-found', 'NOT_PARTICIPANT');
    await mkChallenge('old', { startAt: tsFromMs(D2 - 5 * DAY), endAt: tsFromMs(D2 - DAY) });
    await expectError(join('alice', 'old'), 'failed-precondition', 'CHALLENGE_ENDED');
    await mkChallenge('cancelled', { status: 'CANCELLED' });
    await expectError(join('alice', 'cancelled'), 'failed-precondition', 'CHALLENGE_NOT_JOINABLE');
  });

  test('maxParticipants is enforced; INTER_HOSTEL requires an eligible hostel', async () => {
    await mkChallenge('small', { maxParticipants: 1 });
    await join('alice', 'small');
    await expectError(join('bob', 'small'), 'resource-exhausted', 'CHALLENGE_FULL');
    await mkChallenge('hostels', { type: 'INTER_HOSTEL', hostelIds: ['ira', 'vyom'] });
    await expectError(join('alice', 'hostels'), 'permission-denied', 'HOSTEL_NOT_ELIGIBLE');
    await join('bob', 'hostels');
  });

  test('upcoming FIXED challenges are joinable; ROLLING challenges must be ACTIVE', async () => {
    await mkChallenge('soon', { status: 'UPCOMING', startAt: tsFromMs(D3), endAt: tsFromMs(D5) });
    await join('alice', 'soon');
    await db().collection('challenges').doc('tpl_streak-7').update({ status: 'CANCELLED' });
    await expectError(join('bob', 'tpl_streak-7'), 'failed-precondition', 'CHALLENGE_NOT_JOINABLE');
  });

  test('non-eligible callers cannot join', async () => {
    await expectError(join('alice', 'tpl_streak-7').then(() => handleJoinChallenge(authReq('alice', { challengeId: 'x' }, { verified: false }))), 'permission-denied', 'EMAIL_NOT_VERIFIED');
  });
});

describe('individual challenge progress and completion (server computed, single reward)', () => {
  test('steps walked earlier the same day count at join; steps before the join day never count', async () => {
    await giveVerifiedSteps('alice', '20260301', 9000);
    await giveVerifiedSteps('alice', '20260302', 2500);
    await join('alice', 'tpl_steps-50k-weekly');
    expect((await getDoc('challengeParticipants/tpl_steps-50k-weekly_alice'))?.progress).toBe(2500);
  });

  test('TOTAL_STEPS completes once the target is reached inside the window: status COMPLETED, reward paid ONCE even if the trigger re-runs', async () => {
    await join('alice', 'tpl_steps-50k-weekly');
    await giveVerifiedSteps('alice', '20260302', 20_000);
    await giveVerifiedSteps('alice', '20260303', 20_000);
    expect((await getDoc('challengeParticipants/tpl_steps-50k-weekly_alice'))?.status).toBe('JOINED');
    await giveVerifiedSteps('alice', '20260304', 10_000);
    expect(await getDoc('challengeParticipants/tpl_steps-50k-weekly_alice')).toMatchObject({ status: 'COMPLETED', progress: 50_000, rewardPaid: true });
    for (let i = 0; i < 3; i++) await processDailySummary('alice', '20260304');
    const l = await challengeLedger('alice', 'tpl_steps-50k-weekly');
    expect(l).toHaveLength(1);
    expect(l[0]).toMatchObject({ delta: 60, type: 'REWARD', id: 'CHALLENGE_tpl_steps-50k-weekly_alice_REWARD' });
    expect(await notifs('alice', 'CHALLENGE_DONE')).toHaveLength(1);
    await expectError(join('alice', 'tpl_steps-50k-weekly'), 'already-exists', 'ALREADY_COMPLETED');
    await expectError(leave('alice', 'tpl_steps-50k-weekly'), 'failed-precondition', 'ALREADY_COMPLETED');
  });

  test('steps outside the 7-day window do not count', async () => {
    await join('alice', 'tpl_steps-50k-weekly');
    await giveVerifiedSteps('alice', '20260309', 60_000); // day 8
    expect((await getDoc('challengeParticipants/tpl_steps-50k-weekly_alice'))?.status).toBe('JOINED');
    expect((await getDoc('challengeParticipants/tpl_steps-50k-weekly_alice'))?.progress).toBe(0);
  });

  test('DAILY_TARGET_DAYS counts days at or above the daily target', async () => {
    await join('alice', 'tpl_fitness-30');
    for (const [d, v] of [['20260302', 5000], ['20260303', 4999], ['20260304', 7000], ['20260305', 5000]] as const) await giveVerifiedSteps('alice', d, v);
    expect((await getDoc('challengeParticipants/tpl_fitness-30_alice'))?.progress).toBe(3);
  });

  test('STREAK_DAYS is the longest consecutive run and a gap does not erase it', async () => {
    await join('alice', 'tpl_streak-7');
    for (const d of ['20260302', '20260303', '20260304', '20260306']) await giveVerifiedSteps('alice', d, 5200);
    expect((await getDoc('challengeParticipants/tpl_streak-7_alice'))?.progress).toBe(3);
    for (const d of ['20260305', '20260307', '20260308']) await giveVerifiedSteps('alice', d, 5200);
    expect(await getDoc('challengeParticipants/tpl_streak-7_alice')).toMatchObject({ status: 'COMPLETED', progress: 7 });
    expect(await challengeLedger('alice', 'tpl_streak-7')).toHaveLength(1);
  });

  test('1-day daily template completes on a single big day; recomputation is idempotent', async () => {
    await join('alice', 'tpl_steps-5k-daily');
    await giveVerifiedSteps('alice', '20260302', 5100);
    expect(await getDoc('challengeParticipants/tpl_steps-5k-daily_alice')).toMatchObject({ status: 'COMPLETED' });
    expect((await challengeLedger('alice', 'tpl_steps-5k-daily'))[0].delta).toBe(20);
  });

  test('a rolling participation whose window passed without completion becomes LEFT and can be re-joined', async () => {
    await join('alice', 'tpl_steps-10k-daily');
    setClock(D3 + 12 * 3_600_000);
    expect((await runFinalizeChallenges()).participantsExpired).toBe(1);
    expect(await getDoc('challengeParticipants/tpl_steps-10k-daily_alice')).toMatchObject({ status: 'LEFT', endedReason: 'WINDOW_ENDED' });
    expect((await getDoc('challenges/tpl_steps-10k-daily'))?.participantCount).toBe(0);
    await join('alice', 'tpl_steps-10k-daily');
    expect((await getDoc('challengeParticipants/tpl_steps-10k-daily_alice'))?.status).toBe('JOINED');
  });
});

describe('finalizeChallenges: campus and inter-hostel winners', () => {
  test('CAMPUS: winner is the top verified-steps participant; reward + badges paid once; concurrent finalize is safe', async () => {
    await mkChallenge('campus1');
    for (const u of ['alice', 'bob', 'carol']) await join(u, 'campus1');
    await giveVerifiedSteps('alice', '20260302', 3000);
    await giveVerifiedSteps('bob', '20260302', 5000);
    await giveVerifiedSteps('carol', '20260303', 1000);
    await giveVerifiedSteps('carol', '20260304', 99_999); // outside window (ends D4 exclusive)

    setClock(D4 + 3_600_000);
    expect((await runFinalizeChallenges()).finalized).toBe(0); // grace not over

    setClock(D4 + 7 * 3_600_000);
    const results = await Promise.all([finalizeChallenge('campus1'), finalizeChallenge('campus1'), finalizeChallenge('campus1')]);
    expect(results.filter(Boolean)).toHaveLength(1);
    await runFinalizeChallenges();

    const ch = await getDoc('challenges/campus1');
    expect(ch).toMatchObject({ status: 'COMPLETED', winnerUid: 'bob', rewardsPending: false });
    expect((await getDoc('challengeResults/campus1'))?.ranking).toEqual([
      { rank: 1, uid: 'bob', name: 'User bob', value: 5000 },
      { rank: 2, uid: 'alice', name: 'User alice', value: 3000 },
      { rank: 3, uid: 'carol', name: 'User carol', value: 1000 },
    ]);
    expect(await challengeLedger('bob', 'campus1')).toHaveLength(1);
    expect(await challengeLedger('alice', 'campus1')).toHaveLength(0);
    expect(await getDoc('achievements/bob_CAMPUS_FITNESS_STAR')).toBeDefined();
    expect(await getDoc('achievements/bob_CHALLENGE_CHAMPION')).toBeDefined();
    expect(await getDoc('achievements/alice_CAMPUS_FITNESS_STAR')).toBeUndefined();
    await payChallengeRewards('campus1');
    expect(await challengeLedger('bob', 'campus1')).toHaveLength(1);
    expect((await notifs('alice', 'CHALLENGE_DONE')).length).toBe(1);
  });

  test('INTER_HOSTEL by average per participant: smaller but more active hostel wins; only its participants are rewarded', async () => {
    await mkChallenge('clash', { type: 'INTER_HOSTEL', hostelIds: ['agira', 'ira'], hostelAggregation: 'AVERAGE_PER_PARTICIPANT' });
    for (const u of ['alice', 'bob', 'carol']) await join(u, 'clash');
    await giveVerifiedSteps('alice', '20260302', 6000); // agira
    await giveVerifiedSteps('carol', '20260302', 2000); // agira  => avg 4000, total 8000
    await giveVerifiedSteps('bob', '20260302', 5000); // ira    => avg 5000, total 5000
    setClock(D4 + 7 * 3_600_000);
    await runFinalizeChallenges();
    expect(await getDoc('challenges/clash')).toMatchObject({ status: 'COMPLETED', winnerHostelId: 'ira', winnerUid: null });
    const res = await getDoc('challengeResults/clash');
    expect(res?.ranking).toEqual([
      { rank: 1, hostelId: 'ira', name: 'Ira Hall', value: 5000 },
      { rank: 2, hostelId: 'agira', name: 'Agira Hall', value: 4000 },
    ]);
    expect(await challengeLedger('bob', 'clash')).toHaveLength(1);
    expect(await challengeLedger('alice', 'clash')).toHaveLength(0);
    expect(await getDoc('achievements/bob_HOSTEL_CHAMPION')).toBeDefined();
    expect((await notifs('bob', 'HOSTEL_RESULT')).length).toBe(1);
    await runFinalizeChallenges();
    expect(await challengeLedger('bob', 'clash')).toHaveLength(1);
  });

  test('INTER_HOSTEL by TOTAL: the bigger hostel wins', async () => {
    await mkChallenge('clash2', { type: 'INTER_HOSTEL', hostelIds: ['agira', 'ira'], hostelAggregation: 'TOTAL' });
    for (const u of ['alice', 'bob', 'carol']) await join(u, 'clash2');
    await giveVerifiedSteps('alice', '20260302', 6000);
    await giveVerifiedSteps('carol', '20260302', 2000);
    await giveVerifiedSteps('bob', '20260302', 5000);
    setClock(D4 + 7 * 3_600_000);
    await runFinalizeChallenges();
    expect(await getDoc('challenges/clash2')).toMatchObject({ winnerHostelId: 'agira' });
    expect(await challengeLedger('alice', 'clash2')).toHaveLength(1);
    expect(await challengeLedger('carol', 'clash2')).toHaveLength(1);
    expect(await challengeLedger('bob', 'clash2')).toHaveLength(0);
  });

  test('a cancelled challenge is never finalized or paid', async () => {
    await mkChallenge('cx');
    await join('alice', 'cx');
    await giveVerifiedSteps('alice', '20260302', 3000);
    await db().collection('challenges').doc('cx').update({ status: 'CANCELLED' });
    setClock(D4 + 7 * 3_600_000);
    expect((await runFinalizeChallenges()).finalized).toBe(0);
    expect(await getDoc('challengeResults/cx')).toBeUndefined();
    expect(await challengeLedger('alice', 'cx')).toHaveLength(0);
  });

  test('rewards are resumable: if payment crashed after finalize, the next run pays exactly once', async () => {
    await mkChallenge('resume');
    await join('alice', 'resume');
    await giveVerifiedSteps('alice', '20260302', 3000);
    setClock(D4 + 7 * 3_600_000);
    await finalizeChallenge('resume');
    // Simulate a crash before the reward step completed.
    await db().collection('virtualPointsLedger').doc('CHALLENGE_resume_alice_REWARD').delete();
    await db().collection('achievements').doc('alice_CHALLENGE_CHAMPION').delete();
    await db().collection('achievements').doc('alice_CAMPUS_FITNESS_STAR').delete();
    await db().collection('users').doc('alice').update({ pointsBalance: 0 });
    await db().collection('challenges').doc('resume').update({ rewardsPending: true });
    await runFinalizeChallenges();
    expect(await challengeLedger('alice', 'resume')).toHaveLength(1);
    await runFinalizeChallenges();
    expect(await challengeLedger('alice', 'resume')).toHaveLength(1);
  });
});

describe('getChallengeLeaderboard', () => {
  test('ranks participants by verified progress with progressPct and my rank', async () => {
    await mkChallenge('lb', { target: 4000 });
    for (const u of ['alice', 'bob', 'carol']) await join(u, 'lb');
    await giveVerifiedSteps('alice', '20260302', 1000);
    await giveVerifiedSteps('bob', '20260302', 3000);
    await giveVerifiedSteps('carol', '20260302', 1000);
    const r = await handleGetChallengeLeaderboard(authReq('carol', { challengeId: 'lb' }));
    expect([...r.entries].sort((a, b) => Number(a.rank) - Number(b.rank) || String(a.uid).localeCompare(String(b.uid))).map((e) => [e.uid, e.rank, e.value, e.progressPct])).toEqual([
      ['bob', 1, 3000, 75],
      ['alice', 2, 1000, 25],
      ['carol', 2, 1000, 25],
    ]);
    expect(r.me).toEqual({ rank: 2, value: 1000 });
    expect(r.metricLabel).toBe('Verified steps');
    const outsider = await handleGetChallengeLeaderboard(authReq('bob', { challengeId: 'lb', limit: 1 }));
    expect(outsider.entries).toHaveLength(1);
  });

  test('a participant who left is not listed and has no rank', async () => {
    await mkChallenge('lb2');
    await join('alice', 'lb2');
    await join('bob', 'lb2');
    await leave('bob', 'lb2');
    const r = await handleGetChallengeLeaderboard(authReq('bob', { challengeId: 'lb2' }));
    expect(r.entries.map((e) => e.uid)).toEqual(['alice']);
    expect(r.me.rank).toBeNull();
  });

  test('BUDDY leaderboards are visible to participants only', async () => {
    await makeBuddies('alice', 'bob');
    const { challengeId } = await handleCreateBuddyChallenge(authReq('alice', { buddyUid: 'bob', durationDays: 2, targetSteps: 5000 }));
    await expectError(handleGetChallengeLeaderboard(authReq('carol', { challengeId })), 'permission-denied', 'NOT_PARTICIPANT');
    expect((await handleGetChallengeLeaderboard(authReq('bob', { challengeId }))).entries.length).toBeGreaterThanOrEqual(1);
  });

  test('INTER_HOSTEL leaderboard aggregates hostels (average per participant by default)', async () => {
    await mkChallenge('lbh', { type: 'INTER_HOSTEL', hostelIds: ['agira', 'ira', 'vyom'] });
    for (const u of ['alice', 'bob', 'carol']) await join(u, 'lbh');
    await giveVerifiedSteps('alice', '20260302', 6000);
    await giveVerifiedSteps('carol', '20260302', 2000);
    await giveVerifiedSteps('bob', '20260302', 5000);
    const r = await handleGetChallengeLeaderboard(authReq('alice', { challengeId: 'lbh' }));
    expect(r.entries.map((e) => [e.hostelId, e.value, e.rank])).toEqual([
      ['ira', 5000, 1],
      ['agira', 4000, 2],
      ['vyom', 0, 3],
    ]);
    expect(r.me).toEqual({ rank: 2, value: 4000 });
    expect(r.metricLabel).toContain('average per participant');
  });
});

describe('challengeReminders: at most one per user / challenge / day', () => {
  test('re-running the job (or a retry) does not repeat; a new day produces a new reminder', async () => {
    await join('alice', 'tpl_steps-50k-weekly');
    expect(await runChallengeReminders()).toMatchObject({ sent: 1 });
    expect(await runChallengeReminders()).toMatchObject({ sent: 0 });
    expect(await notifs('alice', 'CHALLENGE_REMINDER')).toHaveLength(1);
    setClock(T0 + DAY);
    expect(await runChallengeReminders()).toMatchObject({ sent: 1 });
    expect(await notifs('alice', 'CHALLENGE_REMINDER')).toHaveLength(2);
  });

  test('users who disabled reminders, completed participants and left participants get nothing', async () => {
    await handleUpdateProfile(authReq('bob', { notificationPrefs: { reminders: false } }));
    await join('alice', 'tpl_steps-5k-daily');
    await join('bob', 'tpl_steps-50k-weekly');
    await join('carol', 'tpl_steps-50k-weekly');
    await leave('carol', 'tpl_steps-50k-weekly');
    await giveVerifiedSteps('alice', '20260302', 6000); // completes
    expect((await runChallengeReminders()).sent).toBe(0);
  });
});
