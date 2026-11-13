import { COL } from '../config';
import { db, FieldValue, admin } from '../lib/firebase';

export type NotificationType =
  | 'BUDDY_REQUEST'
  | 'BUDDY_ACCEPTED'
  | 'CHALLENGE_NEW'
  | 'CHALLENGE_REMINDER'
  | 'CHALLENGE_DONE'
  | 'LEADERBOARD'
  | 'BET_INVITE'
  | 'BET_RESULT'
  | 'HOSTEL_RESULT'
  | 'SYSTEM';

export interface NotifyInput {
  uid: string;
  type: NotificationType;
  title: string;
  body: string;
  data?: Record<string, string>;
  /** Doc id is `{uid}_{dedupeKey}`: the same dedupeKey can never produce a second notification. */
  dedupeKey: string;
}

const PREF_FOR_TYPE: Record<NotificationType, string | null> = {
  BUDDY_REQUEST: 'buddy',
  BUDDY_ACCEPTED: 'buddy',
  CHALLENGE_NEW: 'challenges',
  CHALLENGE_REMINDER: 'reminders',
  CHALLENGE_DONE: 'challenges',
  LEADERBOARD: 'leaderboard',
  BET_INVITE: 'bets',
  BET_RESULT: 'bets',
  HOSTEL_RESULT: 'challenges',
  SYSTEM: null,
};

export function notificationId(uid: string, dedupeKey: string): string {
  return `${uid}_${dedupeKey}`;
}

/** Create the in-app notification once (returns false if the dedupeKey already exists). Push is best-effort. */
export async function notify(n: NotifyInput): Promise<boolean> {
  const ref = db().collection(COL.notifications).doc(notificationId(n.uid, n.dedupeKey));
  try {
    await ref.create({
      uid: n.uid,
      type: n.type,
      title: n.title.slice(0, 120),
      body: n.body.slice(0, 400),
      data: n.data ?? {},
      read: false,
      dedupeKey: n.dedupeKey,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (e) {
    if ((e as { code?: number }).code === 6) return false; // ALREADY_EXISTS => duplicate, no repeat
    throw e;
  }
  await pushBestEffort(n).catch(() => undefined);
  return true;
}

export async function notifyMany(list: NotifyInput[]): Promise<number> {
  let created = 0;
  for (const n of list) {
    if (await notify(n).catch(() => false)) created++;
  }
  return created;
}

async function pushBestEffort(n: NotifyInput): Promise<void> {
  // No outbound network from the emulator / tests.
  if (process.env.FIRESTORE_EMULATOR_HOST || process.env.STEPUP_DISABLE_PUSH === '1') return;
  const userSnap = await db().collection(COL.users).doc(n.uid).get();
  const prefs = (userSnap.data()?.notificationPrefs ?? {}) as Record<string, boolean>;
  const key = PREF_FOR_TYPE[n.type];
  if (key && prefs[key] === false) return;
  const devices = await db().collection(COL.users).doc(n.uid).collection(COL.devices).get();
  const tokens = devices.docs.map((d) => d.data().fcmToken).filter((t): t is string => typeof t === 'string' && t.length > 0);
  if (tokens.length === 0) return;
  await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title: n.title, body: n.body },
    data: { type: n.type, ...(n.data ?? {}) },
  });
}
