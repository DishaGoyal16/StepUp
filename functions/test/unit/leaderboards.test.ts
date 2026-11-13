import { aggregateHostel, periodKeysTouchedBy, periodTotal, rankDescending } from '../../src/leaderboards/aggregate';
import { computeStreak } from '../../src/triggers/streak';
import { mergeSettings } from '../../src/lib/settings';
import { DEFAULT_SETTINGS } from '../../src/config';
import { notificationId } from '../../src/notifications/notify';
import { reminderDedupeKey } from '../../src/challenges/reminders';
import { HOSTEL_SEED } from '../../src/seed/hostels';
import { INDIVIDUAL_TEMPLATES } from '../../src/seed/challenges';
import { BADGE_CATALOGUE } from '../../src/seed/badges';

const m = (o: Record<string, number>) => new Map(Object.entries(o));

describe('period totals (Asia/Kolkata keys)', () => {
  // Week of Monday 2026-01-05, and the previous week.
  const days = m({
    '20251231': 1000,
    '20260101': 2000,
    '20260104': 3000, // Sunday - belongs to the week starting 20251229
    '20260105': 4000, // Monday - new week
    '20260106': 5000,
    '20260201': 700,
  });

  test('DAILY', () => expect(periodTotal(days, 'DAILY', '20260105')).toBe(4000));
  test('WEEKLY: Sunday and Monday fall in different weeks', () => {
    expect(periodTotal(days, 'WEEKLY', '20251229')).toBe(1000 + 2000 + 3000);
    expect(periodTotal(days, 'WEEKLY', '20260105')).toBe(9000);
  });
  test('MONTHLY: 202601 excludes December and February', () => {
    expect(periodTotal(days, 'MONTHLY', '202601')).toBe(2000 + 3000 + 4000 + 5000);
    expect(periodTotal(days, 'MONTHLY', '202512')).toBe(1000);
    expect(periodTotal(days, 'MONTHLY', '202602')).toBe(700);
  });
  test('ALL_TIME sums everything', () => expect(periodTotal(days, 'ALL_TIME', 'ALL')).toBe(15_700));
  test('keys touched by a day', () => {
    expect(periodKeysTouchedBy('20260104')).toEqual([
      { period: 'DAILY', periodKey: '20260104' },
      { period: 'WEEKLY', periodKey: '20251229' },
      { period: 'MONTHLY', periodKey: '202601' },
      { period: 'ALL_TIME', periodKey: 'ALL' },
    ]);
  });
});

describe('hostel aggregation: total AND average per participant', () => {
  const entries = [
    { hostelId: 'agira', verifiedSteps: 6000 },
    { hostelId: 'agira', verifiedSteps: 3000 },
    { hostelId: 'agira', verifiedSteps: 0 }, // not a participant (needs >= 1 verified step)
    { hostelId: 'ira', verifiedSteps: 5000 },
    { hostelId: 'agira', verifiedSteps: 9999, countsForHostel: false }, // suspended: excluded
  ];

  test('total, participants and average', () => {
    expect(aggregateHostel('agira', entries)).toEqual({ hostelId: 'agira', totalVerifiedSteps: 9000, participants: 2, averagePerParticipant: 4500 });
    expect(aggregateHostel('ira', entries)).toEqual({ hostelId: 'ira', totalVerifiedSteps: 5000, participants: 1, averagePerParticipant: 5000 });
  });

  test('a hostel with nobody has average 0 (no division by zero)', () => {
    expect(aggregateHostel('vyom', entries)).toEqual({ hostelId: 'vyom', totalVerifiedSteps: 0, participants: 0, averagePerParticipant: 0 });
  });

  test('average is rounded to 2 decimals', () => {
    const r = aggregateHostel('h', [
      { hostelId: 'h', verifiedSteps: 1 },
      { hostelId: 'h', verifiedSteps: 1 },
      { hostelId: 'h', verifiedSteps: 2 },
    ]);
    expect(r.averagePerParticipant).toBe(1.33);
  });

  test('average and total can rank hostels differently', () => {
    const big = aggregateHostel('big', Array.from({ length: 10 }, () => ({ hostelId: 'big', verifiedSteps: 1000 })));
    const small = aggregateHostel('small', [{ hostelId: 'small', verifiedSteps: 4000 }]);
    expect(big.totalVerifiedSteps).toBeGreaterThan(small.totalVerifiedSteps);
    expect(small.averagePerParticipant).toBeGreaterThan(big.averagePerParticipant);
  });
});

describe('rankDescending', () => {
  test('competition ranking with ties', () => {
    const r = rankDescending([{ n: 'a', v: 5 }, { n: 'b', v: 9 }, { n: 'c', v: 9 }, { n: 'd', v: 1 }], (x) => x.v);
    expect(r.map((x) => [x.n, x.rank])).toEqual([
      ['b', 1],
      ['c', 1],
      ['a', 3],
      ['d', 4],
    ]);
  });
});

