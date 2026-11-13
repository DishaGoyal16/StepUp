import {
  applyCaps,
  BucketInput,
  DEFAULT_LIMITS,
  evaluateBucket,
  Hop,
  HopLabel,
  parseBucket,
  summarizeDay,
  validateBatch,
  verifyBucket,
} from '../../src/steps/validateBatch';

/** Build 5 hops (2 s each) with the same label/imuSteps, mirroring `uniform()` in BucketVerifierGoldenTest.kt. */
function uniform(label: HopLabel, imuSteps: number, count = 5): Hop[] {
  return Array.from({ length: count }, () => ({ label, imuSteps }));
}
function hops(labels: HopLabel[], imu: number[]): Hop[] {
  return labels.map((label, i) => ({ label, imuSteps: imu[i] }));
}

const NOW = Date.UTC(2026, 5, 10, 6, 0, 0); // fixed "now"
const START = Math.floor((NOW - 3_600_000) / 10_000) * 10_000; // 1 h ago, aligned

function bucket(over: Partial<BucketInput> = {}): BucketInput {
  return {
    startMs: START,
    bootCount: 1,
    rawDelta: 18,
    credited: 18,
    state: 'VERIFIED',
    reason: null,
    walkFraction: 1,
    evidenceMode: 'E1',
    carryMode: 'POCKET',
    hops: uniform('WALK', 3.6),
    ...over,
  };
}

describe('BucketVerifier port - the nine Kotlin golden vectors (V1-V9)', () => {
  test('V1 pure walk is VERIFIED 18/18', () => {
    const r = verifyBucket(18, uniform('WALK', 3.6))!;
    expect(r).toEqual({ rawDelta: 18, credited: 18, status: 'VERIFIED', reason: null });
  });

  test('V2 shake is REJECTED SHAKE_PATTERN', () => {
    const r = verifyBucket(26, uniform('SHAKE', 0))!;
    expect(r.rawDelta).toBe(26);
    expect(r.credited).toBe(0);
    expect(r.status).toBe('REJECTED');
    expect(r.reason).toBe('SHAKE_PATTERN');
  });

  test('V3 counter without motion is REJECTED NO_MOTION_EVIDENCE', () => {
    const r = verifyBucket(18, uniform('STILL', 0))!;
    expect(r.credited).toBe(0);
    expect(r.status).toBe('REJECTED');
    expect(r.reason).toBe('NO_MOTION_EVIDENCE');
  });

  test('V4 mixed bucket is capped by the IMU estimate: 24 raw -> 12 PARTIAL EXCESS_OVER_IMU', () => {
    const h = hops(['WALK', 'WALK', 'WALK', 'SHAKE', 'SHAKE'], [3.6, 3.6, 3.6, 0, 0]);
    const r = verifyBucket(24, h)!;
    expect(r.rawDelta).toBe(24);
    expect(r.credited).toBe(12);
    expect(r.status).toBe('PARTIAL');
    expect(r.reason).toBe('EXCESS_OVER_IMU');
  });

  test('V5 impossible cadence (50 in 10 s) is REJECTED CADENCE_EXCEEDED', () => {
    const r = verifyBucket(50, uniform('WALK', 7.0))!;
    expect(r.credited).toBe(0);
    expect(r.status).toBe('REJECTED');
    expect(r.reason).toBe('CADENCE_EXCEEDED');
  });

  test('V6 vehicle (AR says vehicle) is REJECTED IN_VEHICLE', () => {
    const r = verifyBucket(12, uniform('WALK', 2.4), true)!;
    expect(r.credited).toBe(0);
    expect(r.status).toBe('REJECTED');
    expect(r.reason).toBe('IN_VEHICLE');
  });

  test('V7 missing IMU coverage (3 of 5 hops) is UNWITNESSED NO_IMU_EVIDENCE', () => {
    const r = verifyBucket(18, uniform('WALK', 3.6, 3))!;
    expect(r.credited).toBe(0);
    expect(r.status).toBe('UNWITNESSED');
    expect(r.reason).toBe('NO_IMU_EVIDENCE');
  });

  test('V8 minority walk (2 of 5) is REJECTED SHAKE_PATTERN', () => {
    const h = hops(['WALK', 'WALK', 'SHAKE', 'SHAKE', 'SHAKE'], [3.6, 3.6, 0, 0, 0]);
    const r = verifyBucket(18, h)!;
    expect(r.credited).toBe(0);
    expect(r.status).toBe('REJECTED');
    expect(r.reason).toBe('SHAKE_PATTERN');
  });

  test('V9 empty bucket returns null', () => {
    expect(verifyBucket(0, uniform('WALK', 3.6))).toBeNull();
  });

  test('coverage boundary: 4 of 5 hops (0.8) is accepted; 5 hops needed for full coverage', () => {
    const r = verifyBucket(14, uniform('WALK', 3.5, 4))!;
    expect(r.status).toBe('VERIFIED');
  });

  test('dominant non-gait label tie is resolved in encounter order (Kotlin maxByOrNull semantics)', () => {
    // 2 STILL then 2 VEHICLE, 1 WALK: tie of 2-2 => first encountered (STILL) wins.
    const h = hops(['STILL', 'STILL', 'VEHICLE', 'VEHICLE', 'WALK'], [0, 0, 0, 0, 3]);
    expect(verifyBucket(10, h)!.reason).toBe('NO_MOTION_EVIDENCE');
    const h2 = hops(['VEHICLE', 'VEHICLE', 'STILL', 'STILL', 'WALK'], [0, 0, 0, 0, 3]);
    expect(verifyBucket(10, h2)!.reason).toBe('VEHICLE_MOTION');
  });

  test('UNKNOWN-dominant minority walk gives NOT_GAIT; zero IMU gait steps gives NO_GAIT_STEPS', () => {
    expect(verifyBucket(10, hops(['UNKNOWN', 'UNKNOWN', 'UNKNOWN', 'WALK', 'WALK'], [0, 0, 0, 1, 1]))!.reason).toBe('NOT_GAIT');
    const r = verifyBucket(10, uniform('WALK', 0))!;
    expect(r.status).toBe('REJECTED');
    expect(r.reason).toBe('NO_GAIT_STEPS');
  });
});

