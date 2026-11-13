import { BucketInput, decideLateUpdate, evaluateBucket, Hop, parseBucket } from '../../src/steps/validateBatch';

const NOW = Date.UTC(2026, 5, 10, 6, 0, 0);
const START = Math.floor((NOW - 3_600_000) / 10_000) * 10_000;
const walk = (imu: number): Hop[] => Array.from({ length: 5 }, () => ({ label: 'WALK' as const, imuSteps: imu }));

function bucket(over: Partial<BucketInput> = {}): BucketInput {
  return {
    startMs: START,
    bootCount: 1,
    rawDelta: 30,
    credited: 30,
    state: 'VERIFIED',
    reason: null,
    walkFraction: 1,
    evidenceMode: 'E1',
    carryMode: 'POCKET',
    hops: walk(8), // allowed = floor(1.15 * 40) = 46
    lateRawAdded: 10,
    lateCreditedAdded: 10,
    ...over,
  };
}

const stored = (over: Partial<{ rawDelta: number; serverCredited: number; lateRawAdded: number }> = {}) => ({
  rawDelta: 20,
  serverCredited: 20,
  lateRawAdded: 0,
  ...over,
});
const ctx = (over: Record<string, unknown> = {}) => ({ nowMs: NOW, isRewardDevice: true, existing: [], ...over });

