import { assertFails, assertSucceeds, initializeTestEnvironment, RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { collection, deleteDoc, doc, getDoc, getDocs, query, setDoc, updateDoc, where } from 'firebase/firestore';
import * as fs from 'fs';
import * as path from 'path';

const PROJECT = 'demo-stepup';
let env: RulesTestEnvironment;

function hostPort(): { host: string; port: number } {
  const hp = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
  return { host: hp[0], port: Number(hp[1]) };
}

const ctx = {
  alice: () => env.authenticatedContext('alice', { email: 'alice@thapar.edu', email_verified: true }).firestore(),
  bob: () => env.authenticatedContext('bob', { email: 'bob@thapar.edu', email_verified: true }).firestore(),
  carol: () => env.authenticatedContext('carol', { email: 'carol@thapar.edu', email_verified: true }).firestore(),
  admin: () => env.authenticatedContext('root', { email: 'root@thapar.edu', email_verified: true, admin: true }).firestore(),
  outsider: () => env.authenticatedContext('alice', { email: 'alice@gmail.com', email_verified: true }).firestore(),
  unverified: () => env.authenticatedContext('alice', { email: 'alice@thapar.edu', email_verified: false }).firestore(),
  subdomain: () => env.authenticatedContext('alice', { email: 'alice@mail.thapar.edu', email_verified: true }).firestore(),
  lookalike: () => env.authenticatedContext('alice', { email: 'alice@thapar.edu.evil.com', email_verified: true }).firestore(),
  fakeAdmin: () => env.authenticatedContext('alice', { email: 'alice@gmail.com', email_verified: true, admin: true }).firestore(),
  anon: () => env.unauthenticatedContext().firestore(),
};

beforeAll(async () => {
  const { host, port } = hostPort();
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: { rules: fs.readFileSync(path.join(__dirname, '../../../../firestore.rules'), 'utf8'), host, port },
  });
});

afterAll(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    const set = (p: string, data: Record<string, unknown>) => setDoc(doc(d, p), data);
    await set('users/alice', { displayName: 'Alice', email: 'alice@thapar.edu', pointsBalance: 100, pointsReserved: 0, status: 'ACTIVE', role: 'student', lifetimeVerifiedSteps: 5 });
    await set('users/bob', { displayName: 'Bob', email: 'bob@thapar.edu', pointsBalance: 50, status: 'ACTIVE', role: 'student' });
    await set('users/alice/devices/dev1', { deviceId: 'dev1', isRewardDevice: true });
    await set('publicProfiles/alice', { displayName: 'Alice', discoverable: true });
    await set('hostels/agira', { displayName: 'Agira Hall', active: true });
    await set('leaderboards/CAMPUS_20260302', { scope: 'CAMPUS' });
    await set('leaderboards/CAMPUS_20260302/entries/alice', { uid: 'alice', verifiedSteps: 100 });
    await set('stepBuckets/alice_dev1_10000', { uid: 'alice', serverCredited: 10, startMs: 10000 });
    await set('stepBuckets/bob_dev2_10000', { uid: 'bob', serverCredited: 10, startMs: 10000 });
    await set('dailyStepSummaries/alice_20260302', { uid: 'alice', verifiedSteps: 1000 });
    await set('dailyStepSummaries/bob_20260302', { uid: 'bob', verifiedSteps: 2000 });
    await set('virtualPointsLedger/ADMIN_x_alice_ADJUSTMENT', { uid: 'alice', delta: 100 });
    await set('virtualPointsLedger/ADMIN_y_bob_ADJUSTMENT', { uid: 'bob', delta: 100 });
    await set('achievements/alice_FIRST_1K', { uid: 'alice', badgeId: 'FIRST_1K' });
    await set('buddyRequests/alice_bob', { fromUid: 'alice', toUid: 'bob', status: 'PENDING' });
    await set('buddyConnections/alice_bob', { uids: ['alice', 'bob'], active: true });
    await set('challenges/pub1', { type: 'CAMPUS', title: 'Campus', status: 'ACTIVE', winnerUid: null });
    await set('challenges/buddy1', { type: 'BUDDY', title: 'Duel', status: 'ACTIVE', participantUids: ['alice', 'bob'], winnerUid: null });
    await set('challengeResults/pub1', { type: 'CAMPUS', winnerUid: 'x' });
    await set('challengeResults/buddy1', { type: 'BUDDY', winnerUid: 'alice', participantUids: ['alice', 'bob'] });
    await set('challengeParticipants/pub1_alice', { uid: 'alice', challengeId: 'pub1', progress: 10, rewardPaid: false });
    await set('challengeParticipants/pub1_bob', { uid: 'bob', challengeId: 'pub1', progress: 99, rewardPaid: false });
    await set('stepBets/bet1', { challengerUid: 'alice', opponentUid: 'bob', status: 'ACTIVE', stakePoints: 10 });
    await set('notifications/alice_n1', { uid: 'alice', type: 'SYSTEM', title: 'hi', body: 'b', read: false, dedupeKey: 'n1' });
    await set('notifications/bob_n1', { uid: 'bob', type: 'SYSTEM', title: 'hi', body: 'b', read: false, dedupeKey: 'n1' });
    await set('reports/r1', { reporterUid: 'alice', targetUid: 'bob', status: 'OPEN' });
    await set('riskEvents/e1', { uid: 'bob', kind: 'DOWNGRADE', status: 'OPEN' });
    await set('adminAudit/a1', { adminUid: 'root', action: 'x' });
    await set('adminSettings/global', { maxStepsPerBucket: 35 });
    await set('adminSettings/badges', { FIRST_1K: { title: 'x' } });
    await set('adminSettings/admins', { changes: [] });
    await set('adminSettings/challengeTemplates', { suggested: [] });
    await set('secret/doc1', { x: 1 });
  });
});

