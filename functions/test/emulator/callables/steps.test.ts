import { db } from '../../../src/lib/firebase';
import { setClock } from '../../../src/lib/clock';
import { handleRegisterDevice } from '../../../src/profile/profile';
import { recomputeDailySummary } from '../../../src/steps/summaries';
import { handleSyncStepBuckets } from '../../../src/steps/syncStepBuckets';
import {
  alignedBefore,
  authReq,
  expectError,
  freeze,
  getDoc,
  makeUser,
  mkBucket,
  resetAll,
  setReward,
  sync,
  T0,
  uniformHops,
  walkBuckets,
} from '../helpers/env';

const DEV = 'alice-device-1';
const DAY_KEY = '20260302';
const id = (start: number, dev = DEV) => `stepBuckets/alice_${dev}_${start}`;

beforeEach(async () => {
  await resetAll();
  freeze();
  await makeUser('alice');
  await setReward('alice', DEV);
});
afterAll(() => setClock(null));

describe('syncStepBuckets: valid, duplicate, partial overlap', () => {
  test('valid buckets are stored with deterministic ids, credited, and the day summary is computed', async () => {
    const first = alignedBefore(T0, 3_600_000);
    const r = await sync('alice', DEV, walkBuckets(first, 6, 20));
    expect(r).toMatchObject({ accepted: 6, duplicates: 0, rejected: [], downgraded: 0, updated: 0 });
    expect(r.today).toEqual({ verifiedSteps: 120, rawSteps: 120, rejectedSteps: 0, unwitnessedSteps: 0 });
    const b = await getDoc(id(first));
    expect(b).toMatchObject({
      uid: 'alice',
      deviceId: DEV,
      startMs: first,
      rawDelta: 20,
      clientCredited: 20,
      serverCredited: 20,
      state: 'VERIFIED',
      rewardEligible: true,
      dayKey: DAY_KEY,
      lateRawAdded: 0,
      lateCreditedAdded: 0,
    });
    expect(await getDoc(`dailyStepSummaries/alice_${DAY_KEY}`)).toMatchObject({ uid: 'alice', dayKey: DAY_KEY, hostelId: 'agira', verifiedSteps: 120, rawSteps: 120, pendingSteps: 0 });
  });

  test('duplicate sync is a no-op: counts as duplicates, changes nothing (docs and summary identical)', async () => {
    const first = alignedBefore(T0, 3_600_000);
    const batch = walkBuckets(first, 6, 20);
    await sync('alice', DEV, batch);
    const bucketsBefore = (await db().collection('stepBuckets').get()).docs.map((d) => [d.id, JSON.stringify(d.data())]);
    const sumBefore = JSON.stringify(await getDoc(`dailyStepSummaries/alice_${DAY_KEY}`));
    const r = await sync('alice', DEV, batch);
    expect(r).toMatchObject({ accepted: 0, duplicates: 6, rejected: [], updated: 0 });
    expect(r.today.verifiedSteps).toBe(120);
    expect((await db().collection('stepBuckets').get()).docs.map((d) => [d.id, JSON.stringify(d.data())])).toEqual(bucketsBefore);
    expect(JSON.stringify(await getDoc(`dailyStepSummaries/alice_${DAY_KEY}`))).toBe(sumBefore);
  });

  test('duplicates inside a single batch count once', async () => {
    const first = alignedBefore(T0, 3_600_000);
    const b = mkBucket({ startMs: first });
    const r = await sync('alice', DEV, [b, b, { ...b }]);
    expect(r).toMatchObject({ accepted: 1, duplicates: 2 });
    expect((await db().collection('stepBuckets').get()).size).toBe(1);
  });

  test('overlapping batches: only the new buckets are accepted', async () => {
    const first = alignedBefore(T0, 3_600_000);
    await sync('alice', DEV, walkBuckets(first, 3, 20));
    const r = await sync('alice', DEV, walkBuckets(first, 6, 20));
    expect(r).toMatchObject({ accepted: 3, duplicates: 3 });
    expect(r.today.verifiedSteps).toBe(120);
  });

  test('buckets on either side of IST midnight land in different day summaries', async () => {
    const midnight = Date.UTC(2026, 2, 1, 18, 30); // IST 2026-03-02 00:00
    await sync('alice', DEV, [mkBucket({ startMs: midnight - 10_000, raw: 11 }), mkBucket({ startMs: midnight, raw: 22 })]);
    expect(await getDoc('dailyStepSummaries/alice_20260301')).toMatchObject({ verifiedSteps: 11 });
    expect(await getDoc('dailyStepSummaries/alice_20260302')).toMatchObject({ verifiedSteps: 22 });
  });

  test('an empty batch is fine', async () => {
    const r = await sync('alice', DEV, []);
    expect(r).toMatchObject({ accepted: 0, duplicates: 0, rejected: [], updated: 0 });
  });
});

