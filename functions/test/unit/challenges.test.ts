import { computeProgress, decideResult, metricLabel, ParticipantRow, rankParticipants, rollingWindow } from '../../src/challenges/progress';

const days = (o: Record<string, number>) => new Map(Object.entries(o));

describe('challenge progress metrics', () => {
  const d = days({
    '20260101': 4000,
    '20260102': 5000,
    '20260103': 6000,
    '20260104': 2000,
    '20260105': 5000,
    '20260106': 5001,
    '20260107': 9000,
  });

  test('TOTAL_STEPS sums only days inside the window (inclusive bounds)', () => {
    expect(computeProgress('TOTAL_STEPS', null, d, '20260102', '20260104')).toBe(13_000);
    expect(computeProgress('TOTAL_STEPS', null, d, '20260101', '20260107')).toBe(36_001);
    expect(computeProgress('TOTAL_STEPS', null, d, '20260108', '20260110')).toBe(0);
  });

  test('DAILY_TARGET_DAYS counts days with verified >= dailyTarget (>=, not >)', () => {
    expect(computeProgress('DAILY_TARGET_DAYS', 5000, d, '20260101', '20260107')).toBe(5); // 02,03,05,06,07
    expect(computeProgress('DAILY_TARGET_DAYS', 5001, d, '20260101', '20260107')).toBe(3); // 03,06,07
    expect(computeProgress('DAILY_TARGET_DAYS', 5000, d, '20260104', '20260105')).toBe(1);
  });

  test('STREAK_DAYS is the longest run of consecutive goal days inside the window', () => {
    expect(computeProgress('STREAK_DAYS', 5000, d, '20260101', '20260107')).toBe(3); // run 02-03 (day 04 breaks it) = 2, run 05-06-07 = 3
  });

  test('STREAK_DAYS example with a real run', () => {
    const s = days({ '20260101': 5000, '20260102': 5000, '20260103': 100, '20260104': 5000, '20260105': 5000, '20260106': 5000 });
    expect(computeProgress('STREAK_DAYS', 5000, s, '20260101', '20260106')).toBe(3);
    // window truncation shortens the streak
    expect(computeProgress('STREAK_DAYS', 5000, s, '20260101', '20260105')).toBe(2);
  });

  test('a missing day (no summary) breaks a streak; an unmet goal day does too', () => {
    const s = days({ '20260101': 6000, '20260103': 6000, '20260104': 6000 });
    expect(computeProgress('STREAK_DAYS', 5000, s, '20260101', '20260104')).toBe(2);
  });

  test('day-based metric with no dailyTarget never counts', () => {
    expect(computeProgress('DAILY_TARGET_DAYS', null, d, '20260101', '20260107')).toBe(0);
    expect(computeProgress('STREAK_DAYS', 0, d, '20260101', '20260107')).toBe(0);
  });

  test('rolling window length', () => {
    expect(rollingWindow('20260105', 1)).toEqual(['20260105', '20260105']);
    expect(rollingWindow('20260105', 7)).toEqual(['20260105', '20260111']);
    expect(rollingWindow('20260130', 3)).toEqual(['20260130', '20260201']);
  });
});

