import {
  handleAdminCancelChallenge,
  handleAdminCreateChallenge,
  handleAdminListReports,
  handleAdminListRiskEvents,
  handleAdminListStudents,
  handleAdminResolveReport,
  handleAdminResolveRiskEvent,
  handleAdminSeedDefaults,
  handleAdminSetHostelActive,
  handleAdminSetSettings,
  handleAdminSetUserRole,
  handleAdminStats,
  handleAdminSuspendUser,
  handleAdminUpsertBadge,
  handleAdminUpsertHostel,
} from '../../../src/admin/admin';
import { handleCreateStepBet } from '../../../src/bets/bets';
import { Req } from '../../../src/lib/auth';
import { setClock } from '../../../src/lib/clock';
import { admin, db } from '../../../src/lib/firebase';
import { handleCreateProfile, handleRegisterDevice } from '../../../src/profile/profile';
import { handleSyncStepBuckets } from '../../../src/steps/syncStepBuckets';
import { alignedBefore, authReq, DAY, expectError, freeze, getDoc, giveVerifiedSteps, givePoints, makeBuddies, makeUser, mkBucket, noAuthReq, profileData, resetAll, T0 } from '../helpers/env';

const D3 = Date.UTC(2026, 2, 2, 18, 30);

beforeEach(async () => {
  await resetAll();
  freeze();
  await makeUser('alice');
  await makeUser('bob');
});
afterAll(() => setClock(null));

const asAdmin = <T>(data: T) => authReq('root', data, { admin: true });
const asStudent = <T>(data: T) => authReq('alice', data);

/** Every admin callable with a payload that is valid for an admin. */
const adminCalls: Array<[string, (r: Req) => Promise<unknown>, Record<string, unknown>]> = [
  ['adminUpsertHostel', handleAdminUpsertHostel, { hostelId: 'new-hall', displayName: 'New Hall', category: 'GENERAL' }],
  ['adminSetHostelActive', handleAdminSetHostelActive, { hostelId: 'agira', active: true }],
  ['adminCreateChallenge', handleAdminCreateChallenge, { type: 'CAMPUS', title: 'Camp', metric: 'TOTAL_STEPS', target: 1000, windowMode: 'FIXED', startAt: D3, endAt: D3 + 2 * DAY }],
  ['adminCancelChallenge', handleAdminCancelChallenge, { challengeId: 'tpl_streak-7' }],
  ['adminListStudents', handleAdminListStudents, {}],
  ['adminSetUserRole', handleAdminSetUserRole, { uid: 'bob', role: 'admin' }],
  ['adminSuspendUser', handleAdminSuspendUser, { uid: 'bob', suspend: true }],
  ['adminListReports', handleAdminListReports, {}],
  ['adminResolveReport', handleAdminResolveReport, { reportId: 'r1', status: 'DISMISSED' }],
  ['adminListRiskEvents', handleAdminListRiskEvents, {}],
  ['adminResolveRiskEvent', handleAdminResolveRiskEvent, { id: 'e1', status: 'CLEARED' }],
  ['adminSetSettings', handleAdminSetSettings, { settings: { betMaxStake: 900 } }],
  ['adminUpsertBadge', handleAdminUpsertBadge, { badgeId: 'EXTRA', title: 'Extra', description: 'Extra badge', icon: 'star', rule: 'always', points: 5 }],
  ['adminStats', handleAdminStats, {}],
  ['adminSeedDefaults', handleAdminSeedDefaults, {}],
];

describe('authorization: students are denied, unauthenticated users are denied', () => {
  test.each(adminCalls)('%s: student => permission-denied ADMIN_REQUIRED, nothing changes', async (_n, fn, payload) => {
    await expectError(fn(asStudent(payload)), 'permission-denied', 'ADMIN_REQUIRED');
    expect((await db().collection('adminAudit').get()).size).toBe(0); // denied attempts are not audit entries of admin actions
  });

  test.each(adminCalls)('%s: unauthenticated => unauthenticated', async (_n, fn, payload) => {
    await expectError(fn(noAuthReq(payload)), 'unauthenticated', 'UNAUTHENTICATED');
  });

  test('admin claim must be exactly true (a string does not count) and the denial happens before payload validation', async () => {
    await expectError(handleAdminStats({ auth: { uid: 'x', token: { email: 'x@thapar.edu', email_verified: true, admin: 'true' } }, data: {} }), 'permission-denied', 'ADMIN_REQUIRED');
    await expectError(handleAdminUpsertHostel(asStudent({ garbage: true })), 'permission-denied', 'ADMIN_REQUIRED');
  });

  test('students cannot escalate: adminSetUserRole by a student does not change anything', async () => {
    await expectError(handleAdminSetUserRole(asStudent({ uid: 'alice', role: 'admin' })), 'permission-denied', 'ADMIN_REQUIRED');
    expect((await db().collection('users').doc('alice').get()).data()?.role).toBe('student');
  });
});

