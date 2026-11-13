import {
  handleCancelBuddyRequest,
  handleRemoveBuddy,
  handleReportProfile,
  handleRespondBuddyRequest,
  handleSearchBuddies,
  handleSendBuddyRequest,
} from '../../../src/buddies/buddies';
import { setClock } from '../../../src/lib/clock';
import { db } from '../../../src/lib/firebase';
import { handleUpdateProfile } from '../../../src/profile/profile';
import { authReq, DAY, expectError, getDoc, makeUser, resetAll } from '../helpers/env';

beforeEach(async () => {
  await resetAll();
  await makeUser('alice');
  await makeUser('bob', { fitnessLevel: 'BEGINNER', sportsInterests: ['Yoga'], hostelId: 'ira' });
  await makeUser('carol', { fitnessLevel: 'ADVANCED', sportsInterests: ['Running'], availability: ['SAT'], hostelId: 'agira' });
});
afterAll(() => setClock(null));

const send = (from: string, to: string, message?: string) => handleSendBuddyRequest(authReq(from, { toUid: to, message }));
const respond = (uid: string, requestId: string, accept: boolean) => handleRespondBuddyRequest(authReq(uid, { requestId, accept }));
const notifications = async (uid: string) => (await db().collection('notifications').where('uid', '==', uid).get()).docs.map((d) => d.data());

describe('buddy requests', () => {
  test('send creates a PENDING request with a deterministic id and notifies the recipient once', async () => {
    const r = await send('alice', 'bob', 'lets walk');
    expect(r).toEqual({ ok: true, requestId: 'alice_bob' });
    expect(await getDoc('buddyRequests/alice_bob')).toMatchObject({ fromUid: 'alice', toUid: 'bob', status: 'PENDING', message: 'lets walk', fromName: 'User alice', respondedAt: null });
    const n = await notifications('bob');
    expect(n).toHaveLength(1);
    expect(n[0]).toMatchObject({ type: 'BUDDY_REQUEST', read: false });
    // the notification carries no private data (no email / points)
    expect(JSON.stringify(n[0])).not.toContain('@thapar.edu');
  });

  test('duplicate pending request is rejected (already-exists REQUEST_PENDING); reverse request is blocked too', async () => {
    await send('alice', 'bob');
    await expectError(send('alice', 'bob'), 'already-exists', 'REQUEST_PENDING');
    await expectError(send('bob', 'alice'), 'already-exists', 'REVERSE_REQUEST_PENDING');
    expect((await db().collection('buddyRequests').get()).size).toBe(1);
  });

  test('cannot request yourself, a missing user, or a non-discoverable student', async () => {
    await expectError(send('alice', 'alice'), 'invalid-argument', 'CANNOT_REQUEST_SELF');
    await expectError(send('alice', 'ghost'), 'not-found', 'TARGET_NOT_FOUND');
    await handleUpdateProfile(authReq('bob', { privacy: { discoverable: false } }));
    await expectError(send('alice', 'bob'), 'failed-precondition', 'TARGET_NOT_DISCOVERABLE');
  });

  test('accept creates an active connection (sorted ids) and notifies the sender', async () => {
    await send('bob', 'alice');
    await respond('alice', 'bob_alice', true);
    expect(await getDoc('buddyRequests/bob_alice')).toMatchObject({ status: 'ACCEPTED' });
    expect(await getDoc('buddyConnections/alice_bob')).toMatchObject({ uids: ['alice', 'bob'], active: true });
    expect((await notifications('bob')).map((n) => n.type)).toContain('BUDDY_ACCEPTED');
    await expectError(send('alice', 'bob'), 'already-exists', 'ALREADY_BUDDIES');
  });

  test('accepting twice is idempotent; responding to a different decision afterwards fails', async () => {
    await send('alice', 'bob');
    await respond('bob', 'alice_bob', true);
    await respond('bob', 'alice_bob', true);
    await expectError(respond('bob', 'alice_bob', false), 'failed-precondition', 'REQUEST_NOT_PENDING');
    expect((await db().collection('notifications').where('uid', '==', 'alice').get()).size).toBe(1);
  });

  test('reject sets REJECTED and creates no connection', async () => {
    await send('alice', 'bob');
    await respond('bob', 'alice_bob', false);
    expect(await getDoc('buddyRequests/alice_bob')).toMatchObject({ status: 'REJECTED' });
    expect(await getDoc('buddyConnections/alice_bob')).toBeUndefined();
  });

  test('only the recipient can respond; only the sender can cancel', async () => {
    await send('alice', 'bob');
    await expectError(respond('carol', 'alice_bob', true), 'permission-denied', 'NOT_REQUEST_RECIPIENT');
    await expectError(respond('alice', 'alice_bob', true), 'permission-denied', 'NOT_REQUEST_RECIPIENT');
    await expectError(handleCancelBuddyRequest(authReq('bob', { requestId: 'alice_bob' })), 'permission-denied', 'NOT_REQUEST_SENDER');
    await expectError(respond('bob', 'nope_nope', true), 'not-found', 'REQUEST_NOT_FOUND');
  });

  test('cancel sets CANCELLED; re-request is blocked for 24 h then allowed (deterministic id reused)', async () => {
    await send('alice', 'bob');
    await handleCancelBuddyRequest(authReq('alice', { requestId: 'alice_bob' }));
    await handleCancelBuddyRequest(authReq('alice', { requestId: 'alice_bob' })); // idempotent
    expect(await getDoc('buddyRequests/alice_bob')).toMatchObject({ status: 'CANCELLED' });
    await expectError(send('alice', 'bob'), 'resource-exhausted', 'REQUEST_COOLDOWN');
    setClock(() => Date.now() + 25 * 3_600_000);
    await send('alice', 'bob');
    expect(await getDoc('buddyRequests/alice_bob')).toMatchObject({ status: 'PENDING' });
    expect((await db().collection('buddyRequests').get()).size).toBe(1);
    expect((await notifications('bob')).filter((n) => n.type === 'BUDDY_REQUEST')).toHaveLength(2);
  });

  test('after a rejection the cooldown also applies; cancelling an answered request fails', async () => {
    await send('alice', 'bob');
    await respond('bob', 'alice_bob', false);
    await expectError(send('alice', 'bob'), 'resource-exhausted', 'REQUEST_COOLDOWN');
    await expectError(handleCancelBuddyRequest(authReq('alice', { requestId: 'alice_bob' })), 'failed-precondition', 'REQUEST_NOT_PENDING');
  });
});

