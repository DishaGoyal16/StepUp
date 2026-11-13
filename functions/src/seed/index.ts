import { Firestore, FieldValue } from 'firebase-admin/firestore';
import { COL, DEFAULT_SETTINGS } from '../config';
import { HOSTEL_SEED } from './hostels';
import { INDIVIDUAL_TEMPLATES, ADMIN_SUGGESTED_TEMPLATES, templateChallengeId } from './challenges';
import { BADGE_CATALOGUE } from './badges';

export interface SeedReport {
  hostelsCreated: number;
  challengeTemplatesCreated: number;
  settingsCreatedOrFilled: boolean;
  badgesCreatedOrFilled: boolean;
}

/**
 * Shared by `adminSeedDefaults` and `scripts/seed.js`. Idempotent and non-destructive: existing documents (which
 * admins may have edited) are never overwritten; missing documents/fields are created.
 */
export async function seedDefaults(firestore: Firestore): Promise<SeedReport> {
  const report: SeedReport = {
    hostelsCreated: 0,
    challengeTemplatesCreated: 0,
    settingsCreatedOrFilled: false,
    badgesCreatedOrFilled: false,
  };

  for (const [i, h] of HOSTEL_SEED.entries()) {
    const ref = firestore.collection(COL.hostels).doc(h.hostelId);
    if (await createIfMissing(ref, { ...h, active: true, sortOrder: i + 1 })) report.hostelsCreated++;
  }

  for (const t of INDIVIDUAL_TEMPLATES) {
    const ref = firestore.collection(COL.challenges).doc(templateChallengeId(t.key));
    const created = await createIfMissing(ref, {
      type: 'INDIVIDUAL',
      title: t.title,
      description: t.description,
      metric: t.metric,
      target: t.target,
      dailyTarget: t.dailyTarget,
      windowMode: t.windowMode,
      startAt: null,
      endAt: null,
      durationDays: t.durationDays,
      status: 'ACTIVE',
      createdBy: 'system',
      hostelIds: [],
      hostelAggregation: 'AVERAGE_PER_PARTICIPANT',
      maxParticipants: null,
      participantCount: 0,
      rewardPoints: t.rewardPoints,
      isTemplate: true,
      winnerUid: null,
      winnerHostelId: null,
      finalizedAt: null,
    });
    if (created) report.challengeTemplatesCreated++;
  }

  report.settingsCreatedOrFilled = await fillMissing(firestore.collection(COL.adminSettings).doc('global'), { ...DEFAULT_SETTINGS });
  report.badgesCreatedOrFilled = await fillMissing(
    firestore.collection(COL.adminSettings).doc('badges'),
    JSON.parse(JSON.stringify(BADGE_CATALOGUE)) as Record<string, unknown>,
  );
  await fillMissing(firestore.collection(COL.adminSettings).doc('challengeTemplates'), {
    suggested: JSON.parse(JSON.stringify(ADMIN_SUGGESTED_TEMPLATES)) as unknown,
  });
  return report;
}

async function createIfMissing(ref: FirebaseFirestore.DocumentReference, data: Record<string, unknown>): Promise<boolean> {
  try {
    await ref.create({ ...data, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
    return true;
  } catch (e) {
    if ((e as { code?: number }).code === 6) return false;
    throw e;
  }
}

/** Create the doc or add only the keys that are missing (never overwrites admin-edited values). */
async function fillMissing(ref: FirebaseFirestore.DocumentReference, defaults: Record<string, unknown>): Promise<boolean> {
  return ref.firestore.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const existing = (snap.exists ? snap.data() : {}) as Record<string, unknown>;
    const missing: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(defaults)) if (existing[k] === undefined) missing[k] = v;
    if (snap.exists && Object.keys(missing).length === 0) return false;
    tx.set(ref, { ...missing, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    return true;
  });
}