describe('admin actions (allowed) are audit-logged', () => {
  test('every admin call writes an audit entry with the admin uid and action', async () => {
    await handleAdminStats(asAdmin({}));
    await handleAdminSetHostelActive(asAdmin({ hostelId: 'agira', active: true }));
    const audit = (await db().collection('adminAudit').get()).docs.map((d) => d.data());
    expect(audit.map((a) => a.action).sort()).toEqual(['adminSetHostelActive', 'adminStats']);
    expect(audit.every((a) => a.adminUid === 'root')).toBe(true);
    expect(audit.find((a) => a.action === 'adminSetHostelActive')?.details).toMatchObject({ hostelId: 'agira', active: true });
  });

  test('payload objects/arrays are not copied into audit details (no unbounded data, no secrets)', async () => {
    await handleAdminSetSettings(asAdmin({ settings: { betMaxStake: 900 } }));
    const a = (await db().collection('adminAudit').get()).docs[0].data();
    expect(a.details).toEqual({ settings: '[object]' });
  });
});

describe('hostels', () => {
  test('upsert creates and edits; deactivating a hostel blocks new registrations; Vasudha blocks stay separate', async () => {
    await handleAdminUpsertHostel(asAdmin({ hostelId: 'new-hall', displayName: 'New Hall', category: 'GIRLS', block: 'X', sortOrder: 50 }));
    expect(await getDoc('hostels/new-hall')).toMatchObject({ displayName: 'New Hall', category: 'GIRLS', block: 'X', active: true, sortOrder: 50 });
    await handleAdminUpsertHostel(asAdmin({ hostelId: 'new-hall', displayName: 'New Hall 2', category: 'GIRLS' }));
    expect((await getDoc('hostels/new-hall'))?.displayName).toBe('New Hall 2');
    await handleAdminSetHostelActive(asAdmin({ hostelId: 'new-hall', active: false }));
    await expectError(handleCreateProfile(authReq('carol', profileData({ hostelId: 'new-hall' }))), 'invalid-argument', 'INVALID_HOSTEL');
    await expectError(handleAdminSetHostelActive(asAdmin({ hostelId: 'nope', active: true })), 'not-found', 'HOSTEL_NOT_FOUND');
    await expectError(handleAdminUpsertHostel(asAdmin({ hostelId: 'Bad Id!', displayName: 'x', category: 'GENERAL' })), 'invalid-argument', 'INVALID_HOSTEL_ID');
    expect(await getDoc('hostels/vasudha-e')).toMatchObject({ block: 'E' });
    expect(await getDoc('hostels/vasudha-g')).toMatchObject({ block: 'G' });
  });
});

