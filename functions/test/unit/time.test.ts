import {
  addDays,
  dayInRange,
  dayKeyOf,
  dayStartMs,
  daysInMonth,
  diffDays,
  enumerateDays,
  isoWeekday,
  isValidDayKey,
  monthKeyOf,
  nextIstMidnightMs,
  periodKeyForDay,
  periodRange,
  weekKeyOf,
  weekKeyOfDay,
} from '../../src/lib/time';

// IST = UTC+05:30. IST midnight = 18:30 UTC of the previous day.
const utc = (y: number, m: number, d: number, h = 0, mi = 0, s = 0, ms = 0) => Date.UTC(y, m - 1, d, h, mi, s, ms);

describe('IST day keys', () => {
  test('18:29:59.999 UTC is still the same IST day; 18:30:00 UTC rolls to the next IST day', () => {
    expect(dayKeyOf(utc(2026, 1, 1, 18, 29, 59, 999))).toBe('20260101');
    expect(dayKeyOf(utc(2026, 1, 1, 18, 30, 0, 0))).toBe('20260102');
  });

  test('a UTC date and its IST date differ in the morning IST hours', () => {
    expect(dayKeyOf(utc(2026, 3, 9, 20, 0))).toBe('20260310'); // 01:30 IST on the 10th
    expect(dayKeyOf(utc(2026, 3, 10, 12, 0))).toBe('20260310');
  });

  test('year boundary', () => {
    expect(dayKeyOf(utc(2025, 12, 31, 18, 29, 59, 999))).toBe('20251231');
    expect(dayKeyOf(utc(2025, 12, 31, 18, 30))).toBe('20260101');
  });

  test('dayStartMs inverts dayKeyOf and is IST midnight', () => {
    expect(dayStartMs('20260101')).toBe(utc(2025, 12, 31, 18, 30));
    for (const k of ['20240229', '20261231', '20260301']) expect(dayKeyOf(dayStartMs(k))).toBe(k);
  });

  test('isValidDayKey', () => {
    expect(isValidDayKey('20260230')).toBe(false);
    expect(isValidDayKey('20260228')).toBe(true);
    expect(isValidDayKey('2026-02-28')).toBe(false);
    expect(isValidDayKey(20260228)).toBe(false);
  });

  test('addDays / diffDays across month, year and leap boundaries', () => {
    expect(addDays('20260131', 1)).toBe('20260201');
    expect(addDays('20251231', 1)).toBe('20260101');
    expect(addDays('20240228', 1)).toBe('20240229');
    expect(addDays('20240229', 1)).toBe('20240301');
    expect(addDays('20260301', -1)).toBe('20260228');
    expect(diffDays('20260101', '20260108')).toBe(7);
    expect(enumerateDays('20260227', '20260302')).toEqual(['20260227', '20260228', '20260301', '20260302']);
  });

  test('nextIstMidnightMs is strictly after the instant', () => {
    expect(nextIstMidnightMs(utc(2026, 1, 1, 18, 29, 59, 999))).toBe(utc(2026, 1, 1, 18, 30));
    expect(nextIstMidnightMs(utc(2026, 1, 1, 18, 30))).toBe(utc(2026, 1, 2, 18, 30));
  });
});

describe('ISO weeks (Monday start) in IST', () => {
  test('2026-01-01 is a Thursday; its week starts Monday 2025-12-29', () => {
    expect(isoWeekday('20260101')).toBe(4);
    expect(weekKeyOfDay('20260101')).toBe('20251229');
  });

  test('Sunday belongs to the week that started the previous Monday; Monday starts a new week', () => {
    expect(weekKeyOfDay('20260104')).toBe('20251229'); // Sunday
    expect(weekKeyOfDay('20260105')).toBe('20260105'); // Monday
    expect(isoWeekday('20260104')).toBe(7);
    expect(isoWeekday('20260105')).toBe(1);
  });

  test('week boundary happens at IST midnight, not UTC midnight (Sunday 23:59:59.999 IST vs Monday 00:00 IST)', () => {
    // Monday 2026-01-05 00:00 IST == Sunday 2026-01-04 18:30 UTC
    expect(weekKeyOf(utc(2026, 1, 4, 18, 29, 59, 999))).toBe('20251229');
    expect(weekKeyOf(utc(2026, 1, 4, 18, 30))).toBe('20260105');
  });

  test('week range is 7 days, crossing month and year boundaries', () => {
    expect(periodRange('WEEKLY', '20251229')).toEqual(['20251229', '20260104']);
    expect(periodRange('WEEKLY', '20260126')).toEqual(['20260126', '20260201']);
  });
});

describe('monthly and all-time periods', () => {
  test('month boundary happens at IST midnight', () => {
    expect(monthKeyOf(utc(2026, 1, 31, 18, 29, 59, 999))).toBe('202601');
    expect(monthKeyOf(utc(2026, 1, 31, 18, 30))).toBe('202602');
  });

  test('days in month incl. leap years', () => {
    expect(daysInMonth('202602')).toBe(28);
    expect(daysInMonth('202402')).toBe(29);
    expect(daysInMonth('202604')).toBe(30);
    expect(daysInMonth('202612')).toBe(31);
  });

  test('periodRange / periodKeyForDay / dayInRange', () => {
    expect(periodRange('MONTHLY', '202402')).toEqual(['20240201', '20240229']);
    expect(periodRange('DAILY', '20260310')).toEqual(['20260310', '20260310']);
    expect(periodRange('ALL_TIME', 'ALL')).toBeNull();
    expect(periodKeyForDay('DAILY', '20260310')).toBe('20260310');
    expect(periodKeyForDay('WEEKLY', '20260310')).toBe('20260309');
    expect(periodKeyForDay('MONTHLY', '20260310')).toBe('202603');
    expect(periodKeyForDay('ALL_TIME', '20260310')).toBe('ALL');
    expect(dayInRange('20260315', periodRange('MONTHLY', '202603'))).toBe(true);
    expect(dayInRange('20260401', periodRange('MONTHLY', '202603'))).toBe(false);
    expect(dayInRange('19990101', null)).toBe(true);
  });
});
