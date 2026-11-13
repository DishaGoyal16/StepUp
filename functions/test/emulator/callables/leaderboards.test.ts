import { handleGetLeaderboard } from '../../../src/leaderboards/getLeaderboard';
import { setClock } from '../../../src/lib/clock';
import { db } from '../../../src/lib/firebase';
import { handleUpdateProfile } from '../../../src/profile/profile';
import { processDailySummary } from '../../../src/triggers/dailySummary';
import { runRefreshWeeklySteps } from '../../../src/triggers/weekly';
import { authReq, DAY, expectError, getDoc, giveVerifiedSteps, makeBuddies, makeUser, resetAll } from '../helpers/env';

const WED = Date.UTC(2026, 0, 7, 6, 30); // Wed 2026-01-07 12:00 IST

const users: Array<[string, string]> = [
  ['a1', 'agira'],
  ['a2', 'agira'],
  ['a3', 'agira'],
  ['i1', 'ira'],
  ['i2', 'ira'],
  ['v1', 'vyom'],
];

/** Known fixtures (verified steps per IST day). See expectations in the tests below. */
const fixtures: Array<[string, string, number]> = [
  ['a1', '20260107', 8000],
  ['a1', '20260106', 4000],
  ['a1', '20260104', 3000], // Sunday of the previous ISO week
  ['a1', '20251231', 2000], // previous month
  ['a2', '20260107', 2000],
  ['a2', '20260105', 1000],
  ['a3', '20260106', 500],
  ['i1', '20260107', 6000],
  ['i2', '20260107', 4000],
  ['i2', '20260105', 1000],
];

beforeEach(async () => {
  await resetAll();
  setClock(WED);
  for (const [uid, hostelId] of users) await makeUser(uid, { hostelId });
  for (const [uid, day, v] of fixtures) await giveVerifiedSteps(uid, day, v);
});
afterAll(() => setClock(null));

const lb = (uid: string, scope: string, period: string, extra: Record<string, unknown> = {}) => handleGetLeaderboard(authReq(uid, { scope, period, ...extra }));
const rows = (r: { entries: Array<Record<string, unknown>> }, key = 'value') => r.entries.map((e) => [e.uid ?? e.hostelId, e[key], e.rank]);

describe('campus leaderboards (daily / weekly / monthly / all-time) from known fixtures', () => {
  test('DAILY', async () => {
    const r = await lb('a1', 'CAMPUS', 'DAILY');
    expect(r.periodKey).toBe('20260107');
    expect(rows(r)).toEqual([
      ['a1', 8000, 1],
      ['i1', 6000, 2],
      ['i2', 4000, 3],
      ['a2', 2000, 4],
    ]);
    expect(r.me).toEqual({ rank: 1, value: 8000 });
    expect(r.metricLabel).toBe('Verified steps');
    expect(r.entries[0]).toMatchObject({ uid: 'a1', name: 'User a1', hostelId: 'agira' });
    expect(r.entries[0]).not.toHaveProperty('email');
  });

  test('WEEKLY: the ISO week starts Monday; Sunday 2026-01-04 belongs to the previous week', async () => {
    const r = await lb('a2', 'CAMPUS', 'WEEKLY');
    expect(r.periodKey).toBe('20260105');
    expect(rows(r)).toEqual([
      ['a1', 12000, 1],
      ['i1', 6000, 2],
      ['i2', 5000, 3],
      ['a2', 3000, 4],
      ['a3', 500, 5],
    ]);
    expect(r.me).toEqual({ rank: 4, value: 3000 });
    // previous week (Mon 2025-12-29 .. Sun 2026-01-04) = 2000 (Dec 31) + 3000 (Jan 4)
    expect(await getDoc('leaderboards/CAMPUS_20251229/entries/a1')).toMatchObject({ verifiedSteps: 5000 });
  });

  test('MONTHLY: 202601 excludes December', async () => {
    const r = await lb('a3', 'CAMPUS', 'MONTHLY');
    expect(r.periodKey).toBe('202601');
    expect(rows(r)).toEqual([
      ['a1', 15000, 1],
      ['i1', 6000, 2],
      ['i2', 5000, 3],
      ['a2', 3000, 4],
      ['a3', 500, 5],
    ]);
    expect(await getDoc('leaderboards/CAMPUS_202512/entries/a1')).toMatchObject({ verifiedSteps: 2000 });
  });

  test('ALL_TIME', async () => {
    const r = await lb('i1', 'CAMPUS', 'ALL_TIME');
    expect(r.periodKey).toBe('ALL');
    expect(rows(r)).toEqual([
      ['a1', 17000, 1],
      ['i1', 6000, 2],
      ['i2', 5000, 3],
      ['a2', 3000, 4],
      ['a3', 500, 5],
    ]);
    expect(r.me).toEqual({ rank: 2, value: 6000 });
  });

  test('users with no verified steps in the period have no rank; ties share a rank', async () => {
    const none = await lb('v1', 'CAMPUS', 'DAILY');
    expect(none.me).toEqual({ rank: null, value: 0 });
    await giveVerifiedSteps('v1', '20260107', 6000);
    const r = await lb('v1', 'CAMPUS', 'DAILY');
    expect(rows(r).slice(0, 3)).toEqual([
      ['a1', 8000, 1],
      ['i1', 6000, 2],
      ['v1', 6000, 2],
    ]);
    expect(r.me).toEqual({ rank: 2, value: 6000 });
  });

  test('limit is honoured', async () => {
    expect((await lb('a1', 'CAMPUS', 'DAILY', { limit: 2 })).entries).toHaveLength(2);
  });

  test('derived values live in the user doc and public profile as well', async () => {
    const pub = await getDoc('publicProfiles/a1');
    expect(pub?.weeklyVerifiedSteps).toBe(12000);
    const u = (await db().collection('users').doc('a1').get()).data();
    expect(u?.lifetimeVerifiedSteps).toBe(17000);
  });
});

