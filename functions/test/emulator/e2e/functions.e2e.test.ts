/**
 * Real wiring test through the Functions emulator: HTTP callable protocol + Auth emulator tokens + the
 * `beforeUserCreated` blocking function + the `onDailySummaryWritten` Firestore trigger.
 * Run with `npm run test:functions-e2e` (builds first).
 */
import { admin, db } from '../../../src/lib/firebase';
import { seedDefaults } from '../../../src/seed';
import { dayKeyOf } from '../../../src/lib/time';

const PROJECT = process.env.GCLOUD_PROJECT || 'demo-stepup';
const AUTH = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
const FN = `http://${process.env.FUNCTIONS_EMULATOR_HOST || '127.0.0.1:5001'}/${PROJECT}/asia-south1`;

async function authPost(path: string, body: Record<string, unknown>): Promise<{ status: number; json: Record<string, any> }> {
  const res = await fetch(`http://${AUTH}/identitytoolkit.googleapis.com/v1/${path}?key=fake-api-key`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { status: res.status, json: (await res.json()) as Record<string, any> };
}

async function call(name: string, data: unknown, idToken?: string): Promise<{ status: number; json: Record<string, any> }> {
  const res = await fetch(`${FN}/${name}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(idToken ? { authorization: `Bearer ${idToken}` } : {}) },
    body: JSON.stringify({ data }),
  });
  return { status: res.status, json: (await res.json()) as Record<string, any> };
}

jest.setTimeout(120_000);

beforeAll(async () => {
  await seedDefaults(db());
});

describe('Functions emulator end-to-end', () => {
  test('beforeUserCreated blocks non-thapar sign-ups and allows thapar.edu', async () => {
    const bad = await authPost('accounts:signUp', { email: 'intruder@gmail.com', password: 'Passw0rd!', returnSecureToken: true });
    expect(bad.status).toBeGreaterThanOrEqual(400);
    const good = await authPost('accounts:signUp', { email: 'e2e.student@thapar.edu', password: 'Passw0rd!', returnSecureToken: true });
    expect(good.status).toBe(200);
    expect(good.json.idToken).toBeTruthy();
  });

  test('callable protocol: unauthenticated, unverified, then full flow (profile, device, sync) and the Firestore trigger builds the leaderboard', async () => {
    const noAuth = await call('getLeaderboard', { scope: 'CAMPUS', period: 'DAILY' });
    expect(noAuth.json.error?.status).toBe('UNAUTHENTICATED');

    const email = 'flow.student@thapar.edu';
    const up = await authPost('accounts:signUp', { email, password: 'Passw0rd!', returnSecureToken: true });
    expect(up.status).toBe(200);
    const uid = up.json.localId as string;

    const unverified = await call(
      'createProfile',
      { displayName: 'Flow Student', hostelId: 'agira', fitnessLevel: 'BEGINNER' },
      up.json.idToken,
    );
    expect(unverified.json.error?.status).toBe('PERMISSION_DENIED');
    expect(unverified.json.error?.details?.reason).toBe('EMAIL_NOT_VERIFIED');

    await admin.auth().updateUser(uid, { emailVerified: true });
    const signIn = await authPost('accounts:signInWithPassword', { email, password: 'Passw0rd!', returnSecureToken: true });
    const token = signIn.json.idToken as string;

    const created = await call('createProfile', { displayName: 'Flow Student', hostelId: 'agira', fitnessLevel: 'BEGINNER' }, token);
    expect(created.json.result?.ok).toBe(true);
    expect(created.json.result?.created).toBe(true);

    const again = await call('createProfile', { displayName: 'Other', hostelId: 'ira', fitnessLevel: 'BEGINNER' }, token);
    expect(again.json.result?.created).toBe(false);

    const device = await call('registerDevice', { deviceId: 'e2e-device-0001', model: 'Emulator', appVersion: '1.0.0' }, token);
    expect(device.json.result?.isRewardDevice).toBe(true);

    const start = Math.floor((Date.now() - 600_000) / 10_000) * 10_000;
    const buckets = Array.from({ length: 6 }, (_, i) => ({
      startMs: start + i * 10_000,
      bootCount: 1,
      rawDelta: 20,
      credited: 20,
      state: 'VERIFIED',
      reason: null,
      walkFraction: 1,
      evidenceMode: 'E1',
      carryMode: 'POCKET',
      hops: Array.from({ length: 5 }, () => ({ label: 'WALK', imuSteps: 5 })),
    }));
    const sync = await call('syncStepBuckets', { deviceId: 'e2e-device-0001', buckets }, token);
    expect(sync.json.result).toMatchObject({ accepted: 6, duplicates: 0, rejected: [] });

    // Trigger wiring: the daily summary write must produce a campus leaderboard entry (poll up to ~40 s).
    const day = dayKeyOf(start);
    let entry: FirebaseFirestore.DocumentData | undefined;
    for (let i = 0; i < 40 && !entry; i++) {
      const s = await db().collection('leaderboards').doc(`CAMPUS_${day}`).collection('entries').doc(uid).get();
      entry = s.data();
      if (!entry) await new Promise((r) => setTimeout(r, 1000));
    }
    expect(entry).toMatchObject({ uid, verifiedSteps: 120 });

    const board = await call('getLeaderboard', { scope: 'CAMPUS', period: 'DAILY' }, token);
    expect(board.json.result?.me).toMatchObject({ value: 120 });

    const adminCall = await call('adminStats', {}, token);
    expect(adminCall.json.error?.status).toBe('PERMISSION_DENIED');
    expect(adminCall.json.error?.details?.reason).toBe('ADMIN_REQUIRED');
  });
});
