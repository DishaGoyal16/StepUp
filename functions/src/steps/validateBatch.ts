/**
 * Server-side re-validation of step buckets (L7). PURE: no Firebase imports, trivially unit-testable.
 *
 * Faithful port of the Kotlin reference `BucketVerifier.kt` (v2 architecture L4) plus the hard limits from
 * `validateBatch.ts` in StepUp_AntiFraud_Architecture_v2.md section 8.3:
 *   - 35 steps per 10 s bucket, 6,300 per rolling 30 min, 20,000 reward steps per day,
 *     bucket age <= 72 h, future tolerance 120 s, startMs a multiple of 10,000.
 *   - serverCredited = min(clientCredited, recomputed): the server may only DOWNGRADE, never raise a claim.
 *
 * Honest limit: the server cannot re-observe the sensor stream. A rooted/instrumented device can fabricate the hop
 * evidence it sends; this validator bounds the damage (physical + daily caps) but does not prove genuineness.
 */

import { dayKeyOf } from '../lib/time';

export type HopLabel = 'WALK' | 'RUN' | 'SHAKE' | 'VEHICLE' | 'STILL' | 'UNKNOWN';
export type BucketState = 'VERIFIED' | 'PARTIAL' | 'REJECTED' | 'UNWITNESSED';

export const HOP_LABELS: readonly HopLabel[] = ['WALK', 'RUN', 'SHAKE', 'VEHICLE', 'STILL', 'UNKNOWN'];
export const BUCKET_STATES: readonly BucketState[] = ['VERIFIED', 'PARTIAL', 'REJECTED', 'UNWITNESSED'];

export interface Hop {
  label: HopLabel;
  imuSteps: number;
}

export interface VerifierConfig {
  bucketMs: number;
  hopMs: number;
  minCoverage: number;
  minWalkFraction: number;
  imuSlack: number;
  maxStepsPerBucket: number;
}

export const DEFAULT_VERIFIER: VerifierConfig = {
  bucketMs: 10_000,
  hopMs: 2_000,
  minCoverage: 0.8,
  minWalkFraction: 0.5,
  imuSlack: 1.15,
  maxStepsPerBucket: 35,
};

export interface Verdict {
  rawDelta: number;
  credited: number;
  status: BucketState;
  reason: string | null;
}

/**
 * Port of BucketVerifier.verify(). `hops` are the (at most 5) hops of this bucket. Returns null when the bucket has
 * no counter steps (rawDelta == 0), exactly like the Kotlin reference.
 */
export function verifyBucket(
  rawDelta: number,
  hops: readonly Hop[],
  arSaysVehicle = false,
  cfg: VerifierConfig = DEFAULT_VERIFIER,
): Verdict | null {
  const raw = rawDelta;
  if (raw === 0) return null;
  if (raw > cfg.maxStepsPerBucket) return rejected(raw, 'CADENCE_EXCEEDED');

  const expectedHops = Math.trunc(cfg.bucketMs / cfg.hopMs);
  if (hops.length / expectedHops < cfg.minCoverage) {
    return { rawDelta: raw, credited: 0, status: 'UNWITNESSED', reason: 'NO_IMU_EVIDENCE' };
  }
  if (arSaysVehicle) return rejected(raw, 'IN_VEHICLE');

  const gait = hops.filter((h) => h.label === 'WALK' || h.label === 'RUN');
  const walkFraction = gait.length / hops.length;
  if (walkFraction < cfg.minWalkFraction) {
    // Kotlin: groupingBy{label}.eachCount().maxByOrNull{value} - the FIRST label (in encounter order) wins ties.
    const counts = new Map<HopLabel, number>();
    for (const h of hops) {
      if (h.label !== 'WALK' && h.label !== 'RUN') counts.set(h.label, (counts.get(h.label) ?? 0) + 1);
    }
    let dominant: HopLabel | null = null;
    let best = -1;
    for (const [label, n] of counts) {
      if (n > best) {
        best = n;
        dominant = label;
      }
    }
    const reason =
      dominant === 'SHAKE'
        ? 'SHAKE_PATTERN'
        : dominant === 'STILL'
          ? 'NO_MOTION_EVIDENCE'
          : dominant === 'VEHICLE'
            ? 'VEHICLE_MOTION'
            : 'NOT_GAIT';
    return rejected(raw, reason);
  }

  // Credit can never exceed what the IMU independently counted as gait (plus slack).
  let imuSum = 0;
  for (const h of gait) imuSum += h.imuSteps;
  const allowed = Math.floor(cfg.imuSlack * imuSum);
  const credited = Math.min(raw, allowed);
  if (credited === raw) return { rawDelta: raw, credited, status: 'VERIFIED', reason: null };
  if (credited > 0) return { rawDelta: raw, credited, status: 'PARTIAL', reason: 'EXCESS_OVER_IMU' };
  return rejected(raw, 'NO_GAIT_STEPS');
}