describe('challenges', () => {
  const base = { type: 'CAMPUS', title: 'Campus Week', metric: 'TOTAL_STEPS', target: 70000, windowMode: 'FIXED', startAt: D3, endAt: D3 + 7 * DAY };

  test('creates an UPCOMING fixed-window campus challenge with day-aligned IST window', async () => {
    const { challengeId } = await handleAdminCreateChallenge(asAdmin({ ...base, rewardPoints: 150 }));
    const c = await getDoc(`challenges/${challengeId}`);
    expect(c).toMatchObject({ type: 'CAMPUS', status: 'UPCOMING', durationDays: 7, rewardPoints: 150, createdBy: 'root', participantCount: 0, isTemplate: false, windowMode: 'FIXED' });
  });

  test('a window that already started is ACTIVE; a window in the past is rejected; not day aligned is rejected', async () => {
    const started = Date.UTC(2026, 2, 1, 18, 30) - DAY; // IST 2026-03-01 00:00
    const r = await handleAdminCreateChallenge(asAdmin({ ...base, startAt: started, endAt: started + 5 * DAY }));
    expect((await getDoc(`challenges/${r.challengeId}`))?.status).toBe('ACTIVE');
    await expectError(handleAdminCreateChallenge(asAdmin({ ...base, startAt: started - 10 * DAY, endAt: started - 5 * DAY })), 'invalid-argument', 'WINDOW_IN_PAST');
    await expectError(handleAdminCreateChallenge(asAdmin({ ...base, startAt: D3 + 1000 })), 'invalid-argument', 'WINDOW_NOT_DAY_ALIGNED');
    await expectError(handleAdminCreateChallenge(asAdmin({ ...base, endAt: D3 })), 'invalid-argument', 'INVALID_END_AT');
  });

  test('metric validation and INTER_HOSTEL hostel list', async () => {
    await expectError(handleAdminCreateChallenge(asAdmin({ ...base, metric: 'STREAK_DAYS', target: 5 })), 'invalid-argument', 'INVALID_DAILY_TARGET');
    await expectError(handleAdminCreateChallenge(asAdmin({ ...base, type: 'INTER_HOSTEL' })), 'invalid-argument', 'INVALID_HOSTEL_IDS');
    await expectError(handleAdminCreateChallenge(asAdmin({ ...base, type: 'INTER_HOSTEL', hostelIds: ['agira', 'nope'] })), 'invalid-argument', 'INVALID_HOSTEL_IDS');
    await expectError(handleAdminCreateChallenge(asAdmin({ ...base, type: 'BUDDY' })), 'invalid-argument', 'INVALID_TYPE');
    const ok = await handleAdminCreateChallenge(asAdmin({ ...base, type: 'INTER_HOSTEL', hostelIds: ['agira', 'ira'], hostelAggregation: 'TOTAL' }));
    expect(await getDoc(`challenges/${ok.challengeId}`)).toMatchObject({ hostelIds: ['agira', 'ira'], hostelAggregation: 'TOTAL' });
  });

  test('cancel is idempotent and final challenges cannot be cancelled', async () => {
    const { challengeId } = await handleAdminCreateChallenge(asAdmin(base));
    await handleAdminCancelChallenge(asAdmin({ challengeId }));
    await handleAdminCancelChallenge(asAdmin({ challengeId }));
    expect((await getDoc(`challenges/${challengeId}`))?.status).toBe('CANCELLED');
    await db().collection('challenges').doc('done').set({ status: 'COMPLETED' });
    await expectError(handleAdminCancelChallenge(asAdmin({ challengeId: 'done' })), 'failed-precondition', 'CHALLENGE_ALREADY_COMPLETED');
    await expectError(handleAdminCancelChallenge(asAdmin({ challengeId: 'missing' })), 'not-found', 'CHALLENGE_NOT_FOUND');
  });
});