describe('hostel leaderboard: total AND average per participant', () => {
  test('aggregate entry documents', async () => {
    expect(await getDoc('leaderboards/HOSTELS_20260105/entries/agira')).toMatchObject({ hostelId: 'agira', totalVerifiedSteps: 15500, participants: 3, averagePerParticipant: 5166.67, displayName: 'Agira Hall' });
    expect(await getDoc('leaderboards/HOSTELS_20260105/entries/ira')).toMatchObject({ totalVerifiedSteps: 11000, participants: 2, averagePerParticipant: 5500 });
  });

  test('default ranking metric is the average per participant (small active hostel beats big hostel)', async () => {
    const r = await lb('a1', 'HOSTELS', 'WEEKLY');
    expect(r.metricLabel).toBe('Average verified steps per participant');
    expect(r.entries).toHaveLength(18); // every active hostel is listed, zero-participant ones too
    expect(r.entries[0]).toMatchObject({ hostelId: 'ira', rank: 1, value: 5500, total: 11000, participants: 2, average: 5500, name: 'Ira Hall' });
    expect(r.entries[1]).toMatchObject({ hostelId: 'agira', rank: 2, value: 5166.67, total: 15500, participants: 3, average: 5166.67 });
    expect(r.entries[17]).toMatchObject({ value: 0, participants: 0 });
    expect(r.me).toEqual({ rank: 2, value: 5166.67 });
  });

  test('TOTAL metric ranks by total verified steps and is labelled as such', async () => {
    const r = await lb('i1', 'HOSTELS', 'WEEKLY', { hostelMetric: 'TOTAL' });
    expect(r.metricLabel).toBe('Total verified steps');
    expect(r.entries[0]).toMatchObject({ hostelId: 'agira', rank: 1, value: 15500 });
    expect(r.entries[1]).toMatchObject({ hostelId: 'ira', rank: 2, value: 11000 });
    expect(r.me).toEqual({ rank: 2, value: 11000 });
  });

  test('daily ties share a rank; monthly view', async () => {
    const d = await lb('a1', 'HOSTELS', 'DAILY');
    expect(d.entries[0]).toMatchObject({ hostelId: 'agira', value: 5000, rank: 1 });
    expect(d.entries[1]).toMatchObject({ hostelId: 'ira', value: 5000, rank: 1 });
    const m = await lb('a1', 'HOSTELS', 'MONTHLY');
    expect(m.entries[0]).toMatchObject({ hostelId: 'agira', total: 18500, participants: 3 });
  });

  test('MY_HOSTEL lists only my hostel (students of other hostels are not shown)', async () => {
    const r = await lb('a3', 'MY_HOSTEL', 'WEEKLY');
    expect(rows(r)).toEqual([
      ['a1', 12000, 1],
      ['a2', 3000, 2],
      ['a3', 500, 3],
    ]);
    expect(r.me).toEqual({ rank: 3, value: 500 });
  });

  test('hostel aggregates recompute correctly after a hostel change (both hostels updated)', async () => {
    await handleUpdateProfile(authReq('a2', { hostelId: 'ira' }));
    expect(await getDoc('leaderboards/HOSTELS_20260105/entries/agira')).toMatchObject({ totalVerifiedSteps: 12500, participants: 2 });
    expect(await getDoc('leaderboards/HOSTELS_20260105/entries/ira')).toMatchObject({ totalVerifiedSteps: 14000, participants: 3 });
  });
});