describe('server evaluateBucket: hard limits + downgrade-only', () => {
  test('valid bucket from the reward device is VERIFIED and reward eligible', () => {
    const e = evaluateBucket(bucket(), NOW, true);
    expect(e.stored).toBe(true);
    if (e.stored) {
      expect(e.out.serverCredited).toBe(18);
      expect(e.out.state).toBe('VERIFIED');
      expect(e.out.rewardEligible).toBe(true);
      expect(e.out.dayKey).toBe('20260610');
    }
  });

  test('non-reward device => rewardEligible false but still stored/credited for display', () => {
    const e = evaluateBucket(bucket(), NOW, false);
    expect(e.stored && e.out.rewardEligible).toBe(false);
    expect(e.stored && e.out.serverCredited).toBe(18);
  });

  test('misaligned startMs is rejected and not stored', () => {
    const e = evaluateBucket(bucket({ startMs: START + 1 }), NOW, true);
    expect(e).toEqual({ stored: false, rejected: { startMs: START + 1, reason: 'BAD_ALIGNMENT' } });
  });

  test('future bucket (> 120 s) is rejected; within tolerance accepted', () => {
    const farFuture = Math.ceil((NOW + 121_000) / 10_000) * 10_000;
    expect(evaluateBucket(bucket({ startMs: farFuture }), NOW, true)).toMatchObject({ stored: false, rejected: { reason: 'FUTURE_BUCKET' } });
    const ok = Math.floor((NOW + 100_000) / 10_000) * 10_000;
    expect(evaluateBucket(bucket({ startMs: ok }), NOW, true).stored).toBe(true);
  });

  test('bucket older than 72 h is rejected TOO_OLD; just inside 72 h is accepted', () => {
    const old = Math.floor((NOW - 72 * 3_600_000 - 20_000) / 10_000) * 10_000;
    expect(evaluateBucket(bucket({ startMs: old }), NOW, true)).toMatchObject({ stored: false, rejected: { reason: 'TOO_OLD' } });
    const edge = Math.ceil((NOW - 72 * 3_600_000 + 20_000) / 10_000) * 10_000;
    expect(evaluateBucket(bucket({ startMs: edge }), NOW, true).stored).toBe(true);
  });

  test('over-cadence (> 35) is stored as REJECTED CADENCE_EXCEEDED with zero credit', () => {
    const e = evaluateBucket(bucket({ rawDelta: 50, credited: 50, hops: uniform('WALK', 20) }), NOW, true);
    expect(e.stored).toBe(true);
    if (e.stored) {
      expect(e.out.state).toBe('REJECTED');
      expect(e.out.reason).toBe('CADENCE_EXCEEDED');
      expect(e.out.serverCredited).toBe(0);
      expect(e.out.rewardEligible).toBe(false);
    }
  });

  test('exactly 35 steps in a bucket is allowed', () => {
    const e = evaluateBucket(bucket({ rawDelta: 35, credited: 35, hops: uniform('RUN', 7) }), NOW, true);
    expect(e.stored && e.out.serverCredited).toBe(35);
  });

  test('over-claim is DOWNGRADED to the recomputed value (never raised): claims 24, IMU allows 12', () => {
    const h = hops(['WALK', 'WALK', 'WALK', 'SHAKE', 'SHAKE'], [3.6, 3.6, 3.6, 0, 0]);
    const e = evaluateBucket(bucket({ rawDelta: 24, credited: 24, hops: h }), NOW, true);
    expect(e.stored).toBe(true);
    if (e.stored) {
      expect(e.out.serverCredited).toBe(12);
      expect(e.out.state).toBe('PARTIAL');
      expect(e.out.flags).toContain('DOWNGRADED');
      expect(e.out.clientCredited).toBe(24);
      expect(e.out.recomputedCredited).toBe(12);
    }
  });

  test('under-claim is never raised: client claims 5 but evidence supports 18 => 5', () => {
    const e = evaluateBucket(bucket({ credited: 5, state: 'PARTIAL', reason: 'EXCESS_OVER_IMU' }), NOW, true);
    expect(e.stored && e.out.serverCredited).toBe(5);
    expect(e.stored && e.out.recomputedCredited).toBe(18);
    expect(e.stored && e.out.state).toBe('PARTIAL');
  });

  test('credited greater than raw is clamped to raw and flagged CREDIT_GT_RAW', () => {
    const e = evaluateBucket(bucket({ rawDelta: 10, credited: 99, hops: uniform('WALK', 5) }), NOW, true);
    expect(e.stored).toBe(true);
    if (e.stored) {
      expect(e.out.clientCredited).toBe(10);
      expect(e.out.claimedCredited).toBe(99);
      expect(e.out.serverCredited).toBe(10);
      expect(e.out.flags).toContain('CREDIT_GT_RAW');
    }
  });

  test('shake hops with a VERIFIED claim are rejected (server catches the lie)', () => {
    const e = evaluateBucket(bucket({ rawDelta: 26, credited: 26, hops: uniform('SHAKE', 0) }), NOW, true);
    expect(e.stored && e.out.state).toBe('REJECTED');
    expect(e.stored && e.out.reason).toBe('SHAKE_PATTERN');
    expect(e.stored && e.out.serverCredited).toBe(0);
  });

  test('client-REJECTED / UNWITNESSED buckets are never upgraded even with perfect hops', () => {
    const r = evaluateBucket(bucket({ state: 'REJECTED', reason: 'SHAKE_PATTERN', credited: 0 }), NOW, true);
    expect(r.stored && r.out.serverCredited).toBe(0);
    expect(r.stored && r.out.state).toBe('REJECTED');
    const u = evaluateBucket(bucket({ state: 'UNWITNESSED', reason: 'NO_IMU_EVIDENCE', credited: 0 }), NOW, true);
    expect(u.stored && u.out.state).toBe('UNWITNESSED');
    const lie = evaluateBucket(bucket({ state: 'REJECTED', credited: 18 }), NOW, true);
    expect(lie.stored && lie.out.serverCredited).toBe(0);
  });

  test('missing IMU hops => UNWITNESSED, zero credit', () => {
    const e = evaluateBucket(bucket({ hops: [] }), NOW, true);
    expect(e.stored && e.out.state).toBe('UNWITNESSED');
    expect(e.stored && e.out.serverCredited).toBe(0);
  });

  test('rawDelta below 1 is not stored', () => {
    expect(evaluateBucket(bucket({ rawDelta: 0 }), NOW, true).stored).toBe(false);
    expect(evaluateBucket(bucket({ rawDelta: -4 }), NOW, true).stored).toBe(false);
  });
});