describe('ranking and winner decision', () => {
  const row = (uid: string, progress: number, at = 0, hostelId: string | null = null): ParticipantRow => ({ uid, name: uid, hostelId, progress, progressUpdatedAtMs: at });
  const names = new Map([
    ['agira', 'Agira Hall'],
    ['ira', 'Ira Hall'],
    ['vyom', 'Vyom Hall'],
  ]);

  test('ties share a rank; earlier progress timestamp then uid order the list', () => {
    const r = rankParticipants([row('c', 10, 5), row('a', 10, 1), row('b', 20, 9), row('d', 5, 0)]);
    expect(r.map((x) => [x.uid, x.rank])).toEqual([
      ['b', 1],
      ['a', 2],
      ['c', 2],
      ['d', 4],
    ]);
  });

  test('BUDDY: higher progress wins only if the target was reached', () => {
    const win = decideResult({ type: 'BUDDY', target: 1000, aggregation: 'TOTAL', participants: [row('a', 1500, 5), row('b', 1200, 3)], hostelNames: names });
    expect(win.winnerUid).toBe('a');
    const none = decideResult({ type: 'BUDDY', target: 5000, aggregation: 'TOTAL', participants: [row('a', 1500), row('b', 1200)], hostelNames: names });
    expect(none.winnerUid).toBeNull();
    const zero = decideResult({ type: 'BUDDY', target: 0, aggregation: 'TOTAL', participants: [row('a', 0), row('b', 0)], hostelNames: names });
    expect(zero.winnerUid).toBeNull();
  });

  test('BUDDY tie on progress: the participant who got there first wins (deterministic, single winner)', () => {
    const r = decideResult({ type: 'BUDDY', target: 1000, aggregation: 'TOTAL', participants: [row('a', 2000, 50), row('b', 2000, 10)], hostelNames: names });
    expect(r.winnerUid).toBe('b');
    expect(r.ranking.map((x) => x.rank)).toEqual([1, 1]);
  });

  test('CAMPUS: top progress > 0 wins; nobody walking => no winner', () => {
    expect(decideResult({ type: 'CAMPUS', target: 1, aggregation: 'TOTAL', participants: [row('a', 10), row('b', 30)], hostelNames: names }).winnerUid).toBe('b');
    expect(decideResult({ type: 'CAMPUS', target: 1, aggregation: 'TOTAL', participants: [row('a', 0)], hostelNames: names }).winnerUid).toBeNull();
  });

  test('INTER_HOSTEL by average per participant can differ from the winner by total', () => {
    // agira: 3 participants, total 9000, avg 3000.  ira: 1 participant, total 5000, avg 5000.
    const parts = [row('a1', 4000, 0, 'agira'), row('a2', 3000, 0, 'agira'), row('a3', 2000, 0, 'agira'), row('i1', 5000, 0, 'ira')];
    const avg = decideResult({ type: 'INTER_HOSTEL', target: 1, aggregation: 'AVERAGE_PER_PARTICIPANT', participants: parts, hostelNames: names, hostelIds: ['agira', 'ira', 'vyom'] });
    expect(avg.winnerHostelId).toBe('ira');
    expect(avg.ranking.map((r) => [r.hostelId, r.value])).toEqual([
      ['ira', 5000],
      ['agira', 3000],
      ['vyom', 0],
    ]);
    const tot = decideResult({ type: 'INTER_HOSTEL', target: 1, aggregation: 'TOTAL', participants: parts, hostelNames: names, hostelIds: ['agira', 'ira'] });
    expect(tot.winnerHostelId).toBe('agira');
    expect(tot.winnerUid).toBeNull();
  });

  test('INTER_HOSTEL only ranks the competing hostels', () => {
    const parts = [row('x', 99999, 0, 'vyom'), row('a1', 100, 0, 'agira')];
    const r = decideResult({ type: 'INTER_HOSTEL', target: 1, aggregation: 'TOTAL', participants: parts, hostelNames: names, hostelIds: ['agira', 'ira'] });
    expect(r.ranking.map((x) => x.hostelId)).toEqual(['agira', 'ira']);
  });

  test('INDIVIDUAL never has a winner', () => {
    const r = decideResult({ type: 'INDIVIDUAL', target: 1, aggregation: 'TOTAL', participants: [row('a', 10)], hostelNames: names });
    expect(r.winnerUid).toBeNull();
    expect(r.winnerHostelId).toBeNull();
  });

  test('ranking is capped at the top 50', () => {
    const parts = Array.from({ length: 80 }, (_, i) => row(`u${String(i).padStart(2, '0')}`, i + 1));
    expect(decideResult({ type: 'CAMPUS', target: 1, aggregation: 'TOTAL', participants: parts, hostelNames: names }).ranking).toHaveLength(50);
  });

  test('metric labels are explicit about hostel aggregation', () => {
    expect(metricLabel('TOTAL_STEPS', null)).toBe('Verified steps');
    expect(metricLabel('TOTAL_STEPS', null, 'AVERAGE_PER_PARTICIPANT')).toContain('average per participant');
    expect(metricLabel('TOTAL_STEPS', null, 'TOTAL')).toContain('hostel total');
    expect(metricLabel('DAILY_TARGET_DAYS', 7000)).toContain('7000');
  });
});
