import { setClock } from '../../../src/lib/clock';
import { db } from '../../../src/lib/firebase';
import { handleCreateProfile, handleRegisterDevice, handleRequestAccountDeletion, handleUpdateProfile } from '../../../src/profile/profile';
import { handleGetLeaderboard } from '../../../src/leaderboards/getLeaderboard';
import { handleGetChallengeLeaderboard } from '../../../src/challenges/callables';
import { handleMarkNotificationsRead } from '../../../src/notifications/markRead';
import { handleSearchBuddies } from '../../../src/buddies/buddies';
import { handleSyncStepBuckets } from '../../../src/steps/syncStepBuckets';
import { authReq, DAY, expectError, getDoc, makeUser, noAuthReq, profileData, resetAll, userDoc } from '../helpers/env';

beforeEach(resetAll);
afterAll(() => setClock(null));

describe('createProfile (registration)', () => {
  test('valid thapar.edu user gets a profile, a public profile without private data, and zero points', async () => {
    const r = await handleCreateProfile(authReq('alice', profileData({ displayName: 'Alice A' })));
    expect(r.ok).toBe(true);
    expect(r.created).toBe(true);
    const u = await userDoc('alice');
    expect(u).toMatchObject({
      displayName: 'Alice A',
      email: 'alice@thapar.edu',
      hostelId: 'agira',
      block: null,
      status: 'ACTIVE',
      role: 'student',
      pointsBalance: 0,
      pointsReserved: 0,
      lifetimeVerifiedSteps: 0,
      rewardDeviceId: null,
      dailyGoal: 10000,
    });
    expect(u.privacy).toEqual({ discoverable: true, showHostel: true, showWeeklySteps: true, showOnLeaderboards: true });
    expect(u.notificationPrefs).toEqual({ buddy: true, challenges: true, bets: true, leaderboard: true, reminders: true });
    const pub = (await getDoc('publicProfiles/alice')) as Record<string, unknown>;
    expect(pub).toMatchObject({ displayName: 'Alice A', hostelId: 'agira', discoverable: true, weeklyVerifiedSteps: 0 });
    for (const forbidden of ['email', 'pointsBalance', 'pointsReserved', 'status', 'role', 'lifetimeVerifiedSteps']) expect(pub).not.toHaveProperty(forbidden);
  });

  test('email is normalised to lower case from the verified token', async () => {
    await handleCreateProfile(authReq('alice', profileData(), { email: 'Alice.A@THAPAR.EDU' }));
    expect((await userDoc('alice')).email).toBe('alice.a@thapar.edu');
  });

  test.each([
    ['gmail', 'alice@gmail.com'],
    ['subdomain', 'alice@mail.thapar.edu'],
    ['look-alike suffix', 'alice@thapar.edu.evil.com'],
    ['look-alike prefix', 'alice@fakethapar.edu'],
  ])('invalid domain (%s) is rejected and nothing is written', async (_n, email) => {
    await expectError(handleCreateProfile(authReq('alice', profileData(), { email })), 'permission-denied', 'INVALID_EMAIL_DOMAIN');
    expect(await getDoc('users/alice')).toBeUndefined();
    expect(await getDoc('publicProfiles/alice')).toBeUndefined();
  });

  test('unverified email is rejected', async () => {
    await expectError(handleCreateProfile(authReq('alice', profileData(), { verified: false })), 'permission-denied', 'EMAIL_NOT_VERIFIED');
    expect(await getDoc('users/alice')).toBeUndefined();
  });

  test('unauthenticated call is rejected', async () => {
    await expectError(handleCreateProfile(noAuthReq(profileData())), 'unauthenticated', 'UNAUTHENTICATED');
  });

  test('duplicate createProfile is idempotent: the existing profile is returned and NOT overwritten', async () => {
    await handleCreateProfile(authReq('alice', profileData({ displayName: 'First Name', bio: 'one' })));
    await db().collection('users').doc('alice').update({ pointsBalance: 77 });
    const again = await handleCreateProfile(authReq('alice', profileData({ displayName: 'Second Name', bio: 'two', hostelId: 'ira' })));
    expect(again.ok).toBe(true);
    expect(again.created).toBe(false);
    const u = await userDoc('alice');
    expect(u.displayName).toBe('First Name');
    expect(u.hostelId).toBe('agira');
    expect(u.pointsBalance).toBe(77); // not reset
    expect((again.profile as { displayName: string }).displayName).toBe('First Name');
  });

  test('a client cannot choose points, status, role or admin during creation', async () => {
    await handleCreateProfile(authReq('alice', profileData({ pointsBalance: 99999, status: 'SUSPENDED', role: 'admin', lifetimeVerifiedSteps: 9, rewardDeviceId: 'x' })));
    const u = await userDoc('alice');
    expect(u).toMatchObject({ pointsBalance: 0, status: 'ACTIVE', role: 'student', lifetimeVerifiedSteps: 0, rewardDeviceId: null });
  });

  test('Vasudha blocks keep their own block letter', async () => {
    await handleCreateProfile(authReq('alice', profileData({ hostelId: 'vasudha-e' })));
    await handleCreateProfile(authReq('bob', profileData({ hostelId: 'vasudha-g' })));
    expect((await userDoc('alice')).block).toBe('E');
    expect((await userDoc('bob')).block).toBe('G');
  });

  test.each([
    ['unknown hostel', { hostelId: 'nope' }, 'INVALID_HOSTEL'],
    ['short name', { displayName: 'A' }, 'INVALID_DISPLAY_NAME'],
    ['bad fitness level', { fitnessLevel: 'GOD' }, 'INVALID_FITNESS_LEVEL'],
    ['long bio', { bio: 'x'.repeat(161) }, 'INVALID_BIO'],
    ['daily goal too low', { dailyGoal: 500 }, 'INVALID_DAILY_GOAL'],
    ['bad weekday', { availability: ['FUNDAY'] }, 'INVALID_AVAILABILITY'],
    ['bad preferred time', { preferredTime: 'NOON' }, 'INVALID_PREFERRED_TIME'],
    ['non-https photo', { photoUrl: 'javascript:alert(1)' }, 'INVALID_PHOTO_URL'],
  ])('validation: %s', async (_n, over, reason) => {
    await expectError(handleCreateProfile(authReq('alice', profileData(over))), 'invalid-argument', reason);
  });

  test('inactive hostel cannot be chosen', async () => {
    await db().collection('hostels').doc('agira').update({ active: false });
    await expectError(handleCreateProfile(authReq('alice', profileData())), 'invalid-argument', 'INVALID_HOSTEL');
  });
});