describe('parseBucket', () => {
  test('accepts a well-formed bucket and rejects garbage without throwing', () => {
    expect(parseBucket(bucket()).ok).toBe(true);
    for (const bad of [null, 7, 'x', [], {}, { ...bucket(), startMs: 'a' }, { ...bucket(), state: 'BOGUS' }, { ...bucket(), hops: [{ label: 'FLY', imuSteps: 1 }] }, { ...bucket(), hops: new Array(6).fill({ label: 'WALK', imuSteps: 1 }) }, { ...bucket(), credited: NaN }, { ...bucket(), rawDelta: 1.5 }]) {
      expect(parseBucket(bad).ok).toBe(false);
    }
  });
});

describe('caps: rolling 30 min and daily reward cap', () => {
  const mk = (i: number, steps: number): BucketInput =>
    bucket({ startMs: START - 3 * 3_600_000 + i * 10_000, rawDelta: steps, credited: steps, hops: uniform('RUN', steps / 4) });

  test('a real 30-minute run at 180 steps/min (30 per bucket x 180) is NOT clipped (6300 ceiling, not 2500)', () => {
    const raw = Array.from({ length: 180 }, (_, i) => mk(i, 30));
    const v = validateBatch(raw, { nowMs: NOW, isRewardDevice: true });
    expect(v.stored.every((b) => !b.flags.includes('ROLLING_30MIN_CAP'))).toBe(true);
    expect(v.stored.reduce((s, b) => s + b.serverCredited, 0)).toBe(5400);
  });

  test('rolling ceiling bites when other reward steps already fill the window', () => {
    const existing = Array.from({ length: 180 }, (_, i) => ({ startMs: START - 3 * 3_600_000 + i * 10_000 - 1_000_000_000 + 1_000_000_000, serverCredited: 35 })); // 6300 in the window
    const first = existing[0].startMs;
    const v = validateBatch([bucket({ startMs: first + 180 * 10_000 - 10_000, rawDelta: 35, credited: 35, hops: uniform('RUN', 9) })], {
      nowMs: NOW,
      isRewardDevice: true,
      existing,
    });
    const out = v.stored[0];
    expect(out.flags).toContain('ROLLING_30MIN_CAP');
    expect(out.serverCredited).toBe(0);
    expect(out.rewardEligible).toBe(false);
  });

  test('farm at the physical ceiling is stopped by the 20,000 daily cap (stored, partly eligible)', () => {
    const day = Date.UTC(2026, 5, 10, 0, 0, 0) - 5.5 * 3_600_000 + 3_600_000; // inside IST 2026-06-10
    const raw = Array.from({ length: 600 }, (_, i) => bucket({ startMs: day + i * 10_000, rawDelta: 35, credited: 35, hops: uniform('RUN', 9) }));
    const now = day + 700 * 10_000;
    const v = validateBatch(raw, { nowMs: now, isRewardDevice: true });
    const eligible = v.stored.filter((b) => b.rewardEligible).reduce((s, b) => s + b.serverCredited, 0);
    expect(eligible).toBe(20_000);
    expect(v.stored.some((b) => b.flags.includes('DAILY_CAP'))).toBe(true);
    expect(v.stored).toHaveLength(600); // excess stored, just not reward eligible
    expect(v.stored.filter((b) => !b.rewardEligible).length).toBeGreaterThan(0);
  });

  test('daily cap accounts for steps already credited today', () => {
    const existing = [{ startMs: START - 3_600_000, serverCredited: 19_990 }]; // >30 min earlier, same IST day
    const v = validateBatch([bucket({ startMs: START, rawDelta: 35, credited: 35, hops: uniform('RUN', 9) })], { nowMs: NOW, isRewardDevice: true, existing });
    expect(v.stored[0].serverCredited).toBe(10);
    expect(v.stored[0].flags).toContain('DAILY_CAP');
    expect(v.stored[0].state).toBe('PARTIAL');
  });

  test('non-reward device buckets never consume the reward cap', () => {
    const raw = Array.from({ length: 10 }, (_, i) => mk(i, 35));
    const v = validateBatch(raw, { nowMs: NOW, isRewardDevice: false, existing: [{ startMs: START, serverCredited: 20_000 }] });
    expect(v.stored.every((b) => !b.rewardEligible && !b.flags.includes('DAILY_CAP'))).toBe(true);
  });

  test('applyCaps never increases a credit', () => {
    const e = evaluateBucket(bucket(), NOW, true);
    if (!e.stored) throw new Error('expected stored');
    const before = e.out.serverCredited;
    applyCaps([e.out], { existing: [], limits: DEFAULT_LIMITS });
    expect(e.out.serverCredited).toBeLessThanOrEqual(before);
  });
});