describe('streak computation', () => {
  test('current streak survives an unmet today, breaks when yesterday is missed', () => {
    const goal = ['20260101', '20260102', '20260103'];
    expect(computeStreak(goal, '20260103').current).toBe(3);
    expect(computeStreak(goal, '20260104').current).toBe(3); // today not met yet - still alive
    expect(computeStreak(goal, '20260105').current).toBe(0); // missed 04
    expect(computeStreak(goal, '20260105').longest).toBe(3);
  });
  test('run start and longest across gaps; duplicates ignored', () => {
    const s = computeStreak(['20260101', '20260101', '20260102', '20260105', '20260106', '20260107'], '20260107');
    expect(s).toEqual({ current: 3, currentStart: '20260105', longest: 3, lastGoalDayKey: '20260107' });
  });
  test('empty history', () => {
    expect(computeStreak([], '20260101')).toEqual({ current: 0, currentStart: null, longest: 0, lastGoalDayKey: null });
  });
  test('streak across month/year boundary', () => {
    expect(computeStreak(['20251230', '20251231', '20260101'], '20260101').current).toBe(3);
  });
});

describe('notification dedupe keys', () => {
  test('doc id is {uid}_{dedupeKey}: identical keys collide (=> no repeat), different days do not', () => {
    expect(notificationId('u1', reminderDedupeKey('c1', '20260105'))).toBe('u1_reminder_c1_20260105');
    expect(notificationId('u1', reminderDedupeKey('c1', '20260105'))).toBe(notificationId('u1', reminderDedupeKey('c1', '20260105')));
    expect(notificationId('u1', reminderDedupeKey('c1', '20260106'))).not.toBe(notificationId('u1', reminderDedupeKey('c1', '20260105')));
    expect(notificationId('u2', reminderDedupeKey('c1', '20260105'))).not.toBe(notificationId('u1', reminderDedupeKey('c1', '20260105')));
    expect(notificationId('u1', reminderDedupeKey('c2', '20260105'))).not.toBe(notificationId('u1', reminderDedupeKey('c1', '20260105')));
  });
});

describe('settings merge and seed data', () => {
  test('missing/invalid stored settings fall back to schema defaults', () => {
    expect(mergeSettings(undefined)).toEqual(DEFAULT_SETTINGS);
    const s = mergeSettings({ betMaxStake: 500, pointsDailyGoal: 'x', bogus: 1 });
    expect(s.betMaxStake).toBe(500);
    expect(s.pointsDailyGoal).toBe(DEFAULT_SETTINGS.pointsDailyGoal);
    expect((s as unknown as Record<string, unknown>).bogus).toBeUndefined();
  });

  test('schema defaults match DATABASE_SCHEMA.md', () => {
    expect(DEFAULT_SETTINGS).toMatchObject({
      timezone: 'Asia/Kolkata',
      maxStepsPerBucket: 35,
      maxStepsPer30Min: 6300,
      maxRewardStepsPerDay: 20000,
      maxBucketAgeHours: 72,
      futureToleranceSec: 120,
      settlementGraceHours: 6,
      pointsDailyGoal: 10,
      pointsStreak7: 50,
      pointsChallengeComplete: 50,
      pointsChallengeWin: 100,
      betMinStake: 10,
      betMaxStake: 1000,
      betExpiryHours: 48,
    });
  });

  test('hostel seed: 18 hostels, Vasudha blocks kept separate, girls/general split', () => {
    expect(HOSTEL_SEED).toHaveLength(18);
    const ids = HOSTEL_SEED.map((h) => h.hostelId);
    expect(new Set(ids).size).toBe(18);
    expect(HOSTEL_SEED.find((h) => h.hostelId === 'vasudha-e')).toMatchObject({ block: 'E', legacyName: 'Hostel-E', category: 'GIRLS' });
    expect(HOSTEL_SEED.find((h) => h.hostelId === 'vasudha-g')).toMatchObject({ block: 'G', legacyName: 'Hostel-G', category: 'GIRLS' });
    expect(HOSTEL_SEED.filter((h) => h.category === 'GENERAL')).toHaveLength(11);
    expect(HOSTEL_SEED.filter((h) => h.category === 'GIRLS')).toHaveLength(7);
    expect(HOSTEL_SEED.find((h) => h.hostelId === 'pavani')).toMatchObject({ displayName: 'Hostel-Pavani Hall', legacyName: 'PG-2' });
    expect(HOSTEL_SEED.find((h) => h.hostelId === 'frf-g')).toMatchObject({ displayName: 'Hostel-FRF/G', legacyName: null });
  });

  test('six individual challenge templates and the six badges', () => {
    expect(INDIVIDUAL_TEMPLATES.map((t) => t.title)).toEqual([
      '5,000 Steps Daily',
      '10,000 Steps Daily',
      '50,000 Steps Weekly',
      '100,000 Steps Weekly',
      '7-Day Walking Streak',
      '30-Day Fitness Challenge',
    ]);
    expect(Object.keys(BADGE_CATALOGUE).sort()).toEqual(['CAMPUS_FITNESS_STAR', 'CHALLENGE_CHAMPION', 'FIRST_1K', 'HOSTEL_CHAMPION', 'STREAK_7', 'TEN_K_WALKER']);
  });
});
