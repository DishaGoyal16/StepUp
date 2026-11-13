import { COL, DAY_MS } from '../config';
import { Req, requireEligibleUser } from '../lib/auth';
import { nowMs } from '../lib/clock';
import { fail } from '../lib/errors';
import { db, FieldValue, tsFromMs } from '../lib/firebase';
import { toJson } from '../lib/json';
import { getSettings } from '../lib/settings';
import { dayKeyOf, nextIstMidnightMs } from '../lib/time';
import { asRecord, bool, id, int, limitParam, optStr } from '../lib/validate';
import { areActiveBuddies, sortedPair } from '../buddies/buddies';
import { notify } from '../notifications/notify';
import { loadUserDays } from '../steps/summaries';
import { aggregateHostel } from '../leaderboards/aggregate';
import { Metric, metricLabel, rollingWindow } from './progress';
import { participantDocId, updateChallengeProgressForUser } from './service';

function participantDoc(
  challengeId: string,
  uid: string,
  user: FirebaseFirestore.DocumentData,
  status: 'INVITED' | 'JOINED',
  window?: [string, string],
): Record<string, unknown> {
  return {
    challengeId,
    uid,
    displayName: user.displayName,
    photoUrl: user.photoUrl ?? null,
    hostelId: user.hostelId ?? null,
    status,
    joinedAt: status === 'JOINED' ? FieldValue.serverTimestamp() : null,
    windowStart: window ? window[0] : null,
    windowEnd: window ? window[1] : null,
    progress: 0,
    progressUpdatedAt: null,
    completedAt: null,
    rewardPaid: false,
  };
}