describe('buddies leaderboard and privacy', () => {
  test('BUDDIES scope contains only me and my active buddies', async () => {
    await makeBuddies('a1', 'i1');
    await makeBuddies('a1', 'a2');
    const r = await lb('a1', 'BUDDIES', 'WEEKLY');
    expect(rows(r)).toEqual([
      ['a1', 12000, 1],
      ['i1', 6000, 2],
      ['a2', 3000, 3],
    ]);
    expect(r.me).toEqual({ rank: 1, value: 12000 });
  });

  test('showOnLeaderboards=false hides the student from boards (name anonymised) but my own value/rank is still reported to me', async () => {
    await handleUpdateProfile(authReq('i2', { privacy: { showOnLeaderboards: false } }));
    const r = await lb('a1', 'CAMPUS', 'DAILY');
    expect(r.entries.map((e) => e.uid)).toEqual(['a1', 'i1', 'a2']);
    const mine = await lb('i2', 'CAMPUS', 'DAILY');
    expect(mine.me).toEqual({ rank: null, value: 4000 });
    const entry = await getDoc('leaderboards/CAMPUS_20260107/entries/i2');
    expect(entry).toMatchObject({ displayName: 'Student', photoUrl: null, showOnLeaderboards: false });
    // aggregates still include them (a hostel total is not identifying)
    expect(await getDoc('leaderboards/HOSTELS_20260107/entries/ira')).toMatchObject({ totalVerifiedSteps: 10000, participants: 2 });
  });

  test('showHostel=false hides the hostel in the response', async () => {
    await handleUpdateProfile(authReq('a1', { privacy: { showHostel: false } }));
    const r = await lb('i1', 'CAMPUS', 'DAILY');
    expect(r.entries.find((e) => e.uid === 'a1')).toMatchObject({ hostelId: null });
  });

  test('validation and access', async () => {
    await expectError(lb('a1', 'GALAXY', 'DAILY'), 'invalid-argument', 'INVALID_SCOPE');
    await expectError(lb('a1', 'CAMPUS', 'YEARLY'), 'invalid-argument', 'INVALID_PERIOD');
    await expectError(handleGetLeaderboard(authReq('a1', { scope: 'CAMPUS', period: 'DAILY' }, { email: 'a1@gmail.com' })), 'permission-denied', 'INVALID_EMAIL_DOMAIN');
    await expectError(handleGetLeaderboard(authReq('ghost', { scope: 'CAMPUS', period: 'DAILY' })), 'failed-precondition', 'PROFILE_REQUIRED');
  });
});

describe('recomputation is idempotent (never blind increments)', () => {
  const snapshot = async () => {
    const out: Record<string, unknown> = {};
    for (const col of ['CAMPUS_20260107', 'CAMPUS_20260105', 'CAMPUS_202601', 'CAMPUS_ALL', 'HOSTELS_20260105', 'HOSTELS_202601']) {
      const s = await db().collection('leaderboards').doc(col).collection('entries').get();
      for (const d of s.docs) {
        const { updatedAt: _u, ...rest } = d.data();
        out[`${col}/${d.id}`] = rest;
      }
    }
    return JSON.stringify(Object.entries(out).sort());
  };

  test('re-running the trigger logic for every summary leaves every board unchanged', async () => {
    const before = await snapshot();
    for (let i = 0; i < 2; i++) for (const [uid, day] of fixtures) await processDailySummary(uid, day);
    expect(await snapshot()).toBe(before);
  });

  test('a corrected (lower) summary lowers the boards: values are recomputed, not accumulated', async () => {
    await giveVerifiedSteps('a1', '20260107', 1000);
    const r = await lb('a1', 'CAMPUS', 'WEEKLY');
    expect(rows(r)[0]).toEqual(['i1', 6000, 1]);
    expect(r.me.value).toBe(5000);
    expect(await getDoc('leaderboards/HOSTELS_20260105/entries/agira')).toMatchObject({ totalVerifiedSteps: 8500 });
  });
});