describe('batch behaviour and day summary recomputation', () => {
  test('duplicate buckets inside one batch collapse to one (idempotent by startMs)', () => {
    const b = bucket();
    const v = validateBatch([b, { ...b }, { ...b }], { nowMs: NOW, isRewardDevice: true });
    expect(v.stored).toHaveLength(1);
  });

  test('summarizeDay sums raw / verified (eligible only) / rejected / unwitnessed', () => {
    const s = summarizeDay([
      { rawDelta: 18, serverCredited: 18, state: 'VERIFIED', rewardEligible: true },
      { rawDelta: 24, serverCredited: 12, state: 'PARTIAL', rewardEligible: true },
      { rawDelta: 26, serverCredited: 0, state: 'REJECTED', rewardEligible: false },
      { rawDelta: 18, serverCredited: 0, state: 'UNWITNESSED', rewardEligible: false },
      { rawDelta: 20, serverCredited: 20, state: 'VERIFIED', rewardEligible: false }, // display-only device
    ]);
    expect(s).toEqual({ rawSteps: 106, verifiedSteps: 30, rejectedSteps: 26, unwitnessedSteps: 18, pendingSteps: 0 });
  });

  test('summarizeDay is a pure function of the stored set: order and repetition of recomputation do not matter', () => {
    const list = [
      { rawDelta: 10, serverCredited: 10, state: 'VERIFIED' as const, rewardEligible: true },
      { rawDelta: 5, serverCredited: 0, state: 'REJECTED' as const, rewardEligible: false },
    ];
    expect(summarizeDay([...list].reverse())).toEqual(summarizeDay(list));
    expect(summarizeDay(list)).toEqual(summarizeDay(list));
  });
});