describe('default deny and identity gating', () => {
  test('unknown collections are denied for everyone, including admins', async () => {
    await assertFails(getDoc(doc(ctx.alice(), 'secret/doc1')));
    await assertFails(getDoc(doc(ctx.admin(), 'secret/doc1')));
    await assertFails(setDoc(doc(ctx.admin(), 'secret/doc2'), { x: 1 }));
  });

  test.each([
    ['anonymous', () => ctx.anon()],
    ['non-thapar email', () => ctx.outsider()],
    ['unverified thapar email', () => ctx.unverified()],
    ['subdomain thapar email', () => ctx.subdomain()],
    ['look-alike domain', () => ctx.lookalike()],
    ['admin claim on a non-thapar account', () => ctx.fakeAdmin()],
  ])('%s cannot read public data, own user doc or notifications', async (_n, getCtx) => {
    const d = getCtx();
    await assertFails(getDoc(doc(d, 'publicProfiles/alice')));
    await assertFails(getDoc(doc(d, 'hostels/agira')));
    await assertFails(getDoc(doc(d, 'users/alice')));
    await assertFails(getDoc(doc(d, 'notifications/alice_n1')));
    await assertFails(getDoc(doc(d, 'leaderboards/CAMPUS_20260302/entries/alice')));
    await assertFails(getDoc(doc(d, 'adminSettings/global')));
    await assertFails(getDoc(doc(d, 'reports/r1')));
  });

  test('an eligible user reads public reference data', async () => {
    await assertSucceeds(getDoc(doc(ctx.bob(), 'publicProfiles/alice')));
    await assertSucceeds(getDoc(doc(ctx.bob(), 'hostels/agira')));
    await assertSucceeds(getDoc(doc(ctx.bob(), 'leaderboards/CAMPUS_20260302')));
    await assertSucceeds(getDoc(doc(ctx.bob(), 'leaderboards/CAMPUS_20260302/entries/alice')));
    await assertSucceeds(getDocs(collection(ctx.bob(), 'hostels')));
  });
});

