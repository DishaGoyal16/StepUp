import { DAY_MS, IST_OFFSET_MS, Period } from '../config';

/** Pure IST (UTC+05:30, no DST) calendar helpers. dayKey=YYYYMMDD, weekKey=Monday's dayKey, monthKey=YYYYMM. */

function pad(n: number, w = 2): string {
  return String(n).padStart(w, '0');
}

export function dayKeyOf(ms: number): string {
  const d = new Date(ms + IST_OFFSET_MS);
  return `${pad(d.getUTCFullYear(), 4)}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}`;
}

/** Epoch ms of IST 00:00 on the given dayKey. */
export function dayStartMs(dayKey: string): number {
  const y = Number(dayKey.slice(0, 4));
  const m = Number(dayKey.slice(4, 6));
  const d = Number(dayKey.slice(6, 8));
  return Date.UTC(y, m - 1, d) - IST_OFFSET_MS;
}

export function isValidDayKey(k: unknown): k is string {
  if (typeof k !== 'string' || !/^\d{8}$/.test(k)) return false;
  return dayKeyOf(dayStartMs(k)) === k;
}

export function addDays(dayKey: string, n: number): string {
  return dayKeyOf(dayStartMs(dayKey) + n * DAY_MS + 12 * 3_600_000);
}

/** Number of days from a to b (b - a). */
export function diffDays(a: string, b: string): number {
  return Math.round((dayStartMs(b) - dayStartMs(a)) / DAY_MS);
}

/** ISO weekday: Monday=1 ... Sunday=7, in IST. */
export function isoWeekday(dayKey: string): number {
  const d = new Date(dayStartMs(dayKey) + IST_OFFSET_MS);
  const wd = d.getUTCDay();
  return wd === 0 ? 7 : wd;
}

export function weekKeyOfDay(dayKey: string): string {
  return addDays(dayKey, -(isoWeekday(dayKey) - 1));
}

export function monthKeyOfDay(dayKey: string): string {
  return dayKey.slice(0, 6);
}

export function weekKeyOf(ms: number): string {
  return weekKeyOfDay(dayKeyOf(ms));
}

export function monthKeyOf(ms: number): string {
  return monthKeyOfDay(dayKeyOf(ms));
}

export function daysInMonth(monthKey: string): number {
  const y = Number(monthKey.slice(0, 4));
  const m = Number(monthKey.slice(4, 6));
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

/** Period key for a dayKey: DAILY->dayKey, WEEKLY->Monday dayKey, MONTHLY->YYYYMM, ALL_TIME->'ALL'. */
export function periodKeyForDay(period: Period, dayKey: string): string {
  switch (period) {
    case 'DAILY':
      return dayKey;
    case 'WEEKLY':
      return weekKeyOfDay(dayKey);
    case 'MONTHLY':
      return monthKeyOfDay(dayKey);
    default:
      return 'ALL';
  }
}

export function periodKeyForNow(period: Period, ms: number): string {
  return periodKeyForDay(period, dayKeyOf(ms));
}

/** Inclusive [firstDayKey, lastDayKey] for a period key; ALL_TIME returns null (unbounded). */
export function periodRange(period: Period, periodKey: string): [string, string] | null {
  switch (period) {
    case 'DAILY':
      return [periodKey, periodKey];
    case 'WEEKLY':
      return [periodKey, addDays(periodKey, 6)];
    case 'MONTHLY':
      return [`${periodKey}01`, `${periodKey}${pad(daysInMonth(periodKey))}`];
    default:
      return null;
  }
}

export function dayInRange(dayKey: string, range: [string, string] | null): boolean {
  return range === null || (dayKey >= range[0] && dayKey <= range[1]);
}

/** All dayKeys from a to b inclusive. */
export function enumerateDays(a: string, b: string): string[] {
  const out: string[] = [];
  const n = diffDays(a, b);
  for (let i = 0; i <= n; i++) out.push(addDays(a, i));
  return out;
}

/** Epoch ms of the next IST midnight strictly after `ms`. */
export function nextIstMidnightMs(ms: number): number {
  return dayStartMs(dayKeyOf(ms)) + DAY_MS;
}

export function boardIdFor(scope: 'CAMPUS' | 'HOSTELS', periodKey: string): string {
  return `${scope}_${periodKey}`;
}
