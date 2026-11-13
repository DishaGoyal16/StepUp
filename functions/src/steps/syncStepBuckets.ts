import { COL, SYNC_MAX_BUCKETS } from '../config';
import { Req, requireEligibleUser } from '../lib/auth';
import { nowMs } from '../lib/clock';
import { fail } from '../lib/errors';
import { db, FieldValue, tsFromMs } from '../lib/firebase';
import { getSettings } from '../lib/settings';
import { dayKeyOf } from '../lib/time';
import { asRecord, str } from '../lib/validate';
import { bucketDocId, summaryDocId, toLite } from './summaries';
import {
  BucketInput,
  BucketOut,
  decideLateUpdate,
  ExistingEligible,
  Limits,
  parseBucket,
  summarizeDay,
  validateBatch,
  RejectedBucket,
} from './validateBatch';

export const DEVICE_ID_PATTERN = /^[A-Za-z0-9_-]{8,64}$/;

export interface SyncResult {
  /** New buckets stored with VERIFIED/PARTIAL state, plus late-event updates that ended VERIFIED/PARTIAL. */
  accepted: number;
  /** Buckets already stored (equal or lower lateRawAdded): no-ops. */
  duplicates: number;
  /** Permanently rejected buckets (too old, invalid, over limit, ...) and buckets stored as REJECTED/UNWITNESSED. The client acks these. */
  rejected: RejectedBucket[];
  downgraded: number;
  /** Late-event updates applied to already-stored buckets (counted inside accepted/rejected as well). */
  updated: number;
  today: { verifiedSteps: number; rawSteps: number; rejectedSteps: number; unwitnessedSteps: number };
}

type RiskKind = 'HARD_LIMIT' | 'DAILY_CAP' | 'DOWNGRADE' | 'MANY_REJECTIONS';
interface RiskAgg {
  kind: RiskKind;
  count: number;
  examples: Array<Record<string, unknown>>;
}

type EligibleRef = ExistingEligible & { id: string };