function rejected(raw: number, reason: string): Verdict {
  return { rawDelta: raw, credited: 0, status: 'REJECTED', reason };
}

// ---------------------------------------------------------------------------------------------------------------
// Batch-level validation (hard limits, downgrade-only merge, caps)
// ---------------------------------------------------------------------------------------------------------------

export interface Limits {
  bucketMs: number;
  maxStepsPerBucket: number;
  maxBackfillMs: number;
  maxFutureMs: number;
  dailyRewardCap: number;
  rolling30MinCap: number;
}

export const DEFAULT_LIMITS: Limits = {
  bucketMs: 10_000,
  maxStepsPerBucket: 35,
  maxBackfillMs: 72 * 3_600_000,
  maxFutureMs: 120_000,
  dailyRewardCap: 20_000,
  rolling30MinCap: 6_300,
};

export interface BucketInput {
  startMs: number;
  bootCount: number;
  rawDelta: number;
  credited: number;
  state: BucketState;
  reason: string | null;
  walkFraction: number | null;
  evidenceMode: string;
  carryMode: string;
  hops: Hop[];
  /** Cumulative late step-counter parts already INCLUDED in rawDelta / credited (contract extension). Default 0. */
  lateRawAdded?: number;
  lateCreditedAdded?: number;
}

export type ParseResult = { ok: true; bucket: BucketInput } | { ok: false; startMs: number | null; reason: string };

/** Structural parse of one untrusted bucket. Never throws. */
export function parseBucket(raw: unknown): ParseResult {
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) return { ok: false, startMs: null, reason: 'MALFORMED' };
  const r = raw as Record<string, unknown>;
  const startMs = typeof r.startMs === 'number' && Number.isFinite(r.startMs) ? r.startMs : null;
  const bad = (reason: string): ParseResult => ({ ok: false, startMs, reason });
  if (startMs === null || !Number.isSafeInteger(startMs) || startMs < 0) return bad('MALFORMED');
  const bootCount = r.bootCount;
  if (typeof bootCount !== 'number' || !Number.isSafeInteger(bootCount) || bootCount < 0) return bad('MALFORMED');
  const rawDelta = r.rawDelta;
  if (typeof rawDelta !== 'number' || !Number.isSafeInteger(rawDelta) || rawDelta < -100_000 || rawDelta > 100_000) {
    return bad('MALFORMED');
  }
  const credited = r.credited;
  if (typeof credited !== 'number' || !Number.isFinite(credited)) return bad('MALFORMED');
  const state = r.state;
  if (typeof state !== 'string' || !(BUCKET_STATES as readonly string[]).includes(state)) return bad('MALFORMED');
  const reason = r.reason === undefined || r.reason === null ? null : typeof r.reason === 'string' ? r.reason.slice(0, 60) : undefined;
  if (reason === undefined) return bad('MALFORMED');
  let walkFraction: number | null = null;
  if (r.walkFraction !== undefined && r.walkFraction !== null) {
    if (typeof r.walkFraction !== 'number' || !Number.isFinite(r.walkFraction)) return bad('MALFORMED');
    walkFraction = Math.min(1, Math.max(0, r.walkFraction));
  }
  const evidenceMode = typeof r.evidenceMode === 'string' ? r.evidenceMode.slice(0, 24) : '';
  const carryMode = typeof r.carryMode === 'string' ? r.carryMode.slice(0, 24) : '';
  const lateRaw = r.lateRawAdded === undefined || r.lateRawAdded === null ? 0 : r.lateRawAdded;
  const lateCred = r.lateCreditedAdded === undefined || r.lateCreditedAdded === null ? 0 : r.lateCreditedAdded;
  for (const v of [lateRaw, lateCred]) {
    if (typeof v !== 'number' || !Number.isSafeInteger(v) || v < 0 || v > 100_000) return bad('MALFORMED');
  }
  if (!Array.isArray(r.hops) || r.hops.length > 5) return bad('MALFORMED');
  const hops: Hop[] = [];
  for (const h of r.hops) {
    if (h === null || typeof h !== 'object') return bad('MALFORMED');
    const label = (h as Record<string, unknown>).label;
    const imu = (h as Record<string, unknown>).imuSteps;
    if (typeof label !== 'string' || !(HOP_LABELS as readonly string[]).includes(label)) return bad('MALFORMED');
    if (typeof imu !== 'number' || !Number.isFinite(imu) || imu < 0 || imu > 1000) return bad('MALFORMED');
    hops.push({ label: label as HopLabel, imuSteps: imu });
  }
  return {
    ok: true,
    bucket: {
      startMs,
      bootCount,
      rawDelta,
      credited,
      state: state as BucketState,
      reason,
      walkFraction,
      evidenceMode,
      carryMode,
      hops,
      lateRawAdded: lateRaw as number,
      lateCreditedAdded: lateCred as number,
    },
  };
}

