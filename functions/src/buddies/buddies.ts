import {
  BUDDY_TYPES,
  COL,
  FITNESS_LEVELS,
  MAX_PENDING_BUDDY_REQUESTS,
  PREFERRED_TIMES,
  REPORT_REASONS,
  WEEKDAYS,
} from '../config';
import { Req, requireEligibleUser } from '../lib/auth';
import { nowMs } from '../lib/clock';
import { fail } from '../lib/errors';
import { db, FieldValue } from '../lib/firebase';
import { getSettings } from '../lib/settings';
import { dayKeyOf } from '../lib/time';
import { asRecord, bool, id, limitParam, oneOf, optOneOf, optStr, optStrArray, str } from '../lib/validate';
import { notify } from '../notifications/notify';

export function requestDocId(fromUid: string, toUid: string): string {
  return `${fromUid}_${toUid}`;
}

export function connectionDocId(a: string, b: string): string {
  return a < b ? `${a}_${b}` : `${b}_${a}`;
}

export function sortedPair(a: string, b: string): [string, string] {
  return a < b ? [a, b] : [b, a];
}

/** Active buddy connection between two users? */
export async function areActiveBuddies(a: string, b: string): Promise<boolean> {
  const s = await db().collection(COL.buddyConnections).doc(connectionDocId(a, b)).get();
  return s.exists && s.data()?.active === true;
}

// ---------------------------------------------------------------------------------------------------------------

export type Relation = 'NONE' | 'REQUEST_SENT' | 'REQUEST_RECEIVED' | 'BUDDY';

export async function handleSearchBuddies(req: Req): Promise<{ profiles: Array<Record<string, unknown>>; nextCursor: string | null }> {
  const caller = await requireEligibleUser(req);
  const d = asRecord(req.data);
  const fitnessLevel = optOneOf(d, 'fitnessLevel', FITNESS_LEVELS);
  const hostelId = optStr(d, 'hostelId', { max: 64 });
  const preferredTime = optOneOf(d, 'preferredTime', PREFERRED_TIMES);
  const buddyType = optOneOf(d, 'buddyType', BUDDY_TYPES);
  const sports = optStrArray(d, 'sports', { maxItems: 20, maxLen: 40 });
  const goals = optStrArray(d, 'goals', { maxItems: 10, maxLen: 40 });
  const availability = optStrArray(d, 'availability', { maxItems: 7, maxLen: 3, allowed: WEEKDAYS });
  const text = optStr(d, 'query', { max: 60 })?.toLowerCase();
  const limit = limitParam(d, 20, 50);
  const cursor = optStr(d, 'cursor', { max: 128 });

  let q: FirebaseFirestore.Query = db().collection(COL.publicProfiles).where('discoverable', '==', true);
  if (fitnessLevel) q = q.where('fitnessLevel', '==', fitnessLevel);
  if (hostelId) q = q.where('hostelId', '==', hostelId);
  if (preferredTime) q = q.where('preferredTime', '==', preferredTime);
  if (buddyType) q = q.where('buddyType', '==', buddyType);
  q = q.orderBy('__name__');

  const matches: Array<{ uid: string; data: FirebaseFirestore.DocumentData }> = [];
  let last: string | null = cursor ?? null;
  let exhausted = false;
  let scanned = 0;
  let stoppedEarly = false;
  while (matches.length < limit && !exhausted && scanned < 600) {
    let page = q.limit(100);
    if (last) page = page.startAfter(last);
    const snap = await page.get();
    if (snap.empty) {
      exhausted = true;
      break;
    }
    for (const doc of snap.docs) {
      scanned++;
      last = doc.id;
      if (doc.id === caller.uid) continue;
      const p = doc.data();
      if (sports?.length && !sports.some((s) => (p.sportsInterests as string[] | undefined)?.includes(s))) continue;
      if (goals?.length && !goals.some((g) => (p.goals as string[] | undefined)?.includes(g))) continue;
      if (availability?.length && !availability.some((a) => (p.availability as string[] | undefined)?.includes(a))) continue;
      if (text && !String(p.displayName ?? '').toLowerCase().includes(text)) continue;
      matches.push({ uid: doc.id, data: p });
      if (matches.length >= limit) {
        stoppedEarly = true;
        break;
      }
    }
    if (!stoppedEarly && snap.size < 100) exhausted = true;
  }
  const hasMore = !exhausted;

  const firestore = db();
  const refs: FirebaseFirestore.DocumentReference[] = [];
  for (const m of matches) {
    refs.push(firestore.collection(COL.buddyRequests).doc(requestDocId(caller.uid, m.uid)));
    refs.push(firestore.collection(COL.buddyRequests).doc(requestDocId(m.uid, caller.uid)));
    refs.push(firestore.collection(COL.buddyConnections).doc(connectionDocId(caller.uid, m.uid)));
  }
  const snaps = refs.length ? await firestore.getAll(...refs) : [];
  const profiles = matches.map((m, i) => {
    const sent = snaps[i * 3].data();
    const recv = snaps[i * 3 + 1].data();
    const conn = snaps[i * 3 + 2].data();
    let relation: Relation = 'NONE';
    if (conn?.active === true) relation = 'BUDDY';
    else if (sent?.status === 'PENDING') relation = 'REQUEST_SENT';
    else if (recv?.status === 'PENDING') relation = 'REQUEST_RECEIVED';
    const { updatedAt: _u, ...pub } = m.data;
    return { uid: m.uid, ...pub, relation };
  });
  return { profiles, nextCursor: hasMore && matches.length > 0 ? last : null };
}