/** syncStepBuckets: re-validates every bucket server-side (downgrade only), stores idempotently, recomputes summaries. */
export async function handleSyncStepBuckets(req: Req): Promise<SyncResult> {
  const caller = await requireEligibleUser(req);
  const uid = caller.uid;
  const data = asRecord(req.data);
  const deviceId = str(data, 'deviceId', { min: 8, max: 64, pattern: DEVICE_ID_PATTERN });
  const rawBuckets = data.buckets;
  if (!Array.isArray(rawBuckets)) fail('invalid-argument', 'INVALID_BUCKETS');
  if (rawBuckets.length > SYNC_MAX_BUCKETS) fail('invalid-argument', 'TOO_MANY_BUCKETS', `at most ${SYNC_MAX_BUCKETS} buckets per call`);

  const settings = await getSettings();
  const limits: Limits = {
    bucketMs: 10_000,
    maxStepsPerBucket: settings.maxStepsPerBucket,
    maxBackfillMs: settings.maxBucketAgeHours * 3_600_000,
    maxFutureMs: settings.futureToleranceSec * 1000,
    dailyRewardCap: settings.maxRewardStepsPerDay,
    rolling30MinCap: settings.maxStepsPer30Min,
  };
  const now = nowMs();
  const today = dayKeyOf(now);

  // Structural parse + in-batch dedupe (pure) to learn candidate doc ids and days.
  const preRejected: RejectedBucket[] = [];
  const candidates = new Map<number, BucketInput>(); // startMs -> parsed bucket
  let inBatchDuplicates = 0;
  for (const raw of rawBuckets) {
    const p = parseBucket(raw);
    if (!p.ok) {
      preRejected.push({ startMs: p.startMs, reason: p.reason });
      continue;
    }
    const prev = candidates.get(p.bucket.startMs);
    if (prev) {
      inBatchDuplicates++;
      // Same startMs twice in one batch: keep the one with the larger cumulative late part.
      if ((p.bucket.lateRawAdded ?? 0) > (prev.lateRawAdded ?? 0)) candidates.set(p.bucket.startMs, p.bucket);
      continue;
    }
    candidates.set(p.bucket.startMs, p.bucket);
  }

  const firestore = db();
  const result = await firestore.runTransaction(async (tx) => {
    const userRef = firestore.collection(COL.users).doc(uid);
    const deviceRef = userRef.collection(COL.devices).doc(deviceId);
    const [userSnap, deviceSnap] = await tx.getAll(userRef, deviceRef);
    if (!deviceSnap.exists) fail('failed-precondition', 'DEVICE_NOT_REGISTERED', 'register this device first');
    const userData = userSnap.data() as FirebaseFirestore.DocumentData;
    const isRewardDevice = userData.rewardDeviceId === deviceId;

    const startList = [...candidates.keys()];
    const bucketRefs = startList.map((s) => firestore.collection(COL.stepBuckets).doc(bucketDocId(uid, deviceId, s)));
    const existingSnaps = bucketRefs.length ? await tx.getAll(...bucketRefs) : [];
    let duplicates = inBatchDuplicates;
    const newBuckets: BucketInput[] = [];
    const lateCandidates: Array<{ b: BucketInput; snap: FirebaseFirestore.DocumentSnapshot }> = [];
    existingSnaps.forEach((snap, i) => {
      const b = candidates.get(startList[i]) as BucketInput;
      if (!snap.exists) newBuckets.push(b);
      // Existing deterministic doc: a strictly greater CUMULATIVE lateRawAdded is a late-event update; else a duplicate.
      else if ((b.lateRawAdded ?? 0) > Number(snap.data()?.lateRawAdded ?? 0)) lateCandidates.push({ b, snap });
      else duplicates++;
    });

    // Days touched by new + late-updated buckets (only plausible ones; the age window bounds this to a few days).
    const days = new Set<string>();
    for (const b of [...newBuckets, ...lateCandidates.map((l) => l.b)]) {
      if (b.startMs >= now - limits.maxBackfillMs && b.startMs <= now + limits.maxFutureMs) days.add(dayKeyOf(b.startMs));
    }
    const dayBuckets = new Map<string, Array<{ id: string; data: FirebaseFirestore.DocumentData }>>();
    for (const day of days) {
      const q = await tx.get(firestore.collection(COL.stepBuckets).where('uid', '==', uid).where('dayKey', '==', day));
      dayBuckets.set(day, q.docs.map((d) => ({ id: d.id, data: d.data() })));
    }
    const eligible: EligibleRef[] = [];
    for (const list of dayBuckets.values()) {
      for (const { id, data: b } of list) {
        if (b.rewardEligible === true && Number(b.serverCredited) > 0) {
          eligible.push({ id, startMs: Number(b.startMs), serverCredited: Number(b.serverCredited) });
        }
      }
    }

    const validation = validateBatch(newBuckets, { nowMs: now, isRewardDevice, limits, existing: eligible });
    const stored = validation.stored;

    // Late-event updates: re-validate each against everything else; never lowers the stored credit.
    const updates: Array<{ out: BucketOut; ref: FirebaseFirestore.DocumentReference }> = [];
    const lateRejected: RejectedBucket[] = [];
    const running: EligibleRef[] = [
      ...eligible,
      ...stored
        .filter((o) => o.rewardEligible)
        .map((o) => ({ id: bucketDocId(uid, deviceId, o.startMs), startMs: o.startMs, serverCredited: o.serverCredited })),
    ];
    for (const lc of lateCandidates) {
      const old = lc.snap.data() as FirebaseFirestore.DocumentData;
      const decision = decideLateUpdate(
        lc.b,
        { rawDelta: Number(old.rawDelta), serverCredited: Number(old.serverCredited), lateRawAdded: Number(old.lateRawAdded ?? 0) },
        { nowMs: now, isRewardDevice, limits, existing: running.filter((r) => r.id !== lc.snap.id) },
      );
      if (decision.kind === 'DUPLICATE') {
        duplicates++;
      } else if (decision.kind === 'REJECT') {
        lateRejected.push({ startMs: lc.b.startMs, reason: decision.reason });
      } else {
        updates.push({ out: decision.out, ref: lc.snap.ref });
        const i = running.findIndex((r) => r.id === lc.snap.id);
        if (i >= 0) running.splice(i, 1);
        if (decision.out.rewardEligible) {
          running.push({ id: lc.snap.id, startMs: decision.out.startMs, serverCredited: decision.out.serverCredited });
        }
      }
    }

    // Aggregate risk events (read-before-write).
    const touched = [...stored, ...updates.map((u) => u.out)];
    const risks = collectRisks(touched, [...validation.rejected, ...preRejected, ...lateRejected]);
    const riskRefs = risks.map((r) => firestore.collection(COL.riskEvents).doc(`${uid}_${r.kind}_${today}`));
    const riskSnaps = riskRefs.length ? await tx.getAll(...riskRefs) : [];

    // ---- writes ----
    for (const o of stored) {
      tx.create(firestore.collection(COL.stepBuckets).doc(bucketDocId(uid, deviceId, o.startMs)), bucketDoc(uid, deviceId, o));
    }
    for (const u of updates) {
      const fields = bucketDoc(uid, deviceId, u.out);
      // identity + first-receipt fields are immutable
      for (const k of ['uid', 'deviceId', 'startMs', 'startAt', 'receivedAt']) delete fields[k];
      tx.update(u.ref, { ...fields, lateUpdatedAt: FieldValue.serverTimestamp() });
    }
    const changedDays = new Set([...stored.map((o) => o.dayKey), ...updates.map((u) => u.out.dayKey)]);
    for (const day of changedDays) {
      const replaced = new Map(updates.filter((u) => u.out.dayKey === day).map((u) => [u.ref.id, toLite(u.out)]));
      const lites = [
        ...(dayBuckets.get(day) ?? []).map((d) => replaced.get(d.id) ?? toLite(d.data)),
        ...stored.filter((o) => o.dayKey === day).map(toLite),
      ];
      const sum = summarizeDay(lites);
      tx.set(firestore.collection(COL.dailyStepSummaries).doc(summaryDocId(uid, day)), {
        uid,
        dayKey: day,
        hostelId: (userData.hostelId as string | null) ?? null,
        ...sum,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    risks.forEach((r, i) => {
      const snap = riskSnaps[i];
      if (snap.exists) {
        tx.update(riskRefs[i], {
          'detail.count': FieldValue.increment(r.count),
          'detail.lastExamples': r.examples,
          updatedAt: FieldValue.serverTimestamp(),
        });
      } else {
        tx.create(riskRefs[i], {
          uid,
          kind: r.kind,
          detail: { count: r.count, lastExamples: r.examples, deviceId },
          status: 'OPEN',
          dayKey: today,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    });
    tx.update(deviceRef, { lastSeenAt: FieldValue.serverTimestamp(), lastSeq: FieldValue.increment(1) });

    const credited = touched.filter((o) => o.state === 'VERIFIED' || o.state === 'PARTIAL');
    const notCredited = touched.filter((o) => o.state === 'REJECTED' || o.state === 'UNWITNESSED');
    const rejected: RejectedBucket[] = [
      ...preRejected,
      ...lateRejected,
      ...validation.rejected.filter((r) => !notCredited.some((o) => o.startMs === r.startMs)),
      ...notCredited.map((o) => ({ startMs: o.startMs, reason: o.reason ?? o.state })),
    ];
    return {
      accepted: credited.length,
      duplicates,
      rejected: dedupeRejected(rejected),
      downgraded: touched.filter((o) => o.flags.includes('DOWNGRADED')).length,
      updated: updates.length,
    };
  });

  const todaySnap = await firestore.collection(COL.dailyStepSummaries).doc(summaryDocId(uid, today)).get();
  const t = todaySnap.data();
  return {
    ...result,
    today: {
      verifiedSteps: Number(t?.verifiedSteps ?? 0),
      rawSteps: Number(t?.rawSteps ?? 0),
      rejectedSteps: Number(t?.rejectedSteps ?? 0),
      unwitnessedSteps: Number(t?.unwitnessedSteps ?? 0),
    },
  };
}

function dedupeRejected(list: RejectedBucket[]): RejectedBucket[] {
  const seen = new Set<string>();
  const out: RejectedBucket[] = [];
  for (const r of list) {
    const k = `${r.startMs}|${r.reason}`;
    if (!seen.has(k)) {
      seen.add(k);
      out.push(r);
    }
  }
  return out;
}

function bucketDoc(uid: string, deviceId: string, o: BucketOut): Record<string, unknown> {
  return {
    uid,
    deviceId,
    startMs: o.startMs,
    bootCount: o.bootCount,
    rawDelta: o.rawDelta,
    clientCredited: o.clientCredited,
    claimedCredited: o.claimedCredited,
    recomputedCredited: o.recomputedCredited,
    serverCredited: o.serverCredited,
    state: o.state,
    reason: o.reason,
    flags: o.flags,
    evidenceMode: o.evidenceMode,
    carryMode: o.carryMode,
    walkFraction: o.walkFraction,
    hops: o.hops,
    dayKey: o.dayKey,
    rewardEligible: o.rewardEligible,
    lateRawAdded: o.lateRawAdded,
    lateCreditedAdded: o.lateCreditedAdded,
    receivedAt: FieldValue.serverTimestamp(),
    startAt: tsFromMs(o.startMs),
  };
}

const HARD_LIMIT_REASONS = new Set(['BAD_ALIGNMENT', 'FUTURE_BUCKET', 'CADENCE_EXCEEDED']);

function collectRisks(stored: BucketOut[], rejected: RejectedBucket[]): RiskAgg[] {
  const out: RiskAgg[] = [];
  const add = (kind: RiskKind, example: Record<string, unknown>) => {
    let a = out.find((x) => x.kind === kind);
    if (!a) {
      a = { kind, count: 0, examples: [] };
      out.push(a);
    }
    a.count++;
    if (a.examples.length < 5) a.examples.push(example);
  };
  const hard = new Set<string>();
  for (const r of rejected) {
    if (HARD_LIMIT_REASONS.has(r.reason) && !hard.has(`${r.startMs}|${r.reason}`)) {
      hard.add(`${r.startMs}|${r.reason}`);
      add('HARD_LIMIT', { startMs: r.startMs, reason: r.reason });
    }
  }
  for (const o of stored) {
    if (o.flags.includes('DAILY_CAP')) add('DAILY_CAP', { startMs: o.startMs, dayKey: o.dayKey });
    if (o.flags.includes('DOWNGRADED') && o.claimedCredited > 0) {
      add('DOWNGRADE', { startMs: o.startMs, claimed: o.claimedCredited, server: o.serverCredited, raw: o.rawDelta });
    }
  }
  if (stored.length >= 20) {
    const suspicious = stored.filter(
      (o) => o.state === 'REJECTED' && ['SHAKE_PATTERN', 'VEHICLE_MOTION', 'IN_VEHICLE', 'CADENCE_EXCEEDED'].includes(o.reason ?? ''),
    );
    if (suspicious.length / stored.length > 0.25) {
      for (const o of suspicious) add('MANY_REJECTIONS', { startMs: o.startMs, reason: o.reason });
    }
  }
  return out;
}
