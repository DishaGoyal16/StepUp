/**
 * Shared helpers for emulator integration tests. These run the exported HANDLER logic (the exact functions wrapped
 * by `onCall`) against the Firestore + Auth emulators started by `firebase emulators:exec`.
 */
import { HttpsError } from 'firebase-functions/v2/https';
import { Req } from '../../../src/lib/auth';
import { setClock } from '../../../src/lib/clock';
import { db } from '../../../src/lib/firebase';
import { seedDefaults } from '../../../src/seed';
import { handleCreateProfile, handleRegisterDevice } from '../../../src/profile/profile';
import { handleSyncStepBuckets } from '../../../src/steps/syncStepBuckets';
import { processDailySummary } from '../../../src/triggers/dailySummary';
import { awardPoints } from '../../../src/lib/points';
import { dayKeyOf } from '../../../src/lib/time';
import { Hop } from '../../../src/steps/validateBatch';

export const PROJECT = process.env.GCLOUD_PROJECT || 'demo-stepup';

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error('FIRESTORE_EMULATOR_HOST is not set - run these tests through `npm run test:emulator` (firebase emulators:exec)');
}

export async function clearFirestore(): Promise<void> {
  const host = process.env.FIRESTORE_EMULATOR_HOST as string;
  const res = await fetch(`http://${host}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`clearFirestore failed: ${res.status}`);
  const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  if (authHost) await fetch(`http://${authHost}/emulator/v1/projects/${PROJECT}/accounts`, { method: 'DELETE' });
}

export async function resetAll(): Promise<void> {
  setClock(null);
  await clearFirestore();
  await seedDefaults(db());
}

/** Fixed, midday-IST clock: 2026-03-02 11:30 IST (06:00 UTC). Deterministic day keys. */
export const T0 = Date.UTC(2026, 2, 2, 6, 0, 0);
export const DAY = 86_400_000;
export function freeze(ms = T0): void {
  setClock(ms);
}

export function authReq<T>(uid: string, data: T, opts: { email?: string; verified?: boolean; admin?: boolean } = {}): Req<T> {
  const email = opts.email ?? `${uid}@thapar.edu`;
  const token: Record<string, unknown> = { email, email_verified: opts.verified ?? true };
  if (opts.admin) token.admin = true;
  return { auth: { uid, token }, data };
}

export const noAuthReq = <T>(data: T): Req<T> => ({ auth: null, data });

/** Assert a handler promise rejects with an HttpsError of the given code and `details.reason`. */
export async function expectError(p: Promise<unknown>, code: string, reason?: string): Promise<HttpsError> {
  try {
    await p;
  } catch (e) {
    expect(e).toBeInstanceOf(HttpsError);
    const he = e as HttpsError;
    expect(he.code).toBe(code);
    if (reason) expect((he.details as { reason?: string } | undefined)?.reason).toBe(reason);
    return he;
  }
  throw new Error(`expected rejection with ${code}/${reason ?? '*'} but the call succeeded`);
}

export function profileData(over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    displayName: 'Test Student',
    hostelId: 'agira',
    fitnessLevel: 'INTERMEDIATE',
    sportsInterests: ['Running', 'Cricket'],
    preferredActivity: 'Running',
    preferredTime: 'MORNING',
    goals: ['Stay fit'],
    availability: ['MON', 'WED'],
    buddyType: 'BOTH',
    bio: 'hello',
    dailyGoal: 10_000,
    ...over,
  };
}

/** Create a profile through the real handler. */
export async function makeUser(uid: string, over: Record<string, unknown> = {}): Promise<void> {
  await handleCreateProfile(authReq(uid, profileData({ displayName: `User ${uid}`, ...over })));
}

export async function setReward(uid: string, deviceId = `${uid}-device-1`): Promise<string> {
  const r = await handleRegisterDevice(authReq(uid, { deviceId, model: 'Pixel', appVersion: '1.0.0' }));
  expect(r.isRewardDevice).toBe(true);
  return deviceId;
}

export function uniformHops(label: Hop['label'], imuSteps: number, count = 5): Hop[] {
  return Array.from({ length: count }, () => ({ label, imuSteps }));
}

export interface BucketOpts {
  startMs: number;
  raw?: number;
  credited?: number;
  state?: string;
  reason?: string | null;
  hops?: Hop[];
}

export function mkBucket(o: BucketOpts): Record<string, unknown> {
  const raw = o.raw ?? 20;
  return {
    startMs: o.startMs,
    bootCount: 1,
    rawDelta: raw,
    credited: o.credited ?? raw,
    state: o.state ?? 'VERIFIED',
    reason: o.reason ?? null,
    walkFraction: 1,
    evidenceMode: 'E1',
    carryMode: 'POCKET',
    hops: o.hops ?? uniformHops('WALK', raw / 4),
  };
}

/** n consecutive valid 10 s buckets ending ~ `endBeforeMs` before the frozen now. */
export function walkBuckets(firstStartMs: number, n: number, raw = 20): Array<Record<string, unknown>> {
  return Array.from({ length: n }, (_, i) => mkBucket({ startMs: firstStartMs + i * 10_000, raw }));
}

export function alignedBefore(nowMs: number, msBefore: number): number {
  return Math.floor((nowMs - msBefore) / 10_000) * 10_000;
}

export async function sync(uid: string, deviceId: string, buckets: unknown[]) {
  return handleSyncStepBuckets(authReq(uid, { deviceId, buckets }));
}

/** Write a verified day summary directly (fixture) and run the same derivation the trigger runs. */
export async function giveVerifiedSteps(uid: string, dayKey: string, verified: number, opts: { process?: boolean } = {}): Promise<void> {
  const u = (await db().collection('users').doc(uid).get()).data();
  await db()
    .collection('dailyStepSummaries')
    .doc(`${uid}_${dayKey}`)
    .set({ uid, dayKey, hostelId: u?.hostelId ?? null, rawSteps: verified, verifiedSteps: verified, rejectedSteps: 0, unwitnessedSteps: 0, pendingSteps: 0, updatedAt: new Date() });
  if (opts.process !== false) await processDailySummary(uid, dayKey);
}

export async function givePoints(uid: string, points: number): Promise<void> {
  await awardPoints([
    { uid, type: 'ADJUSTMENT', refType: 'ADMIN', refId: `fixture_${Math.random().toString(36).slice(2)}`, balanceDelta: points, reservedDelta: 0, note: 'test fixture' },
  ]);
}

export async function userDoc(uid: string): Promise<FirebaseFirestore.DocumentData> {
  const s = await db().collection('users').doc(uid).get();
  return s.data() as FirebaseFirestore.DocumentData;
}

export async function getDoc(path: string): Promise<FirebaseFirestore.DocumentData | undefined> {
  return (await db().doc(path).get()).data();
}

export async function ledgerFor(uid: string): Promise<FirebaseFirestore.DocumentData[]> {
  const s = await db().collection('virtualPointsLedger').where('uid', '==', uid).get();
  return s.docs.map((d) => ({ id: d.id, ...d.data() }));
}

export async function makeBuddies(a: string, b: string): Promise<void> {
  const { handleSendBuddyRequest, handleRespondBuddyRequest } = await import('../../../src/buddies/buddies');
  await handleSendBuddyRequest(authReq(a, { toUid: b }));
  await handleRespondBuddyRequest(authReq(b, { requestId: `${a}_${b}`, accept: true }));
}

export const today = (ms: number) => dayKeyOf(ms);