describe('users: listing, suspension, roles (Auth emulator)', () => {
  test('adminListStudents returns private fields to admins only; supports search', async () => {
    const r = (await handleAdminListStudents(asAdmin({}))) as { students: Array<Record<string, unknown>> };
    expect(r.students.map((s) => s.uid).sort()).toEqual(['alice', 'bob']);
    expect(r.students[0]).toHaveProperty('email');
    const q = (await handleAdminListStudents(asAdmin({ query: 'BOB@' }))) as { students: Array<Record<string, unknown>> };
    expect(q.students.map((s) => s.uid)).toEqual(['bob']);
  });

  test('suspending a user blocks them everywhere, hides them, and excludes them from hostel totals; unsuspend restores', async () => {
    await giveVerifiedSteps('bob', '20260302', 4000);
    await giveVerifiedSteps('alice', '20260302', 1000);
    expect(await getDoc('leaderboards/HOSTELS_20260302/entries/agira')).toMatchObject({ totalVerifiedSteps: 5000, participants: 2 });
    await handleAdminSuspendUser(asAdmin({ uid: 'bob', suspend: true, reason: 'cheating' }));
    expect(await getDoc('users/bob')).toMatchObject({ status: 'SUSPENDED', suspendedReason: 'cheating' });
    expect(await getDoc('publicProfiles/bob')).toMatchObject({ discoverable: false, showOnLeaderboards: false });
    expect(await getDoc('leaderboards/HOSTELS_20260302/entries/agira')).toMatchObject({ totalVerifiedSteps: 1000, participants: 1 });
    expect(await getDoc('leaderboards/CAMPUS_20260302/entries/bob')).toMatchObject({ showOnLeaderboards: false, displayName: 'Student' });
    await expectError(handleRegisterDevice(authReq('bob', { deviceId: 'bob-device-1', model: 'x', appVersion: '1' })), 'permission-denied', 'ACCOUNT_SUSPENDED');
    await expectError(handleSyncStepBuckets(authReq('bob', { deviceId: 'bob-device-1', buckets: [] })), 'permission-denied', 'ACCOUNT_SUSPENDED');
    await handleAdminSuspendUser(asAdmin({ uid: 'bob', suspend: false }));
    expect(await getDoc('users/bob')).toMatchObject({ status: 'ACTIVE' });
    expect(await getDoc('leaderboards/HOSTELS_20260302/entries/agira')).toMatchObject({ totalVerifiedSteps: 5000, participants: 2 });
    await expectError(handleAdminSuspendUser(asAdmin({ uid: 'root', suspend: true })), 'failed-precondition', 'CANNOT_SUSPEND_SELF');
    await expectError(handleAdminSuspendUser(asAdmin({ uid: 'ghost', suspend: true })), 'not-found', 'USER_NOT_FOUND');
  });

  test('a suspended user cannot take part in new bets', async () => {
    await makeBuddies('alice', 'bob');
    await givePoints('alice', 200);
    await handleAdminSuspendUser(asAdmin({ uid: 'bob', suspend: true }));
    await expectError(handleCreateStepBet(authReq('alice', { opponentUid: 'bob', targetSteps: 5000, durationDays: 1, stakePoints: 50 })), 'failed-precondition');
  });

  test('adminSetUserRole sets/removes the custom claim and mirrors the role; cannot demote self; unknown user', async () => {
    const auth = admin.auth();
    await auth.createUser({ uid: 'bob', email: 'bob@thapar.edu', emailVerified: true });
    await handleAdminSetUserRole(asAdmin({ uid: 'bob', role: 'admin' }));
    expect((await auth.getUser('bob')).customClaims).toMatchObject({ admin: true });
    expect((await getDoc('users/bob'))?.role).toBe('admin');
    expect(((await getDoc('adminSettings/admins'))?.changes as Array<Record<string, unknown>>)[0]).toMatchObject({ uid: 'bob', role: 'admin', by: 'root' });
    // the new admin can now use admin callables with a token carrying the claim
    expect(await handleAdminStats(authReq('bob', {}, { admin: true }))).toMatchObject({ users: 2 });
    await handleAdminSetUserRole(asAdmin({ uid: 'bob', role: 'student' }));
    expect((await auth.getUser('bob')).customClaims?.admin).toBe(false);
    expect((await getDoc('users/bob'))?.role).toBe('student');
    await expectError(handleAdminSetUserRole(asAdmin({ uid: 'root', role: 'student' })), 'failed-precondition', 'CANNOT_DEMOTE_SELF');
    await expectError(handleAdminSetUserRole(asAdmin({ uid: 'nobody-here', role: 'admin' })), 'not-found', 'USER_NOT_FOUND');
    await expectError(handleAdminSetUserRole(asAdmin({ uid: 'bob', role: 'superuser' })), 'invalid-argument', 'INVALID_ROLE');
  });
});

describe('reports and risk events', () => {
  test('list and resolve reports; list and resolve risk events (generated by a real sync)', async () => {
    await db().collection('reports').doc('r1').set({ reporterUid: 'alice', targetUid: 'bob', status: 'OPEN', reason: 'SPAM', createdAt: new Date() });
    await db().collection('reports').doc('r2').set({ reporterUid: 'bob', targetUid: 'alice', status: 'DISMISSED', reason: 'SPAM', createdAt: new Date() });
    const open = (await handleAdminListReports(asAdmin({ status: 'OPEN' }))) as { reports: Array<Record<string, unknown>> };
    expect(open.reports.map((r) => r.id)).toEqual(['r1']);
    expect(((await handleAdminListReports(asAdmin({}))) as { reports: unknown[] }).reports).toHaveLength(2);
    await handleAdminResolveReport(asAdmin({ reportId: 'r1', status: 'ACTIONED' }));
    expect(await getDoc('reports/r1')).toMatchObject({ status: 'ACTIONED', resolvedBy: 'root' });
    await expectError(handleAdminResolveReport(asAdmin({ reportId: 'zzz', status: 'ACTIONED' })), 'not-found', 'REPORT_NOT_FOUND');

    await handleRegisterDevice(authReq('alice', { deviceId: 'alice-device-1', model: 'x', appVersion: '1' }));
    await handleSyncStepBuckets(authReq('alice', { deviceId: 'alice-device-1', buckets: [mkBucket({ startMs: alignedBefore(T0, 600_000), raw: 50, credited: 50 })] }));
    const events = (await handleAdminListRiskEvents(asAdmin({ status: 'OPEN' }))) as { events: Array<Record<string, unknown>> };
    // an over-cadence bucket that was claimed as credited opens a HARD_LIMIT and a DOWNGRADE event
    expect(events.events.map((e) => e.kind).sort()).toEqual(['DOWNGRADE', 'HARD_LIMIT']);
    const hard = events.events.find((e) => e.kind === 'HARD_LIMIT') as Record<string, unknown>;
    expect(hard).toMatchObject({ uid: 'alice', status: 'OPEN' });
    await handleAdminResolveRiskEvent(asAdmin({ id: String(hard.id), status: 'CLEARED' }));
    const rest = (await handleAdminListRiskEvents(asAdmin({ status: 'OPEN' }))) as { events: Array<Record<string, unknown>> };
    expect(rest.events.map((e) => e.kind)).toEqual(['DOWNGRADE']);
    await expectError(handleAdminResolveRiskEvent(asAdmin({ id: 'missing', status: 'CLEARED' })), 'not-found', 'RISK_EVENT_NOT_FOUND');
  });
});

