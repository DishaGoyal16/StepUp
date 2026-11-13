import { COL, DAY_MS, DEFAULT_SETTINGS, GlobalSettings } from '../config';
import { Req, requireAdmin } from '../lib/auth';
import { nowMs } from '../lib/clock';
import { fail } from '../lib/errors';
import { admin, db, FieldValue, tsFromMs } from '../lib/firebase';
import { toJson } from '../lib/json';
import { asRecord, bool, id, int, limitParam, oneOf, optBool, optInt, optOneOf, optStr, optStrArray, str } from '../lib/validate';
import { buildPublicProfile } from '../profile/profile';
import { refreshUserBoards } from '../leaderboards/aggregate';
import { seedDefaults, SeedReport } from '../seed';
import { dayKeyOf, dayStartMs } from '../lib/time';

const HOSTEL_ID = /^[a-z0-9][a-z0-9-]{1,39}$/;

export async function handleAdminUpsertHostel(req: Req): Promise<{ ok: true }> {
  await requireAdmin(req, 'adminUpsertHostel');
  const d = asRecord(req.data);
  const hostelId = str(d, 'hostelId', { min: 2, max: 40, pattern: HOSTEL_ID });
  const data = {
    displayName: str(d, 'displayName', { min: 2, max: 80 }),
    legacyName: optStr(d, 'legacyName', { max: 40 }) || null,
    block: optStr(d, 'block', { max: 10 }) || null,
    category: oneOf(d, 'category', ['GENERAL', 'GIRLS'] as const),
    active: optBool(d, 'active') ?? true,
    sortOrder: optInt(d, 'sortOrder', 0, 10_000) ?? 999,
  };
  const ref = db().collection(COL.hostels).doc(hostelId);
  await db().runTransaction(async (tx) => {
    const s = await tx.get(ref);
    tx.set(ref, { ...data, ...(s.exists ? {} : { createdAt: FieldValue.serverTimestamp() }), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  });
  return { ok: true };
}

export async function handleAdminSetHostelActive(req: Req): Promise<{ ok: true }> {
  await requireAdmin(req, 'adminSetHostelActive');
  const d = asRecord(req.data);
  const hostelId = str(d, 'hostelId', { min: 2, max: 40, pattern: HOSTEL_ID });
  const active = bool(d, 'active');
  const ref = db().collection(COL.hostels).doc(hostelId);
  const s = await ref.get();
  if (!s.exists) fail('not-found', 'HOSTEL_NOT_FOUND');
  await ref.update({ active, updatedAt: FieldValue.serverTimestamp() });
  return { ok: true };
}

export async function handleAdminCreateChallenge(req: Req): Promise<{ challengeId: string }> {
  const caller = await requireAdmin(req, 'adminCreateChallenge');
  const d = asRecord(req.data);
  const type = oneOf(d, 'type', ['INDIVIDUAL', 'INTER_HOSTEL', 'CAMPUS'] as const);
  const metric = oneOf(d, 'metric', ['TOTAL_STEPS', 'DAILY_TARGET_DAYS', 'STREAK_DAYS'] as const);
  const windowMode = oneOf(d, 'windowMode', ['FIXED', 'ROLLING'] as const);
  const target = int(d, 'target', 1, 100_000_000);
  const dailyTarget = metric === 'TOTAL_STEPS' ? null : int(d, 'dailyTarget', 100, 100_000);
  const doc: Record<string, unknown> = {
    type,
    title: str(d, 'title', { min: 3, max: 80 }),
    description: optStr(d, 'description', { max: 400 }) ?? '',
    metric,
    target,
    dailyTarget,
    windowMode,
    hostelIds: [] as string[],
    hostelAggregation: optOneOf(d, 'hostelAggregation', ['AVERAGE_PER_PARTICIPANT', 'TOTAL'] as const) ?? 'AVERAGE_PER_PARTICIPANT',
    maxParticipants: optInt(d, 'maxParticipants', 1, 100_000) ?? null,
    participantCount: 0,
    rewardPoints: optInt(d, 'rewardPoints', 0, 100_000) ?? null,
    isTemplate: false,
    createdBy: caller.uid,
    winnerUid: null,
    winnerHostelId: null,
    finalizedAt: null,
    rewardsPending: false,
  };
  if (windowMode === 'ROLLING') {
    doc.durationDays = int(d, 'durationDays', 1, 90);
    doc.startAt = null;
    doc.endAt = null;
    doc.status = 'ACTIVE';
    if (type !== 'INDIVIDUAL') fail('invalid-argument', 'INVALID_WINDOW_MODE', 'group challenges must use a FIXED window');
  } else {
    const startMs = int(d, 'startAt', 1, 4_102_444_800_000);
    const endMs = int(d, 'endAt', 1, 4_102_444_800_000);
    if (dayStartMs(dayKeyOf(startMs)) !== startMs || dayStartMs(dayKeyOf(endMs)) !== endMs) fail('invalid-argument', 'WINDOW_NOT_DAY_ALIGNED', 'startAt/endAt must be IST midnights');
    if (endMs <= startMs) fail('invalid-argument', 'INVALID_END_AT');
    doc.startAt = tsFromMs(startMs);
    doc.endAt = tsFromMs(endMs);
    doc.durationDays = Math.round((endMs - startMs) / DAY_MS);
    const now = nowMs();
    if (endMs <= now) fail('invalid-argument', 'WINDOW_IN_PAST');
    doc.status = startMs > now ? 'UPCOMING' : 'ACTIVE';
  }
  if (type === 'INTER_HOSTEL') {
    const ids = optStrArray(d, 'hostelIds', { maxItems: 30, maxLen: 40 }) ?? [];
    if (ids.length < 2) fail('invalid-argument', 'INVALID_HOSTEL_IDS', 'select at least two hostels');
    const snaps = await db().getAll(...ids.map((h) => db().collection(COL.hostels).doc(h)));
    if (snaps.some((s) => !s.exists)) fail('invalid-argument', 'INVALID_HOSTEL_IDS', 'unknown hostel');
    doc.hostelIds = ids;
  }
  const ref = db().collection(COL.challenges).doc();
  await ref.create({ ...doc, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  return { challengeId: ref.id };
}

export async function handleAdminCancelChallenge(req: Req): Promise<{ ok: true }> {
  await requireAdmin(req, 'adminCancelChallenge');
  const d = asRecord(req.data);
  const challengeId = id(d, 'challengeId');
  const ref = db().collection(COL.challenges).doc(challengeId);
  await db().runTransaction(async (tx) => {
    const s = await tx.get(ref);
    if (!s.exists) fail('not-found', 'CHALLENGE_NOT_FOUND');
    const st = s.data()?.status;
    if (st === 'CANCELLED') return;
    if (st === 'COMPLETED') fail('failed-precondition', 'CHALLENGE_ALREADY_COMPLETED');
    tx.update(ref, { status: 'CANCELLED', updatedAt: FieldValue.serverTimestamp() });
  });
  return { ok: true };
}

export async function handleAdminListStudents(req: Req): Promise<{ students: unknown[]; nextCursor: string | null }> {
  await requireAdmin(req, 'adminListStudents');
  const d = asRecord(req.data ?? {});
  const limit = limitParam(d, 50, 200);
  const cursor = optStr(d, 'cursor', { max: 128 });
  const text = optStr(d, 'query', { max: 60 })?.toLowerCase();
  const out: unknown[] = [];
  let last: string | null = cursor ?? null;
  let more = true;
  for (let guard = 0; guard < 10 && out.length < limit && more; guard++) {
    let q = db().collection(COL.users).orderBy('__name__').limit(200);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    for (const doc of snap.docs) {
      last = doc.id;
      const u = doc.data();
      if (text && !String(u.displayName ?? '').toLowerCase().includes(text) && !String(u.email ?? '').toLowerCase().includes(text)) continue;
      out.push(
        toJson({
          uid: doc.id,
          displayName: u.displayName,
          email: u.email,
          hostelId: u.hostelId,
          status: u.status,
          role: u.role,
          pointsBalance: u.pointsBalance,
          pointsReserved: u.pointsReserved,
          lifetimeVerifiedSteps: u.lifetimeVerifiedSteps,
          createdAt: u.createdAt,
        }),
      );
      if (out.length >= limit) break;
    }
    more = snap.size === 200;
  }
  return { students: out, nextCursor: out.length >= limit || more ? last : null };
}

export async function handleAdminSetUserRole(req: Req): Promise<{ ok: true }> {
  const caller = await requireAdmin(req, 'adminSetUserRole');
  const d = asRecord(req.data);
  const uid = id(d, 'uid');
  const role = oneOf(d, 'role', ['student', 'admin'] as const);
  if (uid === caller.uid && role !== 'admin') fail('failed-precondition', 'CANNOT_DEMOTE_SELF', 'you cannot remove your own admin role');
  const auth = admin.auth();
  let record;
  try {
    record = await auth.getUser(uid);
  } catch {
    fail('not-found', 'USER_NOT_FOUND');
  }
  await auth.setCustomUserClaims(uid, { ...(record.customClaims ?? {}), admin: role === 'admin' });
  const ref = db().collection(COL.users).doc(uid);
  const s = await ref.get();
  if (s.exists) await ref.update({ role, updatedAt: FieldValue.serverTimestamp() });
  await db()
    .collection(COL.adminSettings)
    .doc('admins')
    .set({ changes: FieldValue.arrayUnion({ uid, role, by: caller.uid, atMs: nowMs() }), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  return { ok: true };
}

export async function handleAdminSuspendUser(req: Req): Promise<{ ok: true }> {
  const caller = await requireAdmin(req, 'adminSuspendUser');
  const d = asRecord(req.data);
  const uid = id(d, 'uid');
  const suspend = bool(d, 'suspend');
  const reason = optStr(d, 'reason', { max: 300 }) ?? '';
  if (uid === caller.uid) fail('failed-precondition', 'CANNOT_SUSPEND_SELF');
  const userRef = db().collection(COL.users).doc(uid);
  const pubRef = db().collection(COL.publicProfiles).doc(uid);
  await db().runTransaction(async (tx) => {
    const [u, p] = await tx.getAll(userRef, pubRef);
    if (!u.exists) fail('not-found', 'USER_NOT_FOUND');
    const cur = u.data() as FirebaseFirestore.DocumentData;
    const status = suspend ? 'SUSPENDED' : 'ACTIVE';
    tx.update(userRef, { status, suspendedReason: suspend ? reason : FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() });
    tx.set(pubRef, buildPublicProfile({ ...cur, status }, (p.data()?.weeklyVerifiedSteps as number | null | undefined) ?? 0));
  });
  await refreshUserBoards(uid, {});
  return { ok: true };
}

export async function handleAdminListReports(req: Req): Promise<{ reports: unknown[] }> {
  await requireAdmin(req, 'adminListReports');
  const d = asRecord(req.data ?? {});
  const status = optOneOf(d, 'status', ['OPEN', 'DISMISSED', 'ACTIONED'] as const);
  const limit = limitParam(d, 50, 200);
  let q: FirebaseFirestore.Query = db().collection(COL.reports);
  if (status) q = q.where('status', '==', status);
  const snap = await q.orderBy('createdAt', 'desc').limit(limit).get();
  return { reports: snap.docs.map((x) => toJson({ id: x.id, ...x.data() })) };
}

export async function handleAdminResolveReport(req: Req): Promise<{ ok: true }> {
  const caller = await requireAdmin(req, 'adminResolveReport');
  const d = asRecord(req.data);
  const reportId = id(d, 'reportId');
  const status = oneOf(d, 'status', ['DISMISSED', 'ACTIONED'] as const);
  const ref = db().collection(COL.reports).doc(reportId);
  const s = await ref.get();
  if (!s.exists) fail('not-found', 'REPORT_NOT_FOUND');
  await ref.update({ status, resolvedBy: caller.uid, resolvedAt: FieldValue.serverTimestamp() });
  return { ok: true };
}

export async function handleAdminListRiskEvents(req: Req): Promise<{ events: unknown[] }> {
  await requireAdmin(req, 'adminListRiskEvents');
  const d = asRecord(req.data ?? {});
  const status = optOneOf(d, 'status', ['OPEN', 'REVIEWED', 'CLEARED'] as const);
  const limit = limitParam(d, 50, 200);
  let q: FirebaseFirestore.Query = db().collection(COL.riskEvents);
  if (status) q = q.where('status', '==', status);
  const snap = await q.orderBy('createdAt', 'desc').limit(limit).get();
  return { events: snap.docs.map((x) => toJson({ id: x.id, ...x.data() })) };
}

export async function handleAdminResolveRiskEvent(req: Req): Promise<{ ok: true }> {
  const caller = await requireAdmin(req, 'adminResolveRiskEvent');
  const d = asRecord(req.data);
  const eventId = id(d, 'id');
  const status = oneOf(d, 'status', ['REVIEWED', 'CLEARED'] as const);
  const ref = db().collection(COL.riskEvents).doc(eventId);
  const s = await ref.get();
  if (!s.exists) fail('not-found', 'RISK_EVENT_NOT_FOUND');
  await ref.update({ status, resolvedBy: caller.uid, resolvedAt: FieldValue.serverTimestamp() });
  return { ok: true };
}

const SETTING_BOUNDS: Partial<Record<keyof GlobalSettings, [number, number]>> = {
  dailyGoalDefault: [1000, 50_000],
  maxStepsPerBucket: [1, 35],
  maxStepsPer30Min: [1, 6300],
  maxRewardStepsPerDay: [1000, 100_000],
  maxBucketAgeHours: [1, 168],
  futureToleranceSec: [0, 600],
  settlementGraceHours: [0, 72],
  pointsDailyGoal: [0, 100_000],
  pointsStreak7: [0, 100_000],
  pointsChallengeComplete: [0, 100_000],
  pointsChallengeWin: [0, 100_000],
  betMinStake: [1, 100_000],
  betMaxStake: [1, 100_000],
  betExpiryHours: [1, 168],
  rewardDeviceTakeoverDays: [1, 365],
  buddyRerequestCooldownHours: [0, 168],
};

export async function handleAdminSetSettings(req: Req): Promise<{ ok: true }> {
  await requireAdmin(req, 'adminSetSettings');
  const d = asRecord(req.data);
  const s = asRecord(d.settings, 'INVALID_SETTINGS');
  const patch: Record<string, number> = {};
  for (const [k, v] of Object.entries(s)) {
    const bounds = SETTING_BOUNDS[k as keyof GlobalSettings];
    if (!bounds || !(k in DEFAULT_SETTINGS)) fail('invalid-argument', 'SETTING_NOT_EDITABLE', `unknown or read-only setting: ${k}`);
    if (typeof v !== 'number' || !Number.isInteger(v) || v < bounds[0] || v > bounds[1]) fail('invalid-argument', 'INVALID_SETTING_VALUE', `invalid value for ${k}`);
    patch[k] = v;
  }
  const ref = db().collection(COL.adminSettings).doc('global');
  await db().runTransaction(async (tx) => {
    const cur = { ...DEFAULT_SETTINGS, ...((await tx.get(ref)).data() ?? {}), ...patch } as GlobalSettings;
    if (cur.betMaxStake < cur.betMinStake) fail('invalid-argument', 'INVALID_SETTING_VALUE', 'betMaxStake must be >= betMinStake');
    tx.set(ref, { ...patch, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  });
  return { ok: true };
}

export async function handleAdminUpsertBadge(req: Req): Promise<{ ok: true }> {
  await requireAdmin(req, 'adminUpsertBadge');
  const d = asRecord(req.data);
  const badgeId = str(d, 'badgeId', { min: 2, max: 40, pattern: /^[A-Z0-9_]+$/ });
  const def = {
    title: str(d, 'title', { min: 2, max: 60 }),
    description: str(d, 'description', { min: 2, max: 200 }),
    icon: str(d, 'icon', { min: 1, max: 40 }),
    rule: str(d, 'rule', { min: 2, max: 200 }),
    points: int(d, 'points', 0, 100_000),
  };
  await db().collection(COL.adminSettings).doc('badges').set({ [badgeId]: def, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  return { ok: true };
}

export async function handleAdminStats(req: Req): Promise<Record<string, number>> {
  await requireAdmin(req, 'adminStats');
  const f = db();
  const count = async (q: FirebaseFirestore.Query) => (await q.count().get()).data().count;
  const [users, active, deletion, challenges, reports, risks, bets] = await Promise.all([
    count(f.collection(COL.users)),
    count(f.collection(COL.users).where('status', '==', 'ACTIVE')),
    count(f.collection(COL.users).where('status', '==', 'DELETION_REQUESTED')),
    count(f.collection(COL.challenges).where('status', '==', 'ACTIVE')),
    count(f.collection(COL.reports).where('status', '==', 'OPEN')),
    count(f.collection(COL.riskEvents).where('status', '==', 'OPEN')),
    count(f.collection(COL.stepBets).where('status', '==', 'ACTIVE')),
  ]);
  return { users, activeUsers: active, deletionRequests: deletion, activeChallenges: challenges, openReports: reports, openRiskEvents: risks, activeBets: bets };
}

export async function handleAdminSeedDefaults(req: Req): Promise<{ ok: true; report: SeedReport }> {
  await requireAdmin(req, 'adminSeedDefaults');
  return { ok: true, report: await seedDefaults(db()) };
}