export interface BucketOut {
  startMs: number;
  bootCount: number;
  rawDelta: number;
  /** min(claimed, rawDelta) - keeps the invariant serverCredited <= clientCredited <= rawDelta. */
  clientCredited: number;
  /** What the client actually claimed (may exceed rawDelta). */
  claimedCredited: number;
  /** Independent server recomputation (before the client-claim downgrade). */
  recomputedCredited: number;
  serverCredited: number;
  state: BucketState;
  reason: string | null;
  flags: string[];
  evidenceMode: string;
  carryMode: string;
  walkFraction: number | null;
  hops: Hop[];
  dayKey: string;
  rewardEligible: boolean;
  lateRawAdded: number;
  lateCreditedAdded: number;
}

export interface RejectedBucket {
  startMs: number | null;
  reason: string;
}

export type Evaluation = { stored: false; rejected: RejectedBucket } | { stored: true; out: BucketOut };

/**
 * Per-bucket evaluation (no cross-bucket caps). `isRewardDevice=false` => never reward-eligible.
 * Hard failures that are NOT stored: BAD_ALIGNMENT, FUTURE_BUCKET, TOO_OLD, empty/negative raw.
 * CADENCE_EXCEEDED (raw > 35) is stored as REJECTED so a retry is a no-op and the day summary shows it.
 */
export function evaluateBucket(b: BucketInput, nowMs: number, isRewardDevice: boolean, limits: Limits = DEFAULT_LIMITS): Evaluation {
  if (b.startMs % limits.bucketMs !== 0) return { stored: false, rejected: { startMs: b.startMs, reason: 'BAD_ALIGNMENT' } };
  if (b.startMs > nowMs + limits.maxFutureMs) return { stored: false, rejected: { startMs: b.startMs, reason: 'FUTURE_BUCKET' } };
  if (b.startMs < nowMs - limits.maxBackfillMs) return { stored: false, rejected: { startMs: b.startMs, reason: 'TOO_OLD' } };
  if (b.rawDelta < 1) return { stored: false, rejected: { startMs: b.startMs, reason: 'CADENCE_EXCEEDED' } };

  const flags: string[] = [];
  const claimed = Math.max(0, Math.floor(b.credited));
  const clientCredited = Math.min(claimed, b.rawDelta);
  if (claimed > b.rawDelta) flags.push('CREDIT_GT_RAW');

  const verdict = verifyBucket(b.rawDelta, b.hops, false, { ...DEFAULT_VERIFIER, maxStepsPerBucket: limits.maxStepsPerBucket }) as Verdict;
  const recomputed = verdict.credited;

  let serverCredited = Math.min(clientCredited, recomputed);
  let state: BucketState;
  let reason: string | null;

  if (verdict.status === 'REJECTED' || verdict.status === 'UNWITNESSED') {
    state = verdict.status;
    reason = verdict.reason;
    serverCredited = 0;
    if (verdict.reason === 'CADENCE_EXCEEDED') flags.push('CADENCE_EXCEEDED');
  } else if (b.state === 'REJECTED' || b.state === 'UNWITNESSED') {
    // The honest client already refused to credit it; the server never upgrades.
    state = b.state;
    reason = b.reason ?? 'CLIENT_NOT_CREDITED';
    serverCredited = 0;
  } else if (serverCredited === 0) {
    state = 'REJECTED';
    reason = b.reason ?? 'CLIENT_ZERO_CREDIT';
  } else if (serverCredited === b.rawDelta) {
    state = 'VERIFIED';
    reason = null;
  } else {
    state = 'PARTIAL';
    reason = serverCredited === recomputed ? 'EXCESS_OVER_IMU' : (b.reason ?? 'EXCESS_OVER_IMU');
  }
  if (serverCredited < clientCredited) flags.push('DOWNGRADED');

  return {
    stored: true,
    out: {
      startMs: b.startMs,
      bootCount: b.bootCount,
      rawDelta: b.rawDelta,
      clientCredited,
      claimedCredited: claimed,
      recomputedCredited: recomputed,
      serverCredited,
      state,
      reason,
      flags,
      evidenceMode: b.evidenceMode,
      carryMode: b.carryMode,
      walkFraction: b.walkFraction,
      hops: b.hops,
      dayKey: dayKeyOf(b.startMs),
      rewardEligible: isRewardDevice && serverCredited > 0,
      lateRawAdded: b.lateRawAdded ?? 0,
      lateCreditedAdded: b.lateCreditedAdded ?? 0,
    },
  };
}

