import {
  BUDDY_TYPES,
  COL,
  FITNESS_LEVELS,
  PREFERRED_TIMES,
  WEEKDAYS,
} from '../config';
import { Req, requireEligibleUser, requireThaparToken } from '../lib/auth';
import { nowMs } from '../lib/clock';
import { fail } from '../lib/errors';
import { db, FieldValue } from '../lib/firebase';
import { toJson } from '../lib/json';
import { getSettings } from '../lib/settings';
import { asRecord, bool, int, oneOf, optInt, optOneOf, optStr, optStrArray, Rec, str } from '../lib/validate';
import { refreshUserBoards } from '../leaderboards/aggregate';
import { DEVICE_ID_PATTERN } from '../steps/syncStepBuckets';

const PRIVACY_KEYS = ['discoverable', 'showHostel', 'showWeeklySteps', 'showOnLeaderboards'] as const;
const NOTIF_KEYS = ['buddy', 'challenges', 'bets', 'leaderboard', 'reminders'] as const;
const URL_PATTERN = /^https:\/\/[^\s]+$/;

export const EDITABLE_FIELDS = [
  'displayName',
  'hostelId',
  'fitnessLevel',
  'sportsInterests',
  'preferredActivity',
  'preferredTime',
  'goals',
  'availability',
  'buddyType',
  'bio',
  'photoUrl',
  'dailyGoal',
  'privacy',
  'notificationPrefs',
] as const;

async function loadActiveHostel(hostelId: string): Promise<FirebaseFirestore.DocumentData> {
  const snap = await db().collection(COL.hostels).doc(hostelId).get();
  if (!snap.exists || snap.data()?.active !== true) fail('invalid-argument', 'INVALID_HOSTEL', 'unknown or inactive hostel');
  return snap.data() as FirebaseFirestore.DocumentData;
}

function parseBoolMap(d: Rec, key: string, keys: readonly string[], partial: boolean): Record<string, boolean> | undefined {
  const v = d[key];
  if (v === undefined || v === null) return undefined;
  const m = asRecord(v, `INVALID_${key.toUpperCase()}`);
  const out: Record<string, boolean> = {};
  for (const k of Object.keys(m)) {
    if (!keys.includes(k)) fail('invalid-argument', `INVALID_${key.toUpperCase()}`);
    out[k] = bool(m, k);
  }
  if (!partial) for (const k of keys) if (out[k] === undefined) out[k] = true;
  return out;
}