describe('users: private, no self-edit of role / status / points', () => {
  test('owner reads own doc only', async () => {
    await assertSucceeds(getDoc(doc(ctx.alice(), 'users/alice')));
    await assertFails(getDoc(doc(ctx.alice(), 'users/bob')));
    await assertFails(getDocs(collection(ctx.alice(), 'users')));
  });

  test.each([
    ['role escalation', { role: 'admin' }],
    ['status self-reactivation', { status: 'ACTIVE' }],
    ['points balance', { pointsBalance: 999_999 }],
    ['points reserved', { pointsReserved: 0 }],
    ['lifetime steps', { lifetimeVerifiedSteps: 10_000_000 }],
    ['streak', { currentStreak: 365 }],
    ['harmless profile field', { bio: 'x' }],
  ])('owner cannot update own user doc: %s', async (_n, patch) => {
    await assertFails(updateDoc(doc(ctx.alice(), 'users/alice'), patch));
  });

  test('cannot create or delete user docs, nor edit another user', async () => {
    await assertFails(setDoc(doc(ctx.carol(), 'users/carol'), { displayName: 'C', role: 'admin', pointsBalance: 1e6 }));
    await assertFails(deleteDoc(doc(ctx.alice(), 'users/alice')));
    await assertFails(updateDoc(doc(ctx.alice(), 'users/bob'), { pointsBalance: 0 }));
  });

  test('devices: owner reads, nobody writes', async () => {
    await assertSucceeds(getDoc(doc(ctx.alice(), 'users/alice/devices/dev1')));
    await assertFails(getDoc(doc(ctx.bob(), 'users/alice/devices/dev1')));
    await assertFails(updateDoc(doc(ctx.alice(), 'users/alice/devices/dev1'), { isRewardDevice: true, fcmToken: 'x' }));
    await assertFails(setDoc(doc(ctx.alice(), 'users/alice/devices/dev2'), { isRewardDevice: true }));
  });

  test('publicProfiles are not client-writable (not even by the owner)', async () => {
    await assertFails(updateDoc(doc(ctx.alice(), 'publicProfiles/alice'), { weeklyVerifiedSteps: 99999 }));
    await assertFails(setDoc(doc(ctx.carol(), 'publicProfiles/carol'), { displayName: 'C' }));
  });
});

describe('hostels and leaderboards: students cannot edit', () => {
  test('hostel create / update / delete by a student is denied', async () => {
    await assertFails(updateDoc(doc(ctx.alice(), 'hostels/agira'), { displayName: 'Hacked', active: false }));
    await assertFails(setDoc(doc(ctx.alice(), 'hostels/new'), { displayName: 'New' }));
    await assertFails(deleteDoc(doc(ctx.alice(), 'hostels/agira')));
  });

  test('hostel edits are server-only even for an admin token (admins use callables)', async () => {
    await assertFails(updateDoc(doc(ctx.admin(), 'hostels/agira'), { displayName: 'X' }));
  });

  test('leaderboard entries cannot be written by the owner (no self-ranking)', async () => {
    await assertFails(updateDoc(doc(ctx.alice(), 'leaderboards/CAMPUS_20260302/entries/alice'), { verifiedSteps: 10_000_000 }));
    await assertFails(setDoc(doc(ctx.alice(), 'leaderboards/CAMPUS_20260302/entries/zzz'), { verifiedSteps: 1 }));
    await assertFails(setDoc(doc(ctx.alice(), 'leaderboards/HOSTELS_20260302'), { scope: 'HOSTELS' }));
  });
});

describe('steps, points, achievements: owner read only, no client writes', () => {
  test('stepBuckets: unauthorized step modification is denied', async () => {
    await assertFails(updateDoc(doc(ctx.alice(), 'stepBuckets/alice_dev1_10000'), { serverCredited: 35, rewardEligible: true }));
    await assertFails(setDoc(doc(ctx.alice(), 'stepBuckets/alice_dev1_20000'), { uid: 'alice', serverCredited: 35, rewardEligible: true }));
    await assertFails(deleteDoc(doc(ctx.alice(), 'stepBuckets/alice_dev1_10000')));
    await assertFails(updateDoc(doc(ctx.alice(), 'stepBuckets/bob_dev2_10000'), { serverCredited: 0 }));
  });

  test('stepBuckets / summaries / ledger / achievements: owner reads, others and listing-all are denied', async () => {
    for (const p of ['stepBuckets/alice_dev1_10000', 'dailyStepSummaries/alice_20260302', 'virtualPointsLedger/ADMIN_x_alice_ADJUSTMENT', 'achievements/alice_FIRST_1K']) {
      await assertSucceeds(getDoc(doc(ctx.alice(), p)));
      await assertFails(getDoc(doc(ctx.bob(), p)));
    }
    await assertSucceeds(getDocs(query(collection(ctx.alice(), 'dailyStepSummaries'), where('uid', '==', 'alice'))));
    await assertFails(getDocs(collection(ctx.alice(), 'dailyStepSummaries')));
    await assertFails(getDocs(query(collection(ctx.alice(), 'dailyStepSummaries'), where('uid', '==', 'bob'))));
  });

  test('daily summaries are not client-writable', async () => {
    await assertFails(updateDoc(doc(ctx.alice(), 'dailyStepSummaries/alice_20260302'), { verifiedSteps: 50_000 }));
    await assertFails(setDoc(doc(ctx.alice(), 'dailyStepSummaries/alice_20260303'), { uid: 'alice', verifiedSteps: 50_000 }));
  });

  test('reward / points modification is denied (ledger, achievements, balance)', async () => {
    await assertFails(setDoc(doc(ctx.alice(), 'virtualPointsLedger/ADMIN_z_alice_ADJUSTMENT'), { uid: 'alice', delta: 1_000_000 }));
    await assertFails(updateDoc(doc(ctx.alice(), 'virtualPointsLedger/ADMIN_x_alice_ADJUSTMENT'), { delta: 1_000_000 }));
    await assertFails(setDoc(doc(ctx.alice(), 'achievements/alice_CAMPUS_FITNESS_STAR'), { uid: 'alice', badgeId: 'CAMPUS_FITNESS_STAR' }));
    await assertFails(deleteDoc(doc(ctx.alice(), 'achievements/alice_FIRST_1K')));
  });
});