export interface ExistingEligible {
  startMs: number;
  serverCredited: number;
}

export interface CapContext {
  /** Already-stored reward-eligible buckets of this user (any device) for the affected days. */
  existing: ExistingEligible[];
  limits: Limits;
}

/**
 * Apply the rolling-30-minute ceiling and the daily reward cap to NEW buckets, in startMs order, on top of what is
 * already stored. Mutates `outs`. Reduction only: serverCredited never increases.
 */
export function applyCaps(outs: BucketOut[], ctx: CapContext): void {
  const dayTotals = new Map<string, number>();
  const recent: ExistingEligible[] = [...ctx.existing];
  for (const e of ctx.existing) {
    const k = dayKeyOf(e.startMs);
    dayTotals.set(k, (dayTotals.get(k) ?? 0) + e.serverCredited);
  }
  const ordered = [...outs].sort((a, b) => a.startMs - b.startMs);
  for (const o of ordered) {
    if (!o.rewardEligible || o.serverCredited <= 0) continue;

    // Rolling 30-minute physical ceiling (6,300 = 210/min x 30, NOT 2,500).
    const windowStart = o.startMs - 30 * 60_000;
    let inWindow = o.serverCredited;
    for (const r of recent) if (r.startMs > windowStart && r.startMs <= o.startMs) inWindow += r.serverCredited;
    if (inWindow > ctx.limits.rolling30MinCap) {
      o.flags.push('ROLLING_30MIN_CAP');
      o.serverCredited = Math.max(0, o.serverCredited - (inWindow - ctx.limits.rolling30MinCap));
    }

    // Daily policy cap: the excess is stored but never reward-eligible.
    const credited = dayTotals.get(o.dayKey) ?? 0;
    if (credited + o.serverCredited > ctx.limits.dailyRewardCap) {
      o.flags.push('DAILY_CAP');
      o.serverCredited = Math.max(0, ctx.limits.dailyRewardCap - credited);
    }

    if (o.flags.includes('ROLLING_30MIN_CAP') || o.flags.includes('DAILY_CAP')) {
      o.state = o.serverCredited > 0 ? 'PARTIAL' : 'REJECTED';
      o.reason = o.flags.includes('DAILY_CAP') ? 'DAILY_CAP' : 'ROLLING_30MIN_CAP';
    }
    o.rewardEligible = o.serverCredited > 0;
    if (o.rewardEligible) {
      dayTotals.set(o.dayKey, credited + o.serverCredited);
      recent.push({ startMs: o.startMs, serverCredited: o.serverCredited });
    }
  }
}

export interface StoredBucketForLate {
  rawDelta: number;
  serverCredited: number;
  lateRawAdded: number;
}

export type LateDecision = { kind: 'DUPLICATE' } | { kind: 'REJECT'; reason: string } | { kind: 'UPDATE'; out: BucketOut };