describe('updateProfile', () => {
  test('requires an existing profile', async () => {
    await expectError(handleUpdateProfile(authReq('alice', { bio: 'x' })), 'failed-precondition', 'PROFILE_REQUIRED');
  });

  test('editable fields update the private and public profile', async () => {
    await makeUser('alice');
    await handleUpdateProfile(authReq('alice', { displayName: 'New Name', bio: 'new bio', fitnessLevel: 'ADVANCED', dailyGoal: 12000, sportsInterests: ['Yoga'] }));
    const u = await userDoc('alice');
    expect(u).toMatchObject({ displayName: 'New Name', bio: 'new bio', fitnessLevel: 'ADVANCED', dailyGoal: 12000, sportsInterests: ['Yoga'] });
    expect(await getDoc('publicProfiles/alice')).toMatchObject({ displayName: 'New Name', bio: 'new bio', fitnessLevel: 'ADVANCED', sportsInterests: ['Yoga'] });
  });

  test.each(['pointsBalance', 'pointsReserved', 'lifetimeVerifiedSteps', 'currentStreak', 'bestStreak', 'status', 'role', 'email', 'block', 'rewardDeviceId', 'createdAt', 'uid'])(
    'self-edit of %s is rejected and nothing changes',
    async (field) => {
      await makeUser('alice');
      const before = await userDoc('alice');
      await expectError(handleUpdateProfile(authReq('alice', { bio: 'sneaky', [field]: field === 'status' ? 'ACTIVE' : 'admin' })), 'invalid-argument', 'FIELD_NOT_EDITABLE');
      const after = await userDoc('alice');
      expect(after.bio).toBe(before.bio);
      expect(after[field]).toEqual(before[field]);
    },
  );

  test('privacy: hiding hostel and weekly steps removes them from the public profile; counters preserved', async () => {
    await makeUser('alice');
    await db().collection('publicProfiles').doc('alice').update({ weeklyVerifiedSteps: 4321 });
    await handleUpdateProfile(authReq('alice', { privacy: { showHostel: false } }));
    let pub = (await getDoc('publicProfiles/alice')) as Record<string, unknown>;
    expect(pub.hostelId).toBeNull();
    expect(pub.weeklyVerifiedSteps).toBe(4321);
    await handleUpdateProfile(authReq('alice', { privacy: { showWeeklySteps: false, discoverable: false } }));
    pub = (await getDoc('publicProfiles/alice')) as Record<string, unknown>;
    expect(pub.weeklyVerifiedSteps).toBeNull();
    expect(pub.discoverable).toBe(false);
    expect((await userDoc('alice')).privacy).toEqual({ discoverable: false, showHostel: false, showWeeklySteps: false, showOnLeaderboards: true });
  });

  test('changing hostel updates block and the hostel field; unknown hostel is rejected', async () => {
    await makeUser('alice');
    await handleUpdateProfile(authReq('alice', { hostelId: 'vasudha-g' }));
    expect(await userDoc('alice')).toMatchObject({ hostelId: 'vasudha-g', block: 'G' });
    await expectError(handleUpdateProfile(authReq('alice', { hostelId: 'nope' })), 'invalid-argument', 'INVALID_HOSTEL');
  });

  test('a suspended user can no longer update', async () => {
    await makeUser('alice');
    await db().collection('users').doc('alice').update({ status: 'SUSPENDED' });
    await expectError(handleUpdateProfile(authReq('alice', { bio: 'x' })), 'permission-denied', 'ACCOUNT_SUSPENDED');
  });

  test('wrong domain / unverified callers are rejected before any work', async () => {
    await makeUser('alice');
    await expectError(handleUpdateProfile(authReq('alice', { bio: 'x' }, { email: 'alice@gmail.com' })), 'permission-denied', 'INVALID_EMAIL_DOMAIN');
    await expectError(handleUpdateProfile(authReq('alice', { bio: 'x' }, { verified: false })), 'permission-denied', 'EMAIL_NOT_VERIFIED');
  });
});