describe('syncStepBuckets: server-side hard limits (rejected buckets are returned so the client can ack them)', () => {
  test('over-cadence (50 in 10 s): stored as REJECTED CADENCE_EXCEEDED, no credit, risk event opened, returned in rejected[]', async () => {
    const s = alignedBefore(T0, 600_000);
    const r = await sync('alice', DEV, [mkBucket({ startMs: s, raw: 50, credited: 50, hops: uniformHops('WALK', 20) })]);
    expect(r.accepted).toBe(0);
    expect(r.rejected).toEqual([{ startMs: s, reason: 'CADENCE_EXCEEDED' }]);
    expect(await getDoc(id(s))).toMatchObject({ state: 'REJECTED', reason: 'CADENCE_EXCEEDED', serverCredited: 0, rewardEligible: false, rawDelta: 50 });
    expect(r.today).toMatchObject({ verifiedSteps: 0, rawSteps: 50, rejectedSteps: 50 });
    expect(await getDoc(`riskEvents/alice_HARD_LIMIT_${DAY_KEY}`)).toMatchObject({ uid: 'alice', kind: 'HARD_LIMIT', status: 'OPEN' });
    // A retry of the same bucket is a duplicate no-op.
    expect((await sync('alice', DEV, [mkBucket({ startMs: s, raw: 50, credited: 50, hops: uniformHops('WALK', 20) })])).duplicates).toBe(1);
  });

  test('a bucket older than 72 h is rejected TOO_OLD and not stored', async () => {
    const old = alignedBefore(T0, 73 * 3_600_000);
    const r = await sync('alice', DEV, [mkBucket({ startMs: old })]);
    expect(r.rejected).toEqual([{ startMs: old, reason: 'TOO_OLD' }]);
    expect(await getDoc(id(old))).toBeUndefined();
    expect(r.accepted).toBe(0);
  });

  test('bucket inside the 72 h window (71 h) is accepted', async () => {
    const s = alignedBefore(T0, 71 * 3_600_000);
    expect((await sync('alice', DEV, [mkBucket({ startMs: s })])).accepted).toBe(1);
  });

  test('future (> 120 s) and misaligned buckets are rejected and flagged; nothing stored', async () => {
    const future = Math.ceil((T0 + 300_000) / 10_000) * 10_000;
    const aligned = alignedBefore(T0, 100_000);
    const r = await sync('alice', DEV, [mkBucket({ startMs: future }), mkBucket({ startMs: aligned + 5 })]);
    expect(r.rejected).toEqual(expect.arrayContaining([{ startMs: future, reason: 'FUTURE_BUCKET' }, { startMs: aligned + 5, reason: 'BAD_ALIGNMENT' }]));
    expect((await db().collection('stepBuckets').get()).size).toBe(0);
    expect(await getDoc(`riskEvents/alice_HARD_LIMIT_${DAY_KEY}`)).toMatchObject({ kind: 'HARD_LIMIT' });
  });

  test('malformed buckets are rejected individually without failing the whole call', async () => {
    const s = alignedBefore(T0, 100_000);
    const r = await sync('alice', DEV, [{ nonsense: true }, mkBucket({ startMs: s }), { ...mkBucket({ startMs: s + 10_000 }), state: 'BOGUS' }]);
    expect(r.accepted).toBe(1);
    expect(r.rejected.map((x) => x.reason)).toEqual(['MALFORMED', 'MALFORMED']);
  });

  test('shake hops claimed as VERIFIED are rejected by the server (SHAKE_PATTERN, no credit), DOWNGRADE risk event', async () => {
    const s = alignedBefore(T0, 600_000);
    const r = await sync('alice', DEV, [mkBucket({ startMs: s, raw: 26, credited: 26, hops: uniformHops('SHAKE', 0) })]);
    expect(r.accepted).toBe(0);
    expect(r.rejected).toEqual([{ startMs: s, reason: 'SHAKE_PATTERN' }]);
    expect(await getDoc(id(s))).toMatchObject({ state: 'REJECTED', reason: 'SHAKE_PATTERN', serverCredited: 0, clientCredited: 26, rewardEligible: false });
    expect(r.today).toMatchObject({ verifiedSteps: 0, rawSteps: 26, rejectedSteps: 26 });
    expect(await getDoc(`riskEvents/alice_DOWNGRADE_${DAY_KEY}`)).toMatchObject({ kind: 'DOWNGRADE' });
  });

  test('over-claim is downgraded to the IMU-supported value (24 claimed, 12 supported), never raised', async () => {
    const s = alignedBefore(T0, 600_000);
    const hops = [...uniformHops('WALK', 3.6, 3), ...uniformHops('SHAKE', 0, 2)];
    const r = await sync('alice', DEV, [mkBucket({ startMs: s, raw: 24, credited: 24, hops })]);
    expect(r).toMatchObject({ accepted: 1, downgraded: 1 });
    const b = await getDoc(id(s));
    expect(b).toMatchObject({ rawDelta: 24, clientCredited: 24, serverCredited: 12, recomputedCredited: 12, state: 'PARTIAL', reason: 'EXCESS_OVER_IMU' });
    expect(b?.flags).toContain('DOWNGRADED');
    expect(r.today.verifiedSteps).toBe(12);
  });

  test('credited greater than raw is clamped and flagged', async () => {
    const s = alignedBefore(T0, 600_000);
    await sync('alice', DEV, [mkBucket({ startMs: s, raw: 10, credited: 500, hops: uniformHops('WALK', 5) })]);
    const b = await getDoc(id(s));
    expect(b).toMatchObject({ rawDelta: 10, clientCredited: 10, claimedCredited: 500, serverCredited: 10 });
    expect(b?.flags).toContain('CREDIT_GT_RAW');
  });

  test('client-REJECTED and UNWITNESSED buckets are stored but never upgraded', async () => {
    const s = alignedBefore(T0, 600_000);
    const r = await sync('alice', DEV, [
      mkBucket({ startMs: s, raw: 15, credited: 0, state: 'REJECTED', reason: 'VEHICLE_MOTION' }),
      mkBucket({ startMs: s + 10_000, raw: 12, credited: 0, state: 'UNWITNESSED', reason: 'NO_IMU_EVIDENCE', hops: [] }),
    ]);
    expect(r.accepted).toBe(0);
    expect(r.today).toMatchObject({ verifiedSteps: 0, rawSteps: 27, rejectedSteps: 15, unwitnessedSteps: 12 });
  });

  test('daily reward cap: 21,000 steps across three syncs => exactly 20,000 verified, excess stored but not reward eligible', async () => {
    const first = Date.UTC(2026, 2, 1, 18, 30) + 60_000; // IST 00:01 on the 2nd
    const all = Array.from({ length: 600 }, (_, i) => mkBucket({ startMs: first + i * 10_000, raw: 35, credited: 35, hops: uniformHops('RUN', 9) }));
    for (let i = 0; i < 600; i += 200) await sync('alice', DEV, all.slice(i, i + 200));
    const sum = await getDoc(`dailyStepSummaries/alice_${DAY_KEY}`);
    expect(sum?.verifiedSteps).toBe(20_000);
    expect(sum?.rawSteps).toBe(21_000);
    const docs = (await db().collection('stepBuckets').get()).docs.map((d) => d.data());
    expect(docs).toHaveLength(600);
    expect(docs.filter((d) => d.rewardEligible).reduce((s, d) => s + d.serverCredited, 0)).toBe(20_000);
    expect(docs.some((d) => d.reason === 'DAILY_CAP' && d.rewardEligible === false)).toBe(true);
    expect(await getDoc(`riskEvents/alice_DAILY_CAP_${DAY_KEY}`)).toMatchObject({ kind: 'DAILY_CAP' });
  });

  test('over-cadence late-night farming is bounded: a real 30-minute run at 180 steps/min is NOT clipped', async () => {
    const first = alignedBefore(T0, 4 * 3_600_000);
    const r = await sync('alice', DEV, Array.from({ length: 180 }, (_, i) => mkBucket({ startMs: first + i * 10_000, raw: 30, hops: uniformHops('RUN', 8) })));
    expect(r.accepted).toBe(180);
    expect(r.today.verifiedSteps).toBe(5400);
  });
});

