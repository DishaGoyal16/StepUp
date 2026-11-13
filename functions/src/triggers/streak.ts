import { addDays, diffDays } from '../lib/time';

export interface StreakInfo {
  /** Run of consecutive goal days ending today or yesterday (0 if broken). */
  current: number;
  /** First day of the current run (null if current == 0). */
  currentStart: string | null;
  /** Longest run ever in the supplied history. */
  longest: number;
  lastGoalDayKey: string | null;
}

/**
 * Pure streak computation from the set of day keys on which the daily goal was met.
 * The streak stays alive through "today" even if today's goal is not met yet (it breaks only when yesterday is missed).
 */
export function computeStreak(goalDays: Iterable<string>, todayKey: string): StreakInfo {
  const sorted = [...new Set(goalDays)].sort();
  if (sorted.length === 0) return { current: 0, currentStart: null, longest: 0, lastGoalDayKey: null };
  let longest = 0;
  let run = 0;
  let runStart = sorted[0];
  let prev: string | null = null;
  const runs: Array<{ start: string; end: string; len: number }> = [];
  for (const k of sorted) {
    if (prev !== null && diffDays(prev, k) === 1) {
      run++;
    } else {
      if (prev !== null) runs.push({ start: runStart, end: prev, len: run });
      run = 1;
      runStart = k;
    }
    if (run > longest) longest = run;
    prev = k;
  }
  runs.push({ start: runStart, end: prev as string, len: run });
  const last = runs[runs.length - 1];
  const alive = last.end === todayKey || last.end === addDays(todayKey, -1);
  return {
    current: alive ? last.len : 0,
    currentStart: alive ? last.start : null,
    longest,
    lastGoalDayKey: sorted[sorted.length - 1],
  };
}