describe('registerDevice', () => {
  const reg = (uid: string, deviceId: string, extra: Record<string, unknown> = {}) =>
    handleRegisterDevice(authReq(uid, { deviceId, model: 'Pixel 8', appVersion: '1.0.0', ...extra }));

  test('first device becomes the reward device; a second device is display-only', async () => {
    await makeUser('alice');
    expect(await reg('alice', 'device-aaaa1111')).toEqual({ isRewardDevice: true });
    expect(await reg('alice', 'device-bbbb2222')).toEqual({ isRewardDevice: false });
    expect((await userDoc('alice')).rewardDeviceId).toBe('device-aaaa1111');
    expect(await getDoc('users/alice/devices/device-aaaa1111')).toMatchObject({ isRewardDevice: true, platform: 'android', model: 'Pixel 8' });
    expect(await getDoc('users/alice/devices/device-bbbb2222')).toMatchObject({ isRewardDevice: false });
  });

  test('registering the same device again is idempotent and keeps the FCM token when none is sent', async () => {
    await makeUser('alice');
    await reg('alice', 'device-aaaa1111', { fcmToken: 'tok-1' });
    expect(await reg('alice', 'device-aaaa1111')).toEqual({ isRewardDevice: true });
    expect((await getDoc('users/alice/devices/device-aaaa1111'))?.fcmToken).toBe('tok-1');
    await reg('alice', 'device-aaaa1111', { fcmToken: 'tok-2' });
    expect((await getDoc('users/alice/devices/device-aaaa1111'))?.fcmToken).toBe('tok-2');
  });

  test('another account can use the same deviceId string without interfering (devices are per user)', async () => {
    await makeUser('alice');
    await makeUser('bob');
    expect((await reg('alice', 'device-shared01')).isRewardDevice).toBe(true);
    expect((await reg('bob', 'device-shared01')).isRewardDevice).toBe(true);
  });

  test('a silent reward device (14+ days) can be replaced; before that it cannot', async () => {
    await makeUser('alice');
    await reg('alice', 'device-aaaa1111');
    setClock(() => Date.now() + 10 * DAY);
    expect((await reg('alice', 'device-bbbb2222')).isRewardDevice).toBe(false);
    setClock(() => Date.now() + 15 * DAY);
    expect((await reg('alice', 'device-bbbb2222')).isRewardDevice).toBe(true);
    expect((await userDoc('alice')).rewardDeviceId).toBe('device-bbbb2222');
    expect((await getDoc('users/alice/devices/device-aaaa1111'))?.isRewardDevice).toBe(false);
  });

  test.each([
    ['short id', { deviceId: 'abc' }],
    ['bad chars', { deviceId: 'device/../../x' }],
    ['missing model', { model: '' }],
  ])('validation: %s', async (_n, over) => {
    await makeUser('alice');
    await expectError(reg('alice', 'device-aaaa1111', over), 'invalid-argument');
  });

  test('requires a profile', async () => {
    await expectError(reg('ghost', 'device-aaaa1111'), 'failed-precondition', 'PROFILE_REQUIRED');
  });
});