export function buildPublicProfile(user: FirebaseFirestore.DocumentData, weeklyVerifiedSteps: number | null): Record<string, unknown> {
  const privacy = (user.privacy ?? {}) as Record<string, boolean>;
  const active = user.status === 'ACTIVE';
  return {
    displayName: user.displayName,
    photoUrl: user.photoUrl ?? null,
    hostelId: privacy.showHostel === false ? null : (user.hostelId ?? null),
    fitnessLevel: user.fitnessLevel,
    sportsInterests: user.sportsInterests ?? [],
    preferredActivity: user.preferredActivity ?? '',
    preferredTime: user.preferredTime,
    goals: user.goals ?? [],
    availability: user.availability ?? [],
    buddyType: user.buddyType,
    bio: user.bio ?? '',
    weeklyVerifiedSteps: privacy.showWeeklySteps === false ? null : weeklyVerifiedSteps,
    discoverable: active && privacy.discoverable !== false,
    showOnLeaderboards: active && privacy.showOnLeaderboards !== false,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

// ---------------------------------------------------------------------------------------------------------------

export async function handleCreateProfile(req: Req): Promise<{ ok: true; created: boolean; profile: unknown }> {
  const caller = requireThaparToken(req);
  const d = asRecord(req.data);
  const settings = await getSettings();

  const displayName = str(d, 'displayName', { min: 2, max: 50 });
  const hostelId = str(d, 'hostelId', { min: 1, max: 64 });
  const fitnessLevel = oneOf(d, 'fitnessLevel', FITNESS_LEVELS);
  const sportsInterests = optStrArray(d, 'sportsInterests', { maxItems: 20, maxLen: 40 }) ?? [];
  const preferredActivity = optStr(d, 'preferredActivity', { max: 40 }) ?? '';
  const preferredTime = optOneOf(d, 'preferredTime', PREFERRED_TIMES) ?? 'ANYTIME';
  const goals = optStrArray(d, 'goals', { maxItems: 10, maxLen: 40 }) ?? [];
  const availability = optStrArray(d, 'availability', { maxItems: 7, maxLen: 3, allowed: WEEKDAYS }) ?? [];
  const buddyType = optOneOf(d, 'buddyType', BUDDY_TYPES) ?? 'BOTH';
  const bio = optStr(d, 'bio', { max: 160 }) ?? '';
  const photoUrl = optStr(d, 'photoUrl', { max: 512, pattern: URL_PATTERN }) || null;
  const dailyGoal = optInt(d, 'dailyGoal', 1000, 50_000) ?? settings.dailyGoalDefault;
  const privacy = { discoverable: true, showHostel: true, showWeeklySteps: true, showOnLeaderboards: true, ...parseBoolMap(d, 'privacy', PRIVACY_KEYS, true) };
  const notificationPrefs = { buddy: true, challenges: true, bets: true, leaderboard: true, reminders: true, ...parseBoolMap(d, 'notificationPrefs', NOTIF_KEYS, true) };
  const hostel = await loadActiveHostel(hostelId);

  const firestore = db();
  const userRef = firestore.collection(COL.users).doc(caller.uid);
  const pubRef = firestore.collection(COL.publicProfiles).doc(caller.uid);
  const created = await firestore.runTransaction(async (tx) => {
    const existing = await tx.get(userRef);
    if (existing.exists) return false; // idempotent: never overwrite an existing profile
    const user = {
      displayName,
      email: caller.email,
      hostelId,
      block: (hostel.block as string | null) ?? null,
      fitnessLevel,
      sportsInterests,
      preferredActivity,
      preferredTime,
      goals,
      availability,
      buddyType,
      bio,
      photoUrl,
      dailyGoal,
      privacy,
      notificationPrefs,
      pointsBalance: 0,
      pointsReserved: 0,
      lifetimeVerifiedSteps: 0,
      currentStreak: 0,
      bestStreak: 0,
      lastGoalDayKey: null,
      status: 'ACTIVE',
      role: caller.isAdminClaim ? 'admin' : 'student',
      rewardDeviceId: null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };
    tx.create(userRef, user);
    tx.create(pubRef, buildPublicProfile(user, 0));
    return true;
  });
  const snap = await userRef.get();
  return { ok: true, created, profile: toJson(snap.data()) };
}

export async function handleUpdateProfile(req: Req): Promise<{ ok: true }> {
  const caller = await requireEligibleUser(req);
  const d = asRecord(req.data);
  for (const k of Object.keys(d)) {
    if (!(EDITABLE_FIELDS as readonly string[]).includes(k)) fail('invalid-argument', 'FIELD_NOT_EDITABLE', `field not editable: ${k}`);
  }
  const patch: Record<string, unknown> = {};
  if (d.displayName !== undefined) patch.displayName = str(d, 'displayName', { min: 2, max: 50 });
  if (d.fitnessLevel !== undefined) patch.fitnessLevel = oneOf(d, 'fitnessLevel', FITNESS_LEVELS);
  if (d.sportsInterests !== undefined) patch.sportsInterests = optStrArray(d, 'sportsInterests', { maxItems: 20, maxLen: 40 });
  if (d.preferredActivity !== undefined) patch.preferredActivity = str(d, 'preferredActivity', { min: 0, max: 40 });
  if (d.preferredTime !== undefined) patch.preferredTime = oneOf(d, 'preferredTime', PREFERRED_TIMES);
  if (d.goals !== undefined) patch.goals = optStrArray(d, 'goals', { maxItems: 10, maxLen: 40 });
  if (d.availability !== undefined) patch.availability = optStrArray(d, 'availability', { maxItems: 7, maxLen: 3, allowed: WEEKDAYS });
  if (d.buddyType !== undefined) patch.buddyType = oneOf(d, 'buddyType', BUDDY_TYPES);
  if (d.bio !== undefined) patch.bio = str(d, 'bio', { min: 0, max: 160 });
  if (d.photoUrl !== undefined) patch.photoUrl = d.photoUrl === null ? null : str(d, 'photoUrl', { max: 512, pattern: URL_PATTERN });
  if (d.dailyGoal !== undefined) patch.dailyGoal = int(d, 'dailyGoal', 1000, 50_000);
  const privacyPatch = parseBoolMap(d, 'privacy', PRIVACY_KEYS, true);
  const notifPatch = parseBoolMap(d, 'notificationPrefs', NOTIF_KEYS, true);
  const oldHostelId = caller.user.hostelId as string | null;
  let newHostelId: string | undefined;
  if (d.hostelId !== undefined) {
    newHostelId = str(d, 'hostelId', { min: 1, max: 64 });
    const hostel = await loadActiveHostel(newHostelId);
    patch.hostelId = newHostelId;
    patch.block = (hostel.block as string | null) ?? null;
  }

  const firestore = db();
  const userRef = firestore.collection(COL.users).doc(caller.uid);
  const pubRef = firestore.collection(COL.publicProfiles).doc(caller.uid);
  await firestore.runTransaction(async (tx) => {
    const [uSnap, pSnap] = await tx.getAll(userRef, pubRef);
    const cur = uSnap.data() as FirebaseFirestore.DocumentData;
    if (cur.status !== 'ACTIVE') fail('permission-denied', 'ACCOUNT_NOT_ACTIVE');
    const merged = { ...cur, ...patch } as FirebaseFirestore.DocumentData;
    if (privacyPatch) merged.privacy = { ...(cur.privacy ?? {}), ...privacyPatch };
    if (notifPatch) merged.notificationPrefs = { ...(cur.notificationPrefs ?? {}), ...notifPatch };
    const update: Record<string, unknown> = { ...patch, updatedAt: FieldValue.serverTimestamp() };
    if (privacyPatch) update.privacy = merged.privacy;
    if (notifPatch) update.notificationPrefs = merged.notificationPrefs;
    tx.update(userRef, update);
    const weekly = (pSnap.data()?.weeklyVerifiedSteps as number | null | undefined) ?? 0;
    tx.set(pubRef, buildPublicProfile(merged, weekly));
  });

  if (newHostelId !== undefined && newHostelId !== oldHostelId) {
    await refreshUserBoards(caller.uid, { previousHostelId: oldHostelId });
  } else if (patch.displayName !== undefined || patch.photoUrl !== undefined || privacyPatch !== undefined) {
    await refreshUserBoards(caller.uid, {});
  }
  return { ok: true };
}

export async function handleRequestAccountDeletion(req: Req): Promise<{ ok: true }> {
  const caller = await requireEligibleUser(req, { allowDeletionRequested: true });
  if (caller.user.status === 'DELETION_REQUESTED') return { ok: true }; // idempotent
  const firestore = db();
  const userRef = firestore.collection(COL.users).doc(caller.uid);
  const pubRef = firestore.collection(COL.publicProfiles).doc(caller.uid);
  await firestore.runTransaction(async (tx) => {
    const [uSnap, pSnap] = await tx.getAll(userRef, pubRef);
    const cur = uSnap.data() as FirebaseFirestore.DocumentData;
    tx.update(userRef, { status: 'DELETION_REQUESTED', updatedAt: FieldValue.serverTimestamp() });
    const weekly = (pSnap.data()?.weeklyVerifiedSteps as number | null | undefined) ?? 0;
    tx.set(pubRef, buildPublicProfile({ ...cur, status: 'DELETION_REQUESTED' }, weekly));
    // Deterministic id => repeated requests never create a second queue item.
    tx.set(
      firestore.collection(COL.reports).doc(`deletion_${caller.uid}`),
      {
        reporterUid: caller.uid,
        targetUid: caller.uid,
        reason: 'ACCOUNT_DELETION',
        details: 'User requested account deletion',
        status: 'OPEN',
        resolvedBy: null,
        createdAt: FieldValue.serverTimestamp(),
        resolvedAt: null,
      },
      { merge: true },
    );
  });
  await refreshUserBoards(caller.uid, {});
  return { ok: true };
}

export async function handleRegisterDevice(req: Req): Promise<{ isRewardDevice: boolean }> {
  const caller = await requireEligibleUser(req);
  const d = asRecord(req.data);
  const deviceId = str(d, 'deviceId', { min: 8, max: 64, pattern: DEVICE_ID_PATTERN });
  const model = str(d, 'model', { min: 1, max: 80 });
  const appVersion = str(d, 'appVersion', { min: 1, max: 40 });
  const fcmToken = optStr(d, 'fcmToken', { min: 1, max: 4096 }) ?? null;
  const settings = await getSettings();
  const takeoverMs = settings.rewardDeviceTakeoverDays * 86_400_000;
  const now = nowMs();

  const firestore = db();
  const userRef = firestore.collection(COL.users).doc(caller.uid);
  const devRef = userRef.collection(COL.devices).doc(deviceId);
  return firestore.runTransaction(async (tx) => {
    const [uSnap, dSnap] = await tx.getAll(userRef, devRef);
    const user = uSnap.data() as FirebaseFirestore.DocumentData;
    let rewardId = (user.rewardDeviceId as string | null) ?? null;
    let demoteRef: FirebaseFirestore.DocumentReference | null = null;
    if (rewardId && rewardId !== deviceId) {
      // Allow takeover only if the current reward device has been silent for a long time (lost / replaced phone).
      const curRef = userRef.collection(COL.devices).doc(rewardId);
      const curSnap = await tx.get(curRef);
      const lastSeen = curSnap.exists ? (curSnap.data()?.lastSeenAt?.toMillis?.() as number | undefined) ?? 0 : 0;
      if (!curSnap.exists || now - lastSeen > takeoverMs) {
        rewardId = null;
        if (curSnap.exists) demoteRef = curRef;
      }
    }
    if (demoteRef) tx.update(demoteRef, { isRewardDevice: false });
    if (!rewardId) {
      rewardId = deviceId;
      tx.update(userRef, { rewardDeviceId: deviceId, updatedAt: FieldValue.serverTimestamp() });
    }
    const isRewardDevice = rewardId === deviceId;
    if (dSnap.exists) {
      const upd: Record<string, unknown> = { model, appVersion, isRewardDevice, lastSeenAt: FieldValue.serverTimestamp() };
      if (fcmToken) upd.fcmToken = fcmToken;
      tx.update(devRef, upd);
    } else {
      tx.create(devRef, {
        deviceId,
        model,
        platform: 'android',
        appVersion,
        fcmToken,
        isRewardDevice,
        registeredAt: FieldValue.serverTimestamp(),
        lastSeenAt: FieldValue.serverTimestamp(),
        lastSeq: 0,
      });
    }
    return { isRewardDevice };
  });
}