describe('syncStepBuckets: device rules', () => {
  test('a non-reward device stores buckets (display only): not reward eligible, verified stays 0', async () => {
    const r2 = await handleRegisterDevice(authReq('alice', { deviceId: 'alice-device-2', model: 'Old phone', appVersion: '1.0.0' }));
    expect(r2.isRewardDevice).toBe(false);
    const s = alignedBefore(T0, 600_000);
    const r = await sync('alice', 'alice-device-2', [mkBucket({ startMs: s, raw: 20 })]);
    expect(r.accepted).toBe(1);
    expect(r.today).toMatchObject({ verifiedSteps: 0, rawSteps: 20 });
    expect(await getDoc(id(s, 'alice-device-2'))).toMatchObject({ rewardEligible: false, serverCredited: 20, state: 'VERIFIED' });
  });

  test('syncing from an unregistered device is rejected', async () => {
    await expectError(sync('alice', 'never-registered-device', [mkBucket({ startMs: alignedBefore(T0, 100_000) })]), 'failed-precondition', 'DEVICE_NOT_REGISTERED');
  });

  test.each([
    ['201 buckets', { deviceId: DEV, buckets: Array.from({ length: 201 }, (_, i) => mkBucket({ startMs: i * 10_000 })) }, 'TOO_MANY_BUCKETS'],
    ['buckets not an array', { deviceId: DEV, buckets: 'x' }, 'INVALID_BUCKETS'],
    ['bad device id', { deviceId: 'x', buckets: [] }, 'INVALID_DEVICE_ID'],
  ])('input validation: %s', async (_n, payload, reason) => {
    await expectError(handleSyncStepBuckets(authReq('alice', payload)), 'invalid-argument', reason);
  });

  test('wrong domain, unverified, missing profile and suspended callers are rejected', async () => {
    const payload = { deviceId: DEV, buckets: [] };
    await expectError(handleSyncStepBuckets(authReq('alice', payload, { email: 'alice@gmail.com' })), 'permission-denied', 'INVALID_EMAIL_DOMAIN');
    await expectError(handleSyncStepBuckets(authReq('alice', payload, { verified: false })), 'permission-denied', 'EMAIL_NOT_VERIFIED');
    await expectError(handleSyncStepBuckets(authReq('nobody', payload)), 'failed-precondition', 'PROFILE_REQUIRED');
    await db().collection('users').doc('alice').update({ status: 'SUSPENDED' });
    await expectError(handleSyncStepBuckets(authReq('alice', payload)), 'permission-denied', 'ACCOUNT_SUSPENDED');
  });
});