// ---------------------------------------------------------------------------------------------------------------

export async function handleSendBuddyRequest(req: Req): Promise<{ ok: true; requestId: string }> {
  const caller = await requireEligibleUser(req);
  const d = asRecord(req.data);
  const toUid = id(d, 'toUid');
  const message = optStr(d, 'message', { max: 120 }) ?? '';
  if (toUid === caller.uid) fail('invalid-argument', 'CANNOT_REQUEST_SELF');
  const settings = await getSettings();
  const cooldownMs = settings.buddyRerequestCooldownHours * 3_600_000;
  const now = nowMs();

  const firestore = db();
  const reqRef = firestore.collection(COL.buddyRequests).doc(requestDocId(caller.uid, toUid));
  const reverseRef = firestore.collection(COL.buddyRequests).doc(requestDocId(toUid, caller.uid));
  const connRef = firestore.collection(COL.buddyConnections).doc(connectionDocId(caller.uid, toUid));
  const targetUser = firestore.collection(COL.users).doc(toUid);
  const targetPub = firestore.collection(COL.publicProfiles).doc(toUid);

  const pending = await firestore
    .collection(COL.buddyRequests)
    .where('fromUid', '==', caller.uid)
    .where('status', '==', 'PENDING')
    .count()
    .get();
  if (pending.data().count >= MAX_PENDING_BUDDY_REQUESTS) fail('resource-exhausted', 'TOO_MANY_PENDING_REQUESTS');

  const requestId = requestDocId(caller.uid, toUid);
  const createdMs = await firestore.runTransaction(async (tx) => {
    const [rSnap, revSnap, cSnap, tUser, tPub] = await tx.getAll(reqRef, reverseRef, connRef, targetUser, targetPub);
    if (!tUser.exists || tUser.data()?.status !== 'ACTIVE') fail('not-found', 'TARGET_NOT_FOUND', 'student not found');
    if (tPub.data()?.discoverable !== true) fail('failed-precondition', 'TARGET_NOT_DISCOVERABLE', 'student is not accepting requests');
    if (cSnap.exists && cSnap.data()?.active === true) fail('already-exists', 'ALREADY_BUDDIES');
    if (revSnap.exists && revSnap.data()?.status === 'PENDING') fail('already-exists', 'REVERSE_REQUEST_PENDING', 'this student already sent you a request');
    if (rSnap.exists) {
      const r = rSnap.data() as FirebaseFirestore.DocumentData;
      if (r.status === 'PENDING') fail('already-exists', 'REQUEST_PENDING');
      const respondedMs = (r.respondedAt?.toMillis?.() as number | undefined) ?? 0;
      if (now - respondedMs < cooldownMs) fail('resource-exhausted', 'REQUEST_COOLDOWN', 'try again later');
    }
    tx.set(reqRef, {
      fromUid: caller.uid,
      toUid,
      status: 'PENDING',
      message,
      fromName: caller.user.displayName,
      fromPhotoUrl: caller.user.photoUrl ?? null,
      createdAt: FieldValue.serverTimestamp(),
      respondedAt: null,
    });
    return now;
  });
  await notify({
    uid: toUid,
    type: 'BUDDY_REQUEST',
    title: 'New buddy request',
    body: `${caller.user.displayName} wants to be your fitness buddy.`,
    data: { requestId, fromUid: caller.uid },
    dedupeKey: `buddyreq_${requestId}_${createdMs}`,
  });
  return { ok: true, requestId };
}