describe('property tests: serverCredited <= clientCredited <= rawDelta, never raised', () => {
  // Deterministic LCG so failures reproduce.
  let seed = 123456789;
  const rnd = () => {
    seed = (seed * 1664525 + 1013904223) % 4294967296;
    return seed / 4294967296;
  };
  const labels: HopLabel[] = ['WALK', 'RUN', 'SHAKE', 'VEHICLE', 'STILL', 'UNKNOWN'];
  const states = ['VERIFIED', 'PARTIAL', 'REJECTED', 'UNWITNESSED'] as const;

  test('5000 random buckets satisfy the downgrade-only invariants', () => {
    let stored = 0;
    for (let i = 0; i < 5000; i++) {
      const raw = Math.floor(rnd() * 60);
      const nHops = Math.floor(rnd() * 6);
      const h: Hop[] = Array.from({ length: nHops }, () => ({ label: labels[Math.floor(rnd() * labels.length)], imuSteps: Math.round(rnd() * 100) / 10 }));
      const b = bucket({
        startMs: START - Math.floor(rnd() * 1000) * 10_000,
        rawDelta: raw,
        credited: Math.floor(rnd() * 80),
        state: states[Math.floor(rnd() * 4)],
        hops: h,
      });
      const e = evaluateBucket(b, NOW, rnd() < 0.8);
      if (!e.stored) continue;
      stored++;
      const o = e.out;
      expect(o.serverCredited).toBeLessThanOrEqual(o.clientCredited);
      expect(o.clientCredited).toBeLessThanOrEqual(o.rawDelta);
      expect(o.serverCredited).toBeLessThanOrEqual(o.recomputedCredited);
      expect(o.serverCredited).toBeGreaterThanOrEqual(0);
      expect(o.serverCredited).toBeLessThanOrEqual(35);
      if (o.state === 'REJECTED' || o.state === 'UNWITNESSED') expect(o.serverCredited).toBe(0);
      if (o.serverCredited === 0) expect(o.rewardEligible).toBe(false);
    }
    expect(stored).toBeGreaterThan(1000);
  });

  test('re-validating the same input is deterministic (no hidden state): result equality', () => {
    const raws = Array.from({ length: 50 }, (_, i) => bucket({ startMs: START - i * 10_000, rawDelta: 10 + (i % 20), credited: 10 + (i % 20), hops: uniform('WALK', 3) }));
    const a = validateBatch(raws, { nowMs: NOW, isRewardDevice: true });
    const b = validateBatch(raws, { nowMs: NOW, isRewardDevice: true });
    expect(a).toEqual(b);
  });

  test('caps never raise the per-bucket serverCredited relative to evaluation', () => {
    const raws = Array.from({ length: 400 }, (_, i) => bucket({ startMs: START - i * 10_000, rawDelta: 35, credited: 35, hops: uniform('RUN', 9) }));
    const pre = raws.map((r) => evaluateBucket(r, NOW, true)).map((e) => (e.stored ? e.out.serverCredited : -1));
    const v = validateBatch(raws, { nowMs: NOW, isRewardDevice: true });
    const byStart = new Map(v.stored.map((o) => [o.startMs, o.serverCredited]));
    raws.forEach((r, i) => {
      const after = byStart.get(r.startMs);
      if (after !== undefined) expect(after).toBeLessThanOrEqual(pre[i]);
    });
  });
});