describe('syncStepBuckets: idempotent day summary and invariants', () => {
  test('recomputeDailySummary reproduces the summary and a second run changes nothing; it also repairs a corrupted summary', async () => {
    const first = alignedBefore(T0, 3_600_000);
    await sync('alice', DEV, walkBuckets(first, 5, 20));
    const before = await getDoc(`dailyStepSummaries/alice_${DAY_KEY}`);
    expect((await recomputeDailySummary('alice', DAY_KEY)).changed).toBe(false);
    await db().collection('dailyStepSummaries').doc(`alice_${DAY_KEY}`).update({ verifiedSteps: 999_999 });
    expect((await recomputeDailySummary('alice', DAY_KEY)).changed).toBe(true);
    expect((await getDoc(`dailyStepSummaries/alice_${DAY_KEY}`))?.verifiedSteps).toBe(before?.verifiedSteps);
    expect((await recomputeDailySummary('alice', DAY_KEY)).changed).toBe(false);
  });

  test('summary is the sum over STORED buckets (not blind increments) when syncs interleave', async () => {
    const first = alignedBefore(T0, 3_600_000);
    await sync('alice', DEV, walkBuckets(first, 4, 10));
    await sync('alice', DEV, walkBuckets(first + 100_000, 4, 15));
    await sync('alice', DEV, walkBuckets(first, 8, 10).slice(0, 4)); // pure duplicates
    expect((await getDoc(`dailyStepSummaries/alice_${DAY_KEY}`))?.verifiedSteps).toBe(40 + 60);
  });

  test('random batches: serverCredited <= clientCredited <= rawDelta for every stored bucket; rewardEligible implies credit', async () => {
    let seed = 42;
    const rnd = () => {
      seed = (seed * 1664525 + 1013904223) % 4294967296;
      return seed / 4294967296;
    };
    const labels = ['WALK', 'RUN', 'SHAKE', 'VEHICLE', 'STILL', 'UNKNOWN'] as const;
    const first = alignedBefore(T0, 5 * 3_600_000);
    const batch = Array.from({ length: 150 }, (_, i) =>
      mkBucket({
        startMs: first + i * 10_000,
        raw: 1 + Math.floor(rnd() * 45),
        credited: Math.floor(rnd() * 60),
        state: (['VERIFIED', 'PARTIAL', 'REJECTED', 'UNWITNESSED'] as const)[Math.floor(rnd() * 4)],
        hops: Array.from({ length: 3 + Math.floor(rnd() * 3) }, () => ({ label: labels[Math.floor(rnd() * 6)], imuSteps: Math.round(rnd() * 80) / 10 })),
      }),
    );
    await sync('alice', DEV, batch);
    const docs = (await db().collection('stepBuckets').get()).docs.map((d) => d.data());
    expect(docs.length).toBeGreaterThan(100);
    for (const d of docs) {
      expect(d.serverCredited).toBeLessThanOrEqual(d.clientCredited);
      expect(d.clientCredited).toBeLessThanOrEqual(d.rawDelta);
      if (d.rewardEligible) expect(d.serverCredited).toBeGreaterThan(0);
    }
    const sum = await getDoc(`dailyStepSummaries/alice_${DAY_KEY}`);
    expect(sum?.verifiedSteps).toBe(docs.filter((d) => d.rewardEligible).reduce((s, d) => s + d.serverCredited, 0));
    expect(sum?.verifiedSteps).toBeLessThanOrEqual(sum?.rawSteps);
  });
});