export async function handleRespondBuddyRequest(req: Req): Promise<{ ok: true }> {
  const caller = await requireEligibleUser(req);
  const d = asRecord(req.data);
  const requestId = str(d, 'requestId', { min: 3, max: 260, pattern: /^[A-Za-z0-9_-]+$/ });
  const accept = bool(d, 'accept');
  const firestore = db();
  const reqRef = firestore.collection(COL.buddyRequests).doc(requestId);

  const fromUid = await firestore.runTransaction(async (tx) => {
    const snap = await tx.get(reqRef);
    if (!snap.exists) fail('not-found', 'REQUEST_NOT_FOUND');
    const r = snap.data() as FirebaseFirestore.DocumentData;
    if (r.toUid !== caller.uid) fail('permission-denied', 'NOT_REQUEST_RECIPIENT');
    const desired = accept ? 'ACCEPTED' : 'REJECTED';
    if (r.status === desired) return null; // idempotent repeat
    if (r.status !== 'PENDING') fail('failed-precondition', 'REQUEST_NOT_PENDING');
    const connRef = firestore.collection(COL.buddyConnections).doc(connectionDocId(r.fromUid, r.toUid));
    tx.update(reqRef, { status: desired, respondedAt: FieldValue.serverTimestamp() });
    if (accept) {
      tx.set(connRef, { uids: sortedPair(r.fromUid, r.toUid), active: true, createdAt: FieldValue.serverTimestamp() });
    }
    return accept ? (r.fromUid as string) : null;
  });
  if (fromUid) {
    await notify({
      uid: fromUid,
      type: 'BUDDY_ACCEPTED',
      title: 'Buddy request accepted',
      body: `${caller.user.displayName} accepted your buddy request.`,
      data: { buddyUid: caller.uid },
      dedupeKey: `buddyacc_${requestId}`,
    });
  }
  return { ok: true };
}

export async function handleCancelBuddyRequest(req: Req): Promise<{ ok: true }> {
  const caller = await requireEligibleUser(req);
  const d = asRecord(req.data);
  const requestId = str(d, 'requestId', { min: 3, max: 260, pattern: /^[A-Za-z0-9_-]+$/ });
  const reqRef = db().collection(COL.buddyRequests).doc(requestId);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(reqRef);
    if (!snap.exists) fail('not-found', 'REQUEST_NOT_FOUND');
    const r = snap.data() as FirebaseFirestore.DocumentData;
    if (r.fromUid !== caller.uid) fail('permission-denied', 'NOT_REQUEST_SENDER');
    if (r.status === 'CANCELLED') return;
    if (r.status !== 'PENDING') fail('failed-precondition', 'REQUEST_NOT_PENDING');
    tx.update(reqRef, { status: 'CANCELLED', respondedAt: FieldValue.serverTimestamp() });
  });
  return { ok: true };
}

export async function handleRemoveBuddy(req: Req): Promise<{ ok: true }> {
  const caller = await requireEligibleUser(req);
  const d = asRecord(req.data);
  const buddyUid = id(d, 'buddyUid');
  if (buddyUid === caller.uid) fail('invalid-argument', 'INVALID_BUDDY_UID');
  const ref = db().collection(COL.buddyConnections).doc(connectionDocId(caller.uid, buddyUid));
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) fail('not-found', 'NOT_BUDDIES');
    if (snap.data()?.active !== true) return; // idempotent
    tx.update(ref, { active: false, removedAt: FieldValue.serverTimestamp() });
  });
  return { ok: true };
}

export async function handleReportProfile(req: Req): Promise<{ ok: true }> {
  const caller = await requireEligibleUser(req);
  const d = asRecord(req.data);
  const targetUid = id(d, 'targetUid');
  const reason = oneOf(d, 'reason', REPORT_REASONS);
  const details = optStr(d, 'details', { max: 500 }) ?? '';
  if (targetUid === caller.uid) fail('invalid-argument', 'CANNOT_REPORT_SELF');
  const target = await db().collection(COL.users).doc(targetUid).get();
  if (!target.exists) fail('not-found', 'TARGET_NOT_FOUND');
  // One report per reporter/target/day: retries and spam collapse into one queue item.
  const reportId = `${caller.uid}_${targetUid}_${dayKeyOf(nowMs())}`;
  try {
    await db().collection(COL.reports).doc(reportId).create({
      reporterUid: caller.uid,
      targetUid,
      reason,
      details,
      status: 'OPEN',
      resolvedBy: null,
      createdAt: FieldValue.serverTimestamp(),
      resolvedAt: null,
    });
  } catch (e) {
    if ((e as { code?: number }).code !== 6) throw e;
  }
  return { ok: true };
}