describe('requestAccountDeletion', () => {
  test('marks the account, hides the public profile, queues an admin item once, and blocks further use', async () => {
    await makeUser('alice');
    await handleRequestAccountDeletion(authReq('alice', {}));
    expect((await userDoc('alice')).status).toBe('DELETION_REQUESTED');
    expect(await getDoc('publicProfiles/alice')).toMatchObject({ discoverable: false, showOnLeaderboards: false });
    expect(await getDoc('reports/deletion_alice')).toMatchObject({ reason: 'ACCOUNT_DELETION', status: 'OPEN', targetUid: 'alice' });
    await expectError(handleUpdateProfile(authReq('alice', { bio: 'x' })), 'permission-denied', 'ACCOUNT_DELETION_REQUESTED');
    await expectError(handleSyncStepBuckets(authReq('alice', { deviceId: 'device-aaaa1111', buckets: [] })), 'permission-denied', 'ACCOUNT_DELETION_REQUESTED');
  });

  test('a user with a pending deletion can still read (leaderboard, notifications, challenge leaderboard); repeating the request is idempotent', async () => {
    await makeUser('alice');
    await handleRequestAccountDeletion(authReq('alice', {}));
    expect(await handleRequestAccountDeletion(authReq('alice', {}))).toEqual({ ok: true });
    const lb = await handleGetLeaderboard(authReq('alice', { scope: 'CAMPUS', period: 'DAILY' }));
    expect(lb).toMatchObject({ entries: [], me: { rank: null, value: 0 } });
    expect(await handleMarkNotificationsRead(authReq('alice', {}))).toMatchObject({ ok: true });
    expect(await handleGetChallengeLeaderboard(authReq('alice', { challengeId: 'tpl_streak-7' }))).toMatchObject({ entries: [], me: { rank: null, value: 0 } });
    // mutating / social callables are refused with a clear reason
    await expectError(handleSearchBuddies(authReq('alice', {})), 'permission-denied', 'ACCOUNT_DELETION_REQUESTED');
  });
});