describe('social data: participants only', () => {
  test('buddy requests and connections', async () => {
    await assertSucceeds(getDoc(doc(ctx.alice(), 'buddyRequests/alice_bob')));
    await assertSucceeds(getDoc(doc(ctx.bob(), 'buddyRequests/alice_bob')));
    await assertFails(getDoc(doc(ctx.carol(), 'buddyRequests/alice_bob')));
    await assertSucceeds(getDoc(doc(ctx.bob(), 'buddyConnections/alice_bob')));
    await assertFails(getDoc(doc(ctx.carol(), 'buddyConnections/alice_bob')));
    await assertFails(updateDoc(doc(ctx.bob(), 'buddyRequests/alice_bob'), { status: 'ACCEPTED' }));
    await assertFails(setDoc(doc(ctx.carol(), 'buddyConnections/alice_carol'), { uids: ['alice', 'carol'], active: true }));
  });

  test('step bets visible to the two participants only; never writable', async () => {
    await assertSucceeds(getDoc(doc(ctx.alice(), 'stepBets/bet1')));
    await assertSucceeds(getDoc(doc(ctx.bob(), 'stepBets/bet1')));
    await assertFails(getDoc(doc(ctx.carol(), 'stepBets/bet1')));
    await assertFails(updateDoc(doc(ctx.alice(), 'stepBets/bet1'), { winnerUid: 'alice', status: 'COMPLETED' }));
    await assertFails(setDoc(doc(ctx.alice(), 'stepBets/bet2'), { challengerUid: 'alice', opponentUid: 'bob', stakePoints: 1 }));
  });

  test('challenges: public ones readable by eligible users, BUDDY ones by participants only', async () => {
    await assertSucceeds(getDoc(doc(ctx.carol(), 'challenges/pub1')));
    await assertSucceeds(getDoc(doc(ctx.alice(), 'challenges/buddy1')));
    await assertFails(getDoc(doc(ctx.carol(), 'challenges/buddy1')));
    await assertSucceeds(getDoc(doc(ctx.carol(), 'challengeResults/pub1')));
    await assertSucceeds(getDoc(doc(ctx.bob(), 'challengeResults/buddy1')));
    await assertFails(getDoc(doc(ctx.carol(), 'challengeResults/buddy1')));
  });

  test('challenge winner / results / status cannot be edited by clients', async () => {
    await assertFails(updateDoc(doc(ctx.alice(), 'challenges/buddy1'), { winnerUid: 'alice', status: 'COMPLETED' }));
    await assertFails(updateDoc(doc(ctx.carol(), 'challenges/pub1'), { winnerUid: 'carol' }));
    await assertFails(updateDoc(doc(ctx.alice(), 'challengeResults/buddy1'), { winnerUid: 'alice' }));
    await assertFails(setDoc(doc(ctx.alice(), 'challengeResults/new'), { winnerUid: 'alice' }));
    await assertFails(deleteDoc(doc(ctx.alice(), 'challenges/pub1')));
  });

  test('challenge participants: own doc readable, others not; progress/reward not writable', async () => {
    await assertSucceeds(getDoc(doc(ctx.alice(), 'challengeParticipants/pub1_alice')));
    await assertFails(getDoc(doc(ctx.alice(), 'challengeParticipants/pub1_bob')));
    await assertFails(updateDoc(doc(ctx.alice(), 'challengeParticipants/pub1_alice'), { progress: 999_999, rewardPaid: true }));
    await assertFails(setDoc(doc(ctx.carol(), 'challengeParticipants/pub1_carol'), { uid: 'carol', challengeId: 'pub1', status: 'JOINED' }));
  });
});