describe('removing a buddy', () => {
  test('remove deactivates the connection (idempotent) and a new request is possible after the cooldown', async () => {
    await send('alice', 'bob');
    await respond('bob', 'alice_bob', true);
    await handleRemoveBuddy(authReq('bob', { buddyUid: 'alice' }));
    await handleRemoveBuddy(authReq('alice', { buddyUid: 'bob' }));
    expect(await getDoc('buddyConnections/alice_bob')).toMatchObject({ active: false });
    await expectError(handleRemoveBuddy(authReq('alice', { buddyUid: 'carol' })), 'not-found', 'NOT_BUDDIES');
    setClock(() => Date.now() + 25 * 3_600_000);
    await send('alice', 'bob');
    expect(await getDoc('buddyRequests/alice_bob')).toMatchObject({ status: 'PENDING' });
    void DAY;
  });
});

describe('searchBuddies', () => {
  test('excludes self, returns only public fields and the relation', async () => {
    await send('alice', 'bob');
    const r = await handleSearchBuddies(authReq('alice', {}));
    const uids = r.profiles.map((p) => p.uid).sort();
    expect(uids).toEqual(['bob', 'carol']);
    const bob = r.profiles.find((p) => p.uid === 'bob') as Record<string, unknown>;
    expect(bob.relation).toBe('REQUEST_SENT');
    expect((r.profiles.find((p) => p.uid === 'carol') as Record<string, unknown>).relation).toBe('NONE');
    for (const p of r.profiles) for (const k of ['email', 'pointsBalance', 'status', 'role']) expect(p).not.toHaveProperty(k);
    const asBob = await handleSearchBuddies(authReq('bob', {}));
    expect((asBob.profiles.find((p) => p.uid === 'alice') as Record<string, unknown>).relation).toBe('REQUEST_RECEIVED');
  });

  test('BUDDY relation after accept', async () => {
    await send('alice', 'bob');
    await respond('bob', 'alice_bob', true);
    const r = await handleSearchBuddies(authReq('alice', {}));
    expect((r.profiles.find((p) => p.uid === 'bob') as Record<string, unknown>).relation).toBe('BUDDY');
  });

  test('filters: fitness level, hostel, sports, availability, text query', async () => {
    const q = async (f: Record<string, unknown>) => (await handleSearchBuddies(authReq('alice', f))).profiles.map((p) => p.uid);
    expect(await q({ fitnessLevel: 'BEGINNER' })).toEqual(['bob']);
    expect(await q({ hostelId: 'agira' })).toEqual(['carol']);
    expect(await q({ sports: ['Yoga'] })).toEqual(['bob']);
    expect(await q({ sports: ['Running', 'Yoga'] })).toEqual(['bob', 'carol']);
    expect(await q({ availability: ['SAT'] })).toEqual(['carol']);
    expect(await q({ query: 'CAR' })).toEqual(['carol']);
    expect(await q({ fitnessLevel: 'ADVANCED', sports: ['Yoga'] })).toEqual([]);
  });

  test('non-discoverable students and hidden hostels are not searchable by those fields', async () => {
    await handleUpdateProfile(authReq('bob', { privacy: { discoverable: false } }));
    await handleUpdateProfile(authReq('carol', { privacy: { showHostel: false } }));
    expect((await handleSearchBuddies(authReq('alice', {}))).profiles.map((p) => p.uid)).toEqual(['carol']);
    expect((await handleSearchBuddies(authReq('alice', { hostelId: 'agira' }))).profiles).toEqual([]);
  });

  test('pagination with limit and cursor returns every profile exactly once', async () => {
    for (const u of ['d1', 'd2', 'd3']) await makeUser(u);
    const seen: string[] = [];
    let cursor: string | null = null;
    for (let i = 0; i < 10; i++) {
      const r: { profiles: Array<Record<string, unknown>>; nextCursor: string | null } = await handleSearchBuddies(authReq('alice', { limit: 2, cursor: cursor ?? undefined }));
      seen.push(...r.profiles.map((p) => String(p.uid)));
      cursor = r.nextCursor;
      if (!cursor) break;
    }
    expect(seen.sort()).toEqual(['bob', 'carol', 'd1', 'd2', 'd3']);
  });

  test('invalid filter values are rejected', async () => {
    await expectError(handleSearchBuddies(authReq('alice', { fitnessLevel: 'GOD' })), 'invalid-argument', 'INVALID_FITNESS_LEVEL');
  });
});

describe('reportProfile', () => {
  test('creates one OPEN report per reporter/target/day (retries collapse); cannot report self or unknown users', async () => {
    await handleReportProfile(authReq('alice', { targetUid: 'bob', reason: 'SPAM', details: 'x' }));
    await handleReportProfile(authReq('alice', { targetUid: 'bob', reason: 'SPAM', details: 'again' }));
    const reports = await db().collection('reports').get();
    expect(reports.size).toBe(1);
    expect(reports.docs[0].data()).toMatchObject({ reporterUid: 'alice', targetUid: 'bob', reason: 'SPAM', status: 'OPEN' });
    await expectError(handleReportProfile(authReq('alice', { targetUid: 'alice', reason: 'SPAM' })), 'invalid-argument', 'CANNOT_REPORT_SELF');
    await expectError(handleReportProfile(authReq('alice', { targetUid: 'ghost', reason: 'SPAM' })), 'not-found', 'TARGET_NOT_FOUND');
    await expectError(handleReportProfile(authReq('alice', { targetUid: 'bob', reason: 'WHATEVER' })), 'invalid-argument', 'INVALID_REASON');
  });
});
