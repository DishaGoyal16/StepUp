import { aggregateHostel } from '../leaderboards/aggregate';
import { addDays, diffDays } from '../lib/time';

/** Pure challenge logic: progress metrics, windows, ranking and winner decision. */

export type Metric = 'TOTAL_STEPS' | 'DAILY_TARGET_DAYS' | 'STREAK_DAYS';
export type ChallengeType = 'INDIVIDUAL' | 'BUDDY' | 'INTER_HOSTEL' | 'CAMPUS';

/**
 * Progress inside the inclusive day window [startKey, endKey]:
 *  - TOTAL_STEPS: sum of verified steps in the window
 *  - DAILY_TARGET_DAYS: number of days with verified >= dailyTarget
 *  - STREAK_DAYS: longest run of consecutive days with verified >= dailyTarget
 */
export function computeProgress(
  metric: Metric,
  dailyTarget: number | null,
  days: ReadonlyMap<string, number>,
  startKey: string,
  endKey: string,
): number {
  const inWindow: Array<[string, number]> = [];
  for (const [k, v] of days) if (k >= startKey && k <= endKey) inWindow.push([k, v]);
  if (metric === 'TOTAL_STEPS') return inWindow.reduce((s, [, v]) => s + v, 0);
  const goal = dailyTarget && dailyTarget > 0 ? dailyTarget : Number.POSITIVE_INFINITY;
  const hit = inWindow.filter(([, v]) => v >= goal).map(([k]) => k).sort();
  if (metric === 'DAILY_TARGET_DAYS') return hit.length;
  let best = 0;
  let run = 0;
  let prev: string | null = null;
  for (const k of hit) {
    run = prev !== null && diffDays(prev, k) === 1 ? run + 1 : 1;
    if (run > best) best = run;
    prev = k;
  }
  return best;
}

export function rollingWindow(joinDayKey: string, durationDays: number): [string, string] {
  return [joinDayKey, addDays(joinDayKey, durationDays - 1)];
}

export interface ParticipantRow {
  uid: string;
  name: string;
  hostelId: string | null;
  progress: number;
  /** When the progress last changed (ms); earlier wins ties. */
  progressUpdatedAtMs: number;
}

export interface RankedRow {
  rank: number;
  uid?: string;
  hostelId?: string;
  name: string;
  value: number;
}

export function rankParticipants(rows: readonly ParticipantRow[]): Array<ParticipantRow & { rank: number }> {
  const sorted = [...rows].sort(
    (a, b) => b.progress - a.progress || a.progressUpdatedAtMs - b.progressUpdatedAtMs || a.uid.localeCompare(b.uid),
  );
  let rank = 0;
  return sorted.map((r, i) => {
    if (i === 0 || sorted[i - 1].progress !== r.progress) rank = i + 1;
    return { ...r, rank };
  });
}

export interface HostelRow {
  hostelId: string;
  name: string;
  value: number;
  total: number;
  participants: number;
}

export function rankHostels(
  rows: readonly ParticipantRow[],
  hostelNames: ReadonlyMap<string, string>,
  aggregation: 'AVERAGE_PER_PARTICIPANT' | 'TOTAL',
  onlyHostels?: readonly string[],
): HostelRow[] {
  const ids = new Set<string>(onlyHostels ?? []);
  for (const r of rows) if (r.hostelId && (!onlyHostels || onlyHostels.includes(r.hostelId))) ids.add(r.hostelId);
  const entries = rows.filter((r) => r.hostelId).map((r) => ({ hostelId: r.hostelId as string, verifiedSteps: r.progress }));
  const out: HostelRow[] = [...ids].map((h) => {
    const a = aggregateHostel(h, entries);
    return {
      hostelId: h,
      name: hostelNames.get(h) ?? h,
      value: aggregation === 'TOTAL' ? a.totalVerifiedSteps : a.averagePerParticipant,
      total: a.totalVerifiedSteps,
      participants: a.participants,
    };
  });
  out.sort((a, b) => b.value - a.value || b.total - a.total || a.hostelId.localeCompare(b.hostelId));
  return out;
}

export interface ResultInput {
  type: ChallengeType;
  target: number;
  aggregation: 'AVERAGE_PER_PARTICIPANT' | 'TOTAL';
  participants: readonly ParticipantRow[];
  hostelNames: ReadonlyMap<string, string>;
  hostelIds?: readonly string[];
}

export interface ResultDecision {
  ranking: RankedRow[];
  winnerUid: string | null;
  winnerHostelId: string | null;
}

/**
 * Winner rules:
 *  - BUDDY: highest progress wins but must have reached `target` (else no winner); ties broken by who got there first.
 *  - CAMPUS: highest progress with progress > 0.
 *  - INTER_HOSTEL: top hostel by the configured aggregation (average per participant or total), value > 0.
 *  - INDIVIDUAL: no winner (completion is rewarded when reached).
 */
export function decideResult(inp: ResultInput): ResultDecision {
  if (inp.type === 'INTER_HOSTEL') {
    const hostels = rankHostels(inp.participants, inp.hostelNames, inp.aggregation, inp.hostelIds);
    let rank = 0;
    const ranking: RankedRow[] = hostels.slice(0, 50).map((h, i) => {
      if (i === 0 || hostels[i - 1].value !== h.value) rank = i + 1;
      return { rank, hostelId: h.hostelId, name: h.name, value: h.value };
    });
    const top = hostels[0];
    return { ranking, winnerUid: null, winnerHostelId: top && top.value > 0 ? top.hostelId : null };
  }
  const ranked = rankParticipants(inp.participants);
  const ranking: RankedRow[] = ranked.slice(0, 50).map((r) => ({ rank: r.rank, uid: r.uid, name: r.name, value: r.progress }));
  const top = ranked[0];
  let winnerUid: string | null = null;
  if (top && inp.type === 'BUDDY' && top.progress >= inp.target && top.progress > 0) winnerUid = top.uid;
  if (top && inp.type === 'CAMPUS' && top.progress > 0) winnerUid = top.uid;
  return { ranking, winnerUid, winnerHostelId: null };
}

export function metricLabel(metric: Metric, dailyTarget: number | null, hostelAggregation?: 'AVERAGE_PER_PARTICIPANT' | 'TOTAL'): string {
  const base =
    metric === 'TOTAL_STEPS'
      ? 'Verified steps'
      : metric === 'DAILY_TARGET_DAYS'
        ? `Days with at least ${dailyTarget ?? 0} verified steps`
        : `Longest streak of days with at least ${dailyTarget ?? 0} verified steps`;
  if (hostelAggregation === 'AVERAGE_PER_PARTICIPANT') return `${base} (average per participant)`;
  if (hostelAggregation === 'TOTAL') return `${base} (hostel total)`;
  return base;
}