export async function handleCreateBuddyChallenge(req: Req): Promise<{ challengeId: string }> {
  const caller = await requireEligibleUser(req);
  const d = asRecord(req.data);
  const buddyUid = id(d, 'buddyUid');
  const durationDays = int(d, 'durationDays', 1, 30);
  const targetSteps = int(d, 'targetSteps', 1000, 1_000_000);
  const title = optStr(d, 'title', { max: 80 });
  if (buddyUid === caller.uid) fail('invalid-argument', 'INVALID_BUDDY_UID');
  if (!(await areActiveBuddies(caller.uid, buddyUid))) fail('failed-precondition', 'NOT_BUDDIES', 'you can only challenge an active buddy');

  const firestore = db();
  const buddySnap = await firestore.collection(COL.users).doc(buddyUid).get();
  if (!buddySnap.exists || buddySnap.data()?.status !== 'ACTIVE') fail('failed-precondition', 'BUDDY_NOT_ACTIVE');
  const buddy = buddySnap.data() as FirebaseFirestore.DocumentData;

  const pair = sortedPair(caller.uid, buddyUid);
  const pending = await firestore
    .collection(COL.challenges)
    .where('type', '==', 'BUDDY')
    .where('status', '==', 'PENDING')
    .where('participantUids', '==', pair)
    .limit(1)
    .get();
  if (!pending.empty) fail('already-exists', 'PENDING_INVITE_EXISTS', 'a pending challenge with this buddy already exists');

  const settings = await getSettings();
  const ref = firestore.collection(COL.challenges).doc();
  const batch = firestore.batch();
  batch.create(ref, {
    type: 'BUDDY',
    title: title || `${caller.user.displayName} vs ${buddy.displayName}`,
    description: `First to ${targetSteps} verified steps within ${durationDays} day(s).`,
    metric: 'TOTAL_STEPS',
    target: targetSteps,
    dailyTarget: null,
    windowMode: 'FIXED',
    startAt: null,
    endAt: null,
    durationDays,
    status: 'PENDING',
    createdBy: caller.uid,
    participantUids: pair,
    hostelIds: [],
    hostelAggregation: 'AVERAGE_PER_PARTICIPANT',
    maxParticipants: 2,
    participantCount: 1,
    rewardPoints: settings.pointsChallengeWin,
    isTemplate: false,
    winnerUid: null,
    winnerHostelId: null,
    finalizedAt: null,
    rewardsPending: false,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  batch.create(firestore.collection(COL.challengeParticipants).doc(participantDocId(ref.id, caller.uid)), participantDoc(ref.id, caller.uid, caller.user, 'JOINED'));
  batch.create(firestore.collection(COL.challengeParticipants).doc(participantDocId(ref.id, buddyUid)), participantDoc(ref.id, buddyUid, buddy, 'INVITED'));
  await batch.commit();

  await notify({
    uid: buddyUid,
    type: 'CHALLENGE_NEW',
    title: 'Buddy challenge invite',
    body: `${caller.user.displayName} challenged you to ${targetSteps} steps in ${durationDays} day(s).`,
    data: { challengeId: ref.id },
    dedupeKey: `buddychal_${ref.id}`,
  });
  return { challengeId: ref.id };
}

export async function handleRespondChallengeInvite(req: Req): Promise<{ ok: true }> {
  const caller = await requireEligibleUser(req);
  const d = asRecord(req.data);
  const challengeId = id(d, 'challengeId');
  const accept = bool(d, 'accept');
  const firestore = db();
  const chRef = firestore.collection(COL.challenges).doc(challengeId);
  const myRef = firestore.collection(COL.challengeParticipants).doc(participantDocId(challengeId, caller.uid));
  const now = nowMs();

  const creator = await firestore.runTransaction(async (tx) => {
    const [chSnap, mySnap] = await tx.getAll(chRef, myRef);
    if (!chSnap.exists || chSnap.data()?.type !== 'BUDDY') fail('not-found', 'CHALLENGE_NOT_FOUND');
    if (!mySnap.exists) fail('permission-denied', 'NOT_INVITED');
    const ch = chSnap.data() as FirebaseFirestore.DocumentData;
    const me = mySnap.data() as FirebaseFirestore.DocumentData;
    if (ch.createdBy === caller.uid) fail('permission-denied', 'NOT_INVITED');
    if (ch.status !== 'PENDING') {
      // Idempotent repeats of the same decision.
      if (accept && me.status === 'JOINED') return null;
      if (!accept && ch.status === 'CANCELLED' && me.status === 'LEFT') return null;
      fail('failed-precondition', 'INVITE_NOT_PENDING');
    }
    if (me.status !== 'INVITED') fail('failed-precondition', 'INVITE_NOT_PENDING');
    if (accept) {
      const startMs = nextIstMidnightMs(now);
      tx.update(chRef, {
        status: 'UPCOMING',
        startAt: tsFromMs(startMs),
        endAt: tsFromMs(startMs + ch.durationDays * DAY_MS),
        participantCount: 2,
        updatedAt: FieldValue.serverTimestamp(),
      });
      tx.update(myRef, { status: 'JOINED', joinedAt: FieldValue.serverTimestamp() });
    } else {
      tx.update(chRef, { status: 'CANCELLED', updatedAt: FieldValue.serverTimestamp() });
      tx.update(myRef, { status: 'LEFT' });
    }
    return accept ? (ch.createdBy as string) : null;
  });
  if (creator) {
    await notify({
      uid: creator,
      type: 'CHALLENGE_NEW',
      title: 'Buddy challenge accepted',
      body: `${caller.user.displayName} accepted your challenge. It starts at midnight.`,
      data: { challengeId },
      dedupeKey: `buddychalacc_${challengeId}`,
    });
  }
  return { ok: true };
}

export async function handleJoinChallenge(req: Req): Promise<{ ok: true; participant: unknown }> {
  const caller = await requireEligibleUser(req);
  const d = asRecord(req.data);
  const challengeId = id(d, 'challengeId');
  const firestore = db();
  const chRef = firestore.collection(COL.challenges).doc(challengeId);
  const pRef = firestore.collection(COL.challengeParticipants).doc(participantDocId(challengeId, caller.uid));
  const now = nowMs();

  await firestore.runTransaction(async (tx) => {
    const [chSnap, pSnap, uSnap] = await tx.getAll(chRef, pRef, firestore.collection(COL.users).doc(caller.uid));
    if (!chSnap.exists) fail('not-found', 'CHALLENGE_NOT_FOUND');
    const ch = chSnap.data() as FirebaseFirestore.DocumentData;
    if (ch.type === 'BUDDY') fail('failed-precondition', 'USE_INVITE_FLOW', 'buddy challenges are joined through the invite');
    const user = uSnap.data() as FirebaseFirestore.DocumentData;
    if (user.status !== 'ACTIVE') fail('permission-denied', 'ACCOUNT_NOT_ACTIVE');
    const joinable = ch.windowMode === 'ROLLING' ? ch.status === 'ACTIVE' : ch.status === 'ACTIVE' || ch.status === 'UPCOMING';
    if (!joinable) fail('failed-precondition', 'CHALLENGE_NOT_JOINABLE');
    if (ch.windowMode === 'FIXED' && (ch.endAt?.toMillis?.() ?? 0) <= now) fail('failed-precondition', 'CHALLENGE_ENDED');
    if (ch.type === 'INTER_HOSTEL' && !(ch.hostelIds as string[]).includes(user.hostelId)) {
      fail('permission-denied', 'HOSTEL_NOT_ELIGIBLE', 'your hostel is not part of this challenge');
    }
    const existing = pSnap.data();
    if (existing?.status === 'JOINED') fail('already-exists', 'ALREADY_JOINED');
    if (existing?.status === 'COMPLETED') fail('already-exists', 'ALREADY_COMPLETED');
    if (ch.maxParticipants && ch.participantCount >= ch.maxParticipants) fail('resource-exhausted', 'CHALLENGE_FULL');
    const window = ch.windowMode === 'ROLLING' ? rollingWindow(dayKeyOf(now), ch.durationDays) : undefined;
    tx.set(pRef, participantDoc(challengeId, caller.uid, user, 'JOINED', window));
    tx.update(chRef, { participantCount: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() });
  });

  // Steps already walked inside the window (e.g. earlier today) count immediately.
  await updateChallengeProgressForUser(caller.uid, await loadUserDays(caller.uid));
  const snap = await pRef.get();
  return { ok: true, participant: toJson(snap.data()) };
}

export async function handleLeaveChallenge(req: Req): Promise<{ ok: true; participant: unknown }> {
  const caller = await requireEligibleUser(req);
  const d = asRecord(req.data);
  const challengeId = id(d, 'challengeId');
  const firestore = db();
  const chRef = firestore.collection(COL.challenges).doc(challengeId);
  const pRef = firestore.collection(COL.challengeParticipants).doc(participantDocId(challengeId, caller.uid));
  await firestore.runTransaction(async (tx) => {
    const [chSnap, pSnap] = await tx.getAll(chRef, pRef);
    if (!chSnap.exists || !pSnap.exists) fail('not-found', 'NOT_PARTICIPANT');
    const ch = chSnap.data() as FirebaseFirestore.DocumentData;
    const p = pSnap.data() as FirebaseFirestore.DocumentData;
    if (p.status === 'LEFT') return; // idempotent
    if (ch.type === 'BUDDY') fail('failed-precondition', 'CANNOT_LEAVE_BUDDY_CHALLENGE');
    if (p.status === 'COMPLETED') fail('failed-precondition', 'ALREADY_COMPLETED');
    if (p.status !== 'JOINED') fail('failed-precondition', 'NOT_JOINED');
    if (ch.status === 'COMPLETED') fail('failed-precondition', 'CHALLENGE_ENDED');
    tx.update(pRef, { status: 'LEFT', leftAt: FieldValue.serverTimestamp() });
    tx.update(chRef, { participantCount: FieldValue.increment(-1), updatedAt: FieldValue.serverTimestamp() });
  });
  const snap = await pRef.get();
  return { ok: true, participant: toJson(snap.data()) };
}

export interface ChallengeLeaderboard {
  entries: Array<Record<string, unknown>>;
  me: { rank: number | null; value: number };
  metricLabel: string;
}

export async function handleGetChallengeLeaderboard(req: Req): Promise<ChallengeLeaderboard> {
  const caller = await requireEligibleUser(req, { allowDeletionRequested: true });
  const d = asRecord(req.data);
  const challengeId = id(d, 'challengeId');
  const limit = limitParam(d, 50, 100);
  const firestore = db();
  const chSnap = await firestore.collection(COL.challenges).doc(challengeId).get();
  if (!chSnap.exists) fail('not-found', 'CHALLENGE_NOT_FOUND');
  const ch = chSnap.data() as FirebaseFirestore.DocumentData;
  const myPart = await firestore.collection(COL.challengeParticipants).doc(participantDocId(challengeId, caller.uid)).get();
  if (ch.type === 'BUDDY' && !myPart.exists) fail('permission-denied', 'NOT_PARTICIPANT');
  const target = Number(ch.target) || 1;
  const metric = ch.metric as Metric;

  const base = firestore.collection(COL.challengeParticipants).where('challengeId', '==', challengeId).where('status', 'in', ['JOINED', 'COMPLETED']);
  const pct = (v: number) => Math.min(100, Math.round((100 * v) / target));

  if (ch.type === 'INTER_HOSTEL') {
    const all = await base.limit(5000).get();
    const rows = all.docs.map((x) => ({ hostelId: String(x.data().hostelId ?? ''), verifiedSteps: Number(x.data().progress ?? 0) })).filter((r) => r.hostelId);
    const hostelSnap = await firestore.collection(COL.hostels).get();
    const names = new Map(hostelSnap.docs.map((h) => [h.id, String(h.data().displayName ?? h.id)]));
    const ids = new Set<string>([...((ch.hostelIds as string[]) ?? []), ...rows.map((r) => r.hostelId)]);
    const agg = [...ids].map((h) => ({ ...aggregateHostel(h, rows), name: names.get(h) ?? h }));
    const key = ch.hostelAggregation === 'TOTAL' ? 'totalVerifiedSteps' : 'averagePerParticipant';
    agg.sort((a, b) => b[key] - a[key] || b.totalVerifiedSteps - a.totalVerifiedSteps || a.hostelId.localeCompare(b.hostelId));
    let rank = 0;
    const ranked = agg.map((a, i) => {
      if (i === 0 || agg[i - 1][key] !== a[key]) rank = i + 1;
      return { rank, hostelId: a.hostelId, name: a.name, value: a[key], participants: a.participants, total: a.totalVerifiedSteps, progressPct: pct(a[key]) };
    });
    const mine = ranked.find((r) => r.hostelId === caller.user.hostelId);
    return {
      entries: ranked.slice(0, limit),
      me: { rank: mine ? mine.rank : null, value: mine ? mine.value : 0 },
      metricLabel: metricLabel(metric, ch.dailyTarget ?? null, ch.hostelAggregation),
    };
  }

  const snap = await base.orderBy('progress', 'desc').limit(limit).get();
  let rank = 0;
  let prev: number | null = null;
  // Explicit, stable tie order (Firestore breaks ties by doc id): progress desc, name, uid.
  const ordered = snap.docs
    .map((x) => x.data())
    .sort((a, b) => Number(b.progress ?? 0) - Number(a.progress ?? 0) || String(a.displayName ?? '').localeCompare(String(b.displayName ?? '')) || String(a.uid).localeCompare(String(b.uid)));
  const entries = ordered.map((p, i) => {
    const v = Number(p.progress ?? 0);
    if (prev === null || v !== prev) rank = i + 1;
    prev = v;
    return { rank, uid: p.uid, name: p.displayName, photoUrl: p.photoUrl ?? null, hostelId: p.hostelId ?? null, value: v, progressPct: pct(v) };
  });
  const my = myPart.data();
  let myRank: number | null = null;
  let myValue = 0;
  if (my && (my.status === 'JOINED' || my.status === 'COMPLETED')) {
    myValue = Number(my.progress ?? 0);
    const higher = await base.where('progress', '>', myValue).count().get();
    myRank = higher.data().count + 1;
  }
  return { entries, me: { rank: myRank, value: myValue }, metricLabel: metricLabel(metric, ch.dailyTarget ?? null) };
}