describe('syncStepBuckets: late step-counter events on an already-settled bucket (lateRawAdded / lateCreditedAdded)', () => {
  const s0 = () => alignedBefore(T0, 1_200_000);

  test('a bucket with a late part is stored with both late fields', async () => {
    const s = s0();
    await sync('alice', DEV, [{ ...mkBucket({ startMs: s, raw: 20 }), lateRawAdded: 4, lateCreditedAdded: 4 }]);
    expect(await getDoc(id(s))).toMatchObject({ rawDelta: 20, lateRawAdded: 4, lateCreditedAdded: 4 });
  });

  test('a greater cumulative lateRawAdded UPDATES the stored bucket within limits and is reported as accepted (not duplicate)', async () => {
    const s = s0();
    await sync('alice', DEV, [mkBucket({ startMs: s, raw: 20 })]);
    const r = await sync('alice', DEV, [{ ...mkBucket({ startMs: s, raw: 30, hops: uniformHops('WALK', 8) }), lateRawAdded: 10, lateCreditedAdded: 10 }]);
    expect(r).toMatchObject({ accepted: 1, duplicates: 0, updated: 1, rejected: [] });
    expect(r.today).toMatchObject({ verifiedSteps: 30, rawSteps: 30 });
    const b = await getDoc(id(s));
    expect(b).toMatchObject({ rawDelta: 30, clientCredited: 30, serverCredited: 30, state: 'VERIFIED', rewardEligible: true, lateRawAdded: 10, lateCreditedAdded: 10 });
    expect(b?.flags).toContain('LATE_UPDATED');
    expect((await db().collection('stepBuckets').get()).size).toBe(1);
    expect(await getDoc(`dailyStepSummaries/alice_${DAY_KEY}`)).toMatchObject({ verifiedSteps: 30, rawSteps: 30 });
  });

  test('a late update is still downgraded by the server when the evidence does not support the claim', async () => {
    const s = s0();
    await sync('alice', DEV, [mkBucket({ startMs: s, raw: 20, hops: uniformHops('WALK', 3.6) })]); // allowed 20
    // raw 30 claimed 30, but IMU supports floor(1.15*18)=20 only
    const r = await sync('alice', DEV, [{ ...mkBucket({ startMs: s, raw: 30, hops: uniformHops('WALK', 3.6) }), lateRawAdded: 10, lateCreditedAdded: 10 }]);
    expect(r).toMatchObject({ accepted: 1, updated: 1, downgraded: 1 });
    expect(await getDoc(id(s))).toMatchObject({ rawDelta: 30, clientCredited: 30, serverCredited: 20, state: 'PARTIAL' });
    expect((await getDoc(`dailyStepSummaries/alice_${DAY_KEY}`))?.verifiedSteps).toBe(20);
  });

  test('equal or lower late values are plain duplicates: the doc and the summary are untouched', async () => {
    const s = s0();
    await sync('alice', DEV, [{ ...mkBucket({ startMs: s, raw: 30, hops: uniformHops('WALK', 8) }), lateRawAdded: 10, lateCreditedAdded: 10 }]);
    const before = JSON.stringify(await getDoc(id(s)));
    const sumBefore = JSON.stringify(await getDoc(`dailyStepSummaries/alice_${DAY_KEY}`));
    for (const late of [10, 3, 0]) {
      const r = await sync('alice', DEV, [{ ...mkBucket({ startMs: s, raw: 35, credited: 35, hops: uniformHops('WALK', 9) }), lateRawAdded: late, lateCreditedAdded: late }]);
      expect(r).toMatchObject({ accepted: 0, duplicates: 1, updated: 0, rejected: [] });
    }
    expect(JSON.stringify(await getDoc(id(s)))).toBe(before);
    expect(JSON.stringify(await getDoc(`dailyStepSummaries/alice_${DAY_KEY}`))).toBe(sumBefore);
  });

  test('an over-limit late update (raw would exceed 35) is rejected and leaves the old doc unchanged', async () => {
    const s = s0();
    await sync('alice', DEV, [mkBucket({ startMs: s, raw: 30, hops: uniformHops('WALK', 8) })]);
    const before = JSON.stringify(await getDoc(id(s)));
    const sumBefore = JSON.stringify(await getDoc(`dailyStepSummaries/alice_${DAY_KEY}`));
    const r = await sync('alice', DEV, [{ ...mkBucket({ startMs: s, raw: 41, credited: 41, hops: uniformHops('WALK', 12) }), lateRawAdded: 11, lateCreditedAdded: 11 }]);
    expect(r.accepted).toBe(0);
    expect(r.updated).toBe(0);
    expect(r.rejected).toEqual([{ startMs: s, reason: 'CADENCE_EXCEEDED' }]);
    expect(JSON.stringify(await getDoc(id(s)))).toBe(before);
    expect(JSON.stringify(await getDoc(`dailyStepSummaries/alice_${DAY_KEY}`))).toBe(sumBefore);
    expect(await getDoc(`riskEvents/alice_HARD_LIMIT_${DAY_KEY}`)).toMatchObject({ kind: 'HARD_LIMIT' });
  });

  test('a re-send can never lower the stored serverCredited', async () => {
    const s = s0();
    await sync('alice', DEV, [mkBucket({ startMs: s, raw: 28, hops: uniformHops('WALK', 8) })]);
    const r = await sync('alice', DEV, [{ ...mkBucket({ startMs: s, raw: 30, credited: 22, hops: uniformHops('WALK', 8) }), lateRawAdded: 2, lateCreditedAdded: 0 }]);
    expect(r.rejected).toEqual([{ startMs: s, reason: 'LATE_UPDATE_LOWERS_CREDIT' }]);
    expect(await getDoc(id(s))).toMatchObject({ rawDelta: 28, serverCredited: 28 });
  });

  test('the daily reward cap is re-applied on a late update', async () => {
    const first = Date.UTC(2026, 2, 1, 18, 30) + 60_000;
    const full = Array.from({ length: 571 }, (_, i) => mkBucket({ startMs: first + i * 10_000, raw: 35, hops: uniformHops('RUN', 9) }));
    const last = first + 571 * 10_000;
    for (let i = 0; i < full.length; i += 200) await sync('alice', DEV, full.slice(i, i + 200));
    expect((await getDoc(`dailyStepSummaries/alice_${DAY_KEY}`))?.verifiedSteps).toBe(19_985);
    await sync('alice', DEV, [mkBucket({ startMs: last, raw: 10, hops: uniformHops('RUN', 9) })]); // 19,995
    const r = await sync('alice', DEV, [{ ...mkBucket({ startMs: last, raw: 30, hops: uniformHops('RUN', 9) }), lateRawAdded: 20, lateCreditedAdded: 20 }]);
    expect(r.updated).toBe(1);
    expect((await getDoc(id(last)))?.serverCredited).toBe(15); // only 15 left under 20,000
    expect((await getDoc(`dailyStepSummaries/alice_${DAY_KEY}`))?.verifiedSteps).toBe(20_000);
  });

  test('late updates on a too-old bucket are rejected', async () => {
    const s = alignedBefore(T0, 71 * 3_600_000);
    await sync('alice', DEV, [mkBucket({ startMs: s, raw: 20 })]);
    setClock(T0 + 3 * 3_600_000); // now the bucket is > 72 h old
    const r = await sync('alice', DEV, [{ ...mkBucket({ startMs: s, raw: 30, hops: uniformHops('WALK', 8) }), lateRawAdded: 10, lateCreditedAdded: 10 }]);
    expect(r.rejected).toEqual([{ startMs: s, reason: 'TOO_OLD' }]);
    expect((await getDoc(id(s)))?.rawDelta).toBe(20);
  });
});