describe('late-event update of an already-stored bucket (contract extension)', () => {
  test('parseBucket: lateRawAdded / lateCreditedAdded default to 0 and must be non-negative integers', () => {
    const p = parseBucket({ ...bucket(), lateRawAdded: undefined, lateCreditedAdded: undefined });
    expect(p.ok && p.bucket.lateRawAdded).toBe(0);
    expect(p.ok && p.bucket.lateCreditedAdded).toBe(0);
    expect(parseBucket({ ...bucket(), lateRawAdded: -1 }).ok).toBe(false);
    expect(parseBucket({ ...bucket(), lateCreditedAdded: 1.5 }).ok).toBe(false);
    expect(parseBucket({ ...bucket(), lateRawAdded: '3' }).ok).toBe(false);
  });

  test('evaluateBucket carries the late fields onto a new bucket', () => {
    const e = evaluateBucket(bucket(), NOW, true);
    expect(e.stored && e.out.lateRawAdded).toBe(10);
    expect(e.stored && e.out.lateCreditedAdded).toBe(10);
  });

  test('greater cumulative late part raises raw and credited within limits (UPDATE)', () => {
    const d = decideLateUpdate(bucket(), stored(), ctx());
    expect(d.kind).toBe('UPDATE');
    if (d.kind === 'UPDATE') {
      expect(d.out.rawDelta).toBe(30);
      expect(d.out.serverCredited).toBe(30);
      expect(d.out.state).toBe('VERIFIED');
      expect(d.out.flags).toContain('LATE_UPDATED');
      expect(d.out.lateRawAdded).toBe(10);
    }
  });

  test('equal or lower late values are plain duplicates (no-op), even if other numbers differ', () => {
    expect(decideLateUpdate(bucket({ lateRawAdded: 0 }), stored({ lateRawAdded: 0 }), ctx()).kind).toBe('DUPLICATE');
    expect(decideLateUpdate(bucket({ lateRawAdded: 10 }), stored({ lateRawAdded: 10 }), ctx()).kind).toBe('DUPLICATE');
    expect(decideLateUpdate(bucket({ lateRawAdded: 5, rawDelta: 35, credited: 35 }), stored({ lateRawAdded: 10 }), ctx()).kind).toBe('DUPLICATE');
    expect(decideLateUpdate(bucket({ lateRawAdded: undefined }), stored(), ctx()).kind).toBe('DUPLICATE');
  });

  test('over-limit late update (raw > 35 per bucket) is REJECTED CADENCE_EXCEEDED', () => {
    const d = decideLateUpdate(bucket({ rawDelta: 40, credited: 40, lateRawAdded: 20 }), stored({ rawDelta: 20 }), ctx());
    expect(d).toEqual({ kind: 'REJECT', reason: 'CADENCE_EXCEEDED' });
  });

  test('exactly 35 after the late part is allowed', () => {
    const d = decideLateUpdate(bucket({ rawDelta: 35, credited: 35, lateRawAdded: 15 }), stored({ rawDelta: 20 }), ctx());
    expect(d.kind).toBe('UPDATE');
    expect(d.kind === 'UPDATE' && d.out.serverCredited).toBe(35);
  });

  test('a decreasing rawDelta is rejected', () => {
    expect(decideLateUpdate(bucket({ rawDelta: 15, credited: 15 }), stored({ rawDelta: 20 }), ctx())).toEqual({ kind: 'REJECT', reason: 'LATE_RAW_DECREASED' });
  });

  test('a re-send can never lower the stored serverCredited (client claims less than stored)', () => {
    expect(decideLateUpdate(bucket({ credited: 22 }), stored({ serverCredited: 28, rawDelta: 28 }), ctx())).toEqual({ kind: 'REJECT', reason: 'LATE_UPDATE_LOWERS_CREDIT' });
  });

  test('worse evidence on re-send cannot lower the stored credit either', () => {
    const d = decideLateUpdate(bucket({ hops: walk(2) }), stored({ serverCredited: 20 }), ctx()); // allowed = floor(1.15*10)=11 < 20
    expect(d).toEqual({ kind: 'REJECT', reason: 'LATE_UPDATE_LOWERS_CREDIT' });
  });

  test('serverCredited stays <= clientCredited <= new rawDelta (downgrade-only) even if the client over-claims', () => {
    const d = decideLateUpdate(bucket({ credited: 99 }), stored(), ctx());
    expect(d.kind).toBe('UPDATE');
    if (d.kind === 'UPDATE') {
      expect(d.out.serverCredited).toBeLessThanOrEqual(d.out.clientCredited);
      expect(d.out.clientCredited).toBeLessThanOrEqual(d.out.rawDelta);
      expect(d.out.serverCredited).toBe(30);
    }
  });

  test('too-old buckets cannot be late-updated', () => {
    const old = Math.floor((NOW - 80 * 3_600_000) / 10_000) * 10_000;
    expect(decideLateUpdate(bucket({ startMs: old }), stored(), ctx())).toEqual({ kind: 'REJECT', reason: 'TOO_OLD' });
  });

  test('the daily reward cap is re-applied to the update (excluding the bucket own previous credit)', () => {
    const existing = [{ startMs: START - 3_600_000, serverCredited: 19_990 }];
    const d = decideLateUpdate(bucket({ rawDelta: 35, credited: 35, lateRawAdded: 15, hops: walk(9) }), stored({ rawDelta: 20, serverCredited: 5 }), ctx({ existing }));
    expect(d.kind).toBe('UPDATE');
    if (d.kind === 'UPDATE') {
      expect(d.out.serverCredited).toBe(10);
      expect(d.out.flags).toContain('DAILY_CAP');
    }
  });

  test('non-reward devices update display values but never become reward eligible', () => {
    const d = decideLateUpdate(bucket(), stored(), ctx({ isRewardDevice: false }));
    expect(d.kind === 'UPDATE' && d.out.rewardEligible).toBe(false);
  });

  test('an update whose evidence is now a shake is accepted as REJECTED only if it does not lower credit', () => {
    const shake: Hop[] = Array.from({ length: 5 }, () => ({ label: 'SHAKE' as const, imuSteps: 0 }));
    // stored credit 0 (was rejected before) -> state may change, credit stays 0
    const d = decideLateUpdate(bucket({ hops: shake }), stored({ serverCredited: 0 }), ctx());
    expect(d.kind === 'UPDATE' && d.out.state).toBe('REJECTED');
    // stored credit 20 -> would be lowered -> rejected, old doc stays
    expect(decideLateUpdate(bucket({ hops: shake }), stored({ serverCredited: 20 }), ctx())).toEqual({ kind: 'REJECT', reason: 'LATE_UPDATE_LOWERS_CREDIT' });
  });
});