describe('settings, badges, stats, seed', () => {
  test('adminSetSettings validates keys and bounds and takes effect (bet stake limit)', async () => {
    await expectError(handleAdminSetSettings(asAdmin({ settings: { timezone: 'UTC' } })), 'invalid-argument', 'SETTING_NOT_EDITABLE');
    await expectError(handleAdminSetSettings(asAdmin({ settings: { bogus: 1 } })), 'invalid-argument', 'SETTING_NOT_EDITABLE');
    await expectError(handleAdminSetSettings(asAdmin({ settings: { maxStepsPerBucket: 100 } })), 'invalid-argument', 'INVALID_SETTING_VALUE'); // cannot exceed the physical cap
    await expectError(handleAdminSetSettings(asAdmin({ settings: { betMinStake: 2000 } })), 'invalid-argument', 'INVALID_SETTING_VALUE'); // min > max
    await expectError(handleAdminSetSettings(asAdmin({ settings: { betMaxStake: '5' } })), 'invalid-argument', 'INVALID_SETTING_VALUE');
    await makeBuddies('alice', 'bob');
    await givePoints('alice', 5000);
    const bet = { opponentUid: 'bob', targetSteps: 5000, durationDays: 1, stakePoints: 1500 };
    await expectError(handleCreateStepBet(authReq('alice', bet)), 'invalid-argument', 'INVALID_STAKE_POINTS');
    await handleAdminSetSettings(asAdmin({ settings: { betMaxStake: 2000 } }));
    expect((await db().collection('adminSettings').doc('global').get()).data()?.betMaxStake).toBe(2000);
    expect((await handleCreateStepBet(authReq('alice', bet))).betId).toBeTruthy();
  });

  test('adminUpsertBadge stores a badge definition', async () => {
    await handleAdminUpsertBadge(asAdmin({ badgeId: 'EXTRA', title: 'Extra', description: 'Extra badge', icon: 'star', rule: 'always', points: 5 }));
    expect((await getDoc('adminSettings/badges'))?.EXTRA).toEqual({ title: 'Extra', description: 'Extra badge', icon: 'star', rule: 'always', points: 5 });
    expect((await getDoc('adminSettings/badges'))?.FIRST_1K).toBeDefined(); // seeded catalogue kept
    await expectError(handleAdminUpsertBadge(asAdmin({ badgeId: 'lower', title: 'x', description: 'x', icon: 'x', rule: 'x', points: 1 })), 'invalid-argument', 'INVALID_BADGE_ID');
  });

  test('adminStats counts', async () => {
    expect(await handleAdminStats(asAdmin({}))).toMatchObject({ users: 2, activeUsers: 2, deletionRequests: 0, openReports: 0, openRiskEvents: 0, activeBets: 0 });
  });

  test('adminSeedDefaults is idempotent and never overwrites admin-edited data', async () => {
    await db().collection('hostels').doc('agira').update({ displayName: 'Edited Name' });
    await db().collection('adminSettings').doc('global').update({ betMaxStake: 777 });
    const r1 = (await handleAdminSeedDefaults(asAdmin({}))) as unknown as { report: Record<string, unknown> };
    expect(r1.report).toMatchObject({ hostelsCreated: 0, challengeTemplatesCreated: 0 });
    expect((await getDoc('hostels/agira'))?.displayName).toBe('Edited Name');
    expect((await getDoc('adminSettings/global'))?.betMaxStake).toBe(777);
    // wipe & reseed
    await db().collection('hostels').doc('ira').delete();
    await db().collection('challenges').doc('tpl_streak-7').delete();
    const r2 = (await handleAdminSeedDefaults(asAdmin({}))) as unknown as { report: Record<string, unknown> };
    expect(r2.report).toMatchObject({ hostelsCreated: 1, challengeTemplatesCreated: 1 });
    expect((await db().collection('hostels').get()).size).toBe(18);
    expect((await db().collection('challenges').where('isTemplate', '==', true).get()).size).toBe(6);
  });
});
