import { COL, Period, PERIODS } from '../config';
import { nowMs } from '../lib/clock';
import { db, FieldValue } from '../lib/firebase';
import {
  boardIdFor,
  dayInRange,
  dayKeyOf,
  periodKeyForDay,
  periodRange,
} from '../lib/time';
import { loadUserDays } from '../steps/summaries';

// ---------------------------------------------------------------------------------------------------------------
// Pure logic
// ---------------------------------------------------------------------------------------------------------------

/** Sum of verified steps in a period (ALL_TIME = every day). Pure. */
export function periodTotal(days: ReadonlyMap<string, number>, period: Period, periodKey: string): number {
  const range = periodRange(period, periodKey);
  let total = 0;
  for (const [k, v] of days) if (dayInRange(k, range)) total += v;
  return total;
}

export interface HostelEntryInput {
  hostelId: string;
  verifiedSteps: number;
  /** false for suspended / deleted accounts: excluded from hostel aggregates. */
  countsForHostel?: boolean;
}

export interface HostelAggregate {
  hostelId: string;
  totalVerifiedSteps: number;
  participants: number;
  averagePerParticipant: number;
}

/** Hostel metric: total AND average per participant (participant = >= 1 verified step in the period). */
export function aggregateHostel(hostelId: string, entries: readonly HostelEntryInput[]): HostelAggregate {
  let total = 0;
  let participants = 0;
  for (const e of entries) {
    if (e.hostelId !== hostelId || e.countsForHostel === false) continue;
    total += e.verifiedSteps;
    if (e.verifiedSteps >= 1) participants++;
  }
  const average = participants === 0 ? 0 : Math.round((total / participants) * 100) / 100;
  return { hostelId, totalVerifiedSteps: total, participants, averagePerParticipant: average };
}

/** Standard competition ranking (ties share a rank). Pure. */
export function rankDescending<T>(items: readonly T[], value: (t: T) => number): Array<T & { rank: number; value: number }> {
  const sorted = [...items].sort((a, b) => value(b) - value(a));
  const out: Array<T & { rank: number; value: number }> = [];
  let prev: number | null = null;
  let rank = 0;
  sorted.forEach((it, i) => {
    const v = value(it);
    if (prev === null || v !== prev) rank = i + 1;
    prev = v;
    out.push({ ...it, rank, value: v });
  });
  return out;
}

export function periodKeysTouchedBy(dayKey: string): Array<{ period: Period; periodKey: string }> {
  return PERIODS.map((p) => ({ period: p, periodKey: periodKeyForDay(p, dayKey) }));
}

// ---------------------------------------------------------------------------------------------------------------
// Firestore maintenance (idempotent recomputation; never blind increments)
// ---------------------------------------------------------------------------------------------------------------

const METRIC_LABEL_STUDENT = 'Verified steps';

export function boardDocId(scope: 'CAMPUS' | 'HOSTELS', periodKey: string): string {
  return boardIdFor(scope, periodKey);
}

async function ensureBoard(scope: 'CAMPUS' | 'HOSTELS', period: Period, periodKey: string): Promise<void> {
  await db()
    .collection(COL.leaderboards)
    .doc(boardDocId(scope, periodKey))
    .set(
      {
        scope,
        period,
        periodKey,
        metricLabel: scope === 'CAMPUS' ? METRIC_LABEL_STUDENT : 'Verified steps (total and average per participant)',
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
}

export interface RefreshOptions {
  /** Hostel the user belonged to before a hostel change (its aggregates are recomputed too). */
  previousHostelId?: string | null;
}

/**
 * Recompute one user's entries and the affected hostel aggregates.
 * `touchedDayKey` = day whose summary changed (affects DAILY/WEEKLY/MONTHLY/ALL_TIME of that day).
 * Without it (profile edits) the CURRENT daily/weekly/monthly/all-time boards are refreshed.
 */
export async function refreshUserBoards(
  uid: string,
  opts: RefreshOptions & { touchedDayKey?: string; days?: Map<string, number> } = {},
): Promise<void> {
  const firestore = db();
  const userSnap = await firestore.collection(COL.users).doc(uid).get();
  if (!userSnap.exists) return;
  const user = userSnap.data() as FirebaseFirestore.DocumentData;
  const days = opts.days ?? (await loadUserDays(uid));
  const dayKey = opts.touchedDayKey ?? dayKeyOf(nowMs());
  const privacy = (user.privacy ?? {}) as Record<string, boolean>;
  const active = user.status === 'ACTIVE';
  const visible = active && privacy.showOnLeaderboards !== false;
  const hostelId = (user.hostelId as string | null) ?? null;

  for (const { period, periodKey } of periodKeysTouchedBy(dayKey)) {
    const value = periodTotal(days, period, periodKey);
    await ensureBoard('CAMPUS', period, periodKey);
    await firestore
      .collection(COL.leaderboards)
      .doc(boardDocId('CAMPUS', periodKey))
      .collection(COL.entries)
      .doc(uid)
      .set({
        uid,
        displayName: visible ? user.displayName : 'Student',
        photoUrl: visible ? (user.photoUrl ?? null) : null,
        hostelId,
        verifiedSteps: value,
        showOnLeaderboards: visible,
        showHostel: privacy.showHostel !== false,
        countsForHostel: active,
        updatedAt: FieldValue.serverTimestamp(),
      });
    await ensureBoard('HOSTELS', period, periodKey);
    const hostels = new Set<string>();
    if (hostelId) hostels.add(hostelId);
    if (opts.previousHostelId) hostels.add(opts.previousHostelId);
    for (const h of hostels) await recomputeHostelEntry(periodKey, h);
  }
}

/** Recompute `leaderboards/HOSTELS_{periodKey}/entries/{hostelId}` from the campus entries, atomically. */
export async function recomputeHostelEntry(periodKey: string, hostelId: string): Promise<HostelAggregate> {
  const firestore = db();
  const campusEntries = firestore
    .collection(COL.leaderboards)
    .doc(boardDocId('CAMPUS', periodKey))
    .collection(COL.entries)
    .where('hostelId', '==', hostelId);
  const hostelRef = firestore.collection(COL.hostels).doc(hostelId);
  const outRef = firestore
    .collection(COL.leaderboards)
    .doc(boardDocId('HOSTELS', periodKey))
    .collection(COL.entries)
    .doc(hostelId);
  return firestore.runTransaction(async (tx) => {
    const [q, h] = await Promise.all([tx.get(campusEntries), tx.get(hostelRef)]);
    const agg = aggregateHostel(
      hostelId,
      q.docs.map((d) => ({
        hostelId,
        verifiedSteps: Number(d.data().verifiedSteps ?? 0),
        countsForHostel: d.data().countsForHostel !== false,
      })),
    );
    tx.set(outRef, {
      displayName: (h.data()?.displayName as string | undefined) ?? hostelId,
      ...agg,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return agg;
  });
}