describe('notifications: owner may only flip `read`', () => {
  test('owner reads own, not others', async () => {
    await assertSucceeds(getDoc(doc(ctx.alice(), 'notifications/alice_n1')));
    await assertFails(getDoc(doc(ctx.alice(), 'notifications/bob_n1')));
    await assertSucceeds(getDocs(query(collection(ctx.alice(), 'notifications'), where('uid', '==', 'alice'))));
    await assertFails(getDocs(collection(ctx.alice(), 'notifications')));
  });

  test('marking own notification read is allowed (true and false)', async () => {
    await assertSucceeds(updateDoc(doc(ctx.alice(), 'notifications/alice_n1'), { read: true }));
    await assertSucceeds(updateDoc(doc(ctx.alice(), 'notifications/alice_n1'), { read: false }));
  });

  test.each([
    ['title', { title: 'tampered' }],
    ['body', { body: 'tampered' }],
    ['uid (hand over)', { uid: 'bob' }],
    ['type', { type: 'BET_RESULT' }],
    ['dedupeKey', { dedupeKey: 'other' }],
    ['read plus another field', { read: true, title: 'tampered' }],
    ['read non-boolean', { read: 'yes' }],
    ['new field', { extra: 1 }],
  ])('updating %s is denied', async (_n, patch) => {
    await assertFails(updateDoc(doc(ctx.alice(), 'notifications/alice_n1'), patch));
  });

  test("cannot mark another user's notification, nor create/delete notifications", async () => {
    await assertFails(updateDoc(doc(ctx.alice(), 'notifications/bob_n1'), { read: true }));
    await assertFails(setDoc(doc(ctx.alice(), 'notifications/alice_n2'), { uid: 'alice', title: 'fake', read: false }));
    await assertFails(deleteDoc(doc(ctx.alice(), 'notifications/alice_n1')));
  });

  test('non-eligible identities cannot mark read', async () => {
    await assertFails(updateDoc(doc(ctx.outsider(), 'notifications/alice_n1'), { read: true }));
    await assertFails(updateDoc(doc(ctx.unverified(), 'notifications/alice_n1'), { read: true }));
  });
});

describe('admin-only collections', () => {
  test.each(['reports/r1', 'riskEvents/e1', 'adminAudit/a1', 'adminSettings/admins', 'adminSettings/challengeTemplates'])('%s: admin reads, student denied', async (p) => {
    await assertSucceeds(getDoc(doc(ctx.admin(), p)));
    await assertFails(getDoc(doc(ctx.alice(), p)));
    await assertFails(getDoc(doc(ctx.anon(), p)));
  });

  test('students can read adminSettings global and badges only', async () => {
    await assertSucceeds(getDoc(doc(ctx.alice(), 'adminSettings/global')));
    await assertSucceeds(getDoc(doc(ctx.alice(), 'adminSettings/badges')));
  });

  test('nobody can write admin collections from a client (even with the admin claim)', async () => {
    for (const [c, ctxFn] of [
      ['student', ctx.alice],
      ['admin', ctx.admin],
    ] as const) {
      void c;
      await assertFails(updateDoc(doc(ctxFn(), 'adminSettings/global'), { maxRewardStepsPerDay: 99_999_999 }));
      await assertFails(updateDoc(doc(ctxFn(), 'reports/r1'), { status: 'DISMISSED' }));
      await assertFails(updateDoc(doc(ctxFn(), 'riskEvents/e1'), { status: 'CLEARED' }));
      await assertFails(setDoc(doc(ctxFn(), 'adminAudit/a2'), { x: 1 }));
    }
  });

  test('students cannot create reports directly (only via reportProfile)', async () => {
    await assertFails(setDoc(doc(ctx.alice(), 'reports/r2'), { reporterUid: 'alice', targetUid: 'bob', status: 'OPEN' }));
  });
});