describe('refreshWeeklySteps (scheduled)', () => {
  test('repairs a stale public weekly value and resets everybody at week rollover', async () => {
    await db().collection('publicProfiles').doc('a1').update({ weeklyVerifiedSteps: 1 });
    expect((await runRefreshWeeklySteps()).updated).toBeGreaterThanOrEqual(1);
    expect((await getDoc('publicProfiles/a1'))?.weeklyVerifiedSteps).toBe(12000);
    expect((await getDoc('publicProfiles/i1'))?.weeklyVerifiedSteps).toBe(6000);
    setClock(WED + 7 * DAY);
    await runRefreshWeeklySteps();
    expect((await getDoc('publicProfiles/a1'))?.weeklyVerifiedSteps).toBe(0);
    expect((await getDoc('publicProfiles/i1'))?.weeklyVerifiedSteps).toBe(0);
  });

  test('respects the showWeeklySteps privacy flag', async () => {
    await handleUpdateProfile(authReq('a2', { privacy: { showWeeklySteps: false } }));
    await runRefreshWeeklySteps();
    expect((await getDoc('publicProfiles/a2'))?.weeklyVerifiedSteps).toBeNull();
    expect((await getDoc('publicProfiles/a1'))?.weeklyVerifiedSteps).toBe(12000);
  });
});

describe('daily goal, streak and badges (derived by the same trigger)', () => {
  test('goal reward is paid once per day; streak and best streak recomputed; badges awarded once', async () => {
    // a1 hit 10k? no (8000). Give a2 three goal days in a row ending today.
    for (const d of ['20260105', '20260106', '20260107']) await giveVerifiedSteps('a2', d, 10_500);
    for (let i = 0; i < 3; i++) await processDailySummary('a2', '20260107');
    const u = (await db().collection('users').doc('a2').get()).data();
    expect(u).toMatchObject({ currentStreak: 3, bestStreak: 3, lastGoalDayKey: '20260107' });
    const ledger = (await db().collection('virtualPointsLedger').where('uid', '==', 'a2').get()).docs.map((d) => d.id);
    for (const d of ['20260105', '20260106', '20260107']) expect(ledger.filter((i) => i === `DAILY_GOAL_${d}_a2_REWARD`)).toHaveLength(1);
    expect(await getDoc('achievements/a2_TEN_K_WALKER')).toBeDefined();
    expect(await getDoc('achievements/a2_FIRST_1K')).toBeDefined();
    expect(await getDoc('achievements/a2_STREAK_7')).toBeUndefined();
    // points: 3 x 10 daily goal + FIRST_1K 10 + TEN_K_WALKER 20, exactly once
    expect(u?.pointsBalance).toBe(60);
  });

  test('a 7-day streak pays the streak reward once and awards STREAK_7', async () => {
    for (const d of ['20260101', '20260102', '20260103', '20260104', '20260105', '20260106', '20260107']) await giveVerifiedSteps('v1', d, 10_000);
    await processDailySummary('v1', '20260107');
    const u = (await db().collection('users').doc('v1').get()).data();
    expect(u).toMatchObject({ currentStreak: 7, bestStreak: 7 });
    expect(await getDoc('virtualPointsLedger/STREAK_20260101_v1_REWARD')).toMatchObject({ delta: 50 });
    expect(await getDoc('achievements/v1_STREAK_7')).toBeDefined();
    const before = u?.pointsBalance;
    await processDailySummary('v1', '20260107');
    expect(((await db().collection('users').doc('v1').get()).data())?.pointsBalance).toBe(before);
  });
});