/**
 * A bucket whose deterministic doc already exists. If the incoming CUMULATIVE `lateRawAdded` is greater than the stored
 * one this is a late-event UPDATE: the same validation (35/bucket, rolling 30 min, daily cap, age) is re-run and
 * serverCredited is recomputed downgrade-only. Equal/lower late values are plain duplicates (no-op). An update can never
 * lower the stored serverCredited, never exceed clientCredited or the new rawDelta; if any rule fails the update is
 * REJECTED and the stored doc stays unchanged.
 * `existing` must NOT contain this bucket's own previous credit.
 */
export function decideLateUpdate(
  incoming: BucketInput,
  stored: StoredBucketForLate,
  ctx: { nowMs: number; isRewardDevice: boolean; limits?: Limits; existing: ExistingEligible[] },
): LateDecision {
  const limits = ctx.limits ?? DEFAULT_LIMITS;
  const incomingLate = incoming.lateRawAdded ?? 0;
  if (incomingLate <= stored.lateRawAdded) return { kind: 'DUPLICATE' };
  if (incoming.rawDelta < stored.rawDelta) return { kind: 'REJECT', reason: 'LATE_RAW_DECREASED' };
  const ev = evaluateBucket(incoming, ctx.nowMs, ctx.isRewardDevice, limits);
  if (!ev.stored) return { kind: 'REJECT', reason: ev.rejected.reason };
  if (ev.out.flags.includes('CADENCE_EXCEEDED')) return { kind: 'REJECT', reason: 'CADENCE_EXCEEDED' };
  applyCaps([ev.out], { existing: ctx.existing, limits });
  if (ev.out.serverCredited < stored.serverCredited) return { kind: 'REJECT', reason: 'LATE_UPDATE_LOWERS_CREDIT' };
  ev.out.flags.push('LATE_UPDATED');
  return { kind: 'UPDATE', out: ev.out };
}

export interface BatchValidation {
  stored: BucketOut[];
  rejected: RejectedBucket[];
}

/**
 * Full pipeline over NEW (non-duplicate) buckets: parse -> evaluate -> caps.
 * Duplicates must be removed by the caller (deterministic bucket doc ids make them no-ops).
 */
export function validateBatch(
  rawBuckets: readonly unknown[],
  opts: { nowMs: number; isRewardDevice: boolean; limits?: Limits; existing?: ExistingEligible[] },
): BatchValidation {
  const limits = opts.limits ?? DEFAULT_LIMITS;
  const stored: BucketOut[] = [];
  const rejected: RejectedBucket[] = [];
  const seen = new Set<number>();
  for (const raw of rawBuckets) {
    const p = parseBucket(raw);
    if (!p.ok) {
      rejected.push({ startMs: p.startMs, reason: p.reason });
      continue;
    }
    if (seen.has(p.bucket.startMs)) continue; // duplicate within the same batch is a no-op
    seen.add(p.bucket.startMs);
    const ev = evaluateBucket(p.bucket, opts.nowMs, opts.isRewardDevice, limits);
    if (ev.stored) stored.push(ev.out);
    else rejected.push(ev.rejected);
  }
  applyCaps(stored, { existing: opts.existing ?? [], limits });
  for (const s of stored) if (s.state === 'REJECTED' || s.state === 'UNWITNESSED') rejected.push({ startMs: s.startMs, reason: s.reason ?? s.state });
  return { stored, rejected };
}

// ---------------------------------------------------------------------------------------------------------------
// Day summary recomputation (idempotent: always from stored buckets, never incremental)
// ---------------------------------------------------------------------------------------------------------------

export interface StoredBucketLite {
  rawDelta: number;
  serverCredited: number;
  state: BucketState;
  rewardEligible: boolean;
}

export interface DaySummary {
  rawSteps: number;
  verifiedSteps: number;
  rejectedSteps: number;
  unwitnessedSteps: number;
  pendingSteps: number;
}

export function summarizeDay(buckets: readonly StoredBucketLite[]): DaySummary {
  const s: DaySummary = { rawSteps: 0, verifiedSteps: 0, rejectedSteps: 0, unwitnessedSteps: 0, pendingSteps: 0 };
  for (const b of buckets) {
    s.rawSteps += b.rawDelta;
    if (b.rewardEligible) s.verifiedSteps += b.serverCredited;
    if (b.state === 'REJECTED') s.rejectedSteps += b.rawDelta;
    if (b.state === 'UNWITNESSED') s.unwitnessedSteps += b.rawDelta;
  }
  return s;
}
