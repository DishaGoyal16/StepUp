import { COL } from '../config';
import { BADGE_CATALOGUE } from '../seed/badges';
import { db, FieldValue } from './firebase';
import { applyPoints, LedgerOp, LedgerRefType, loadPoints, rewardOp } from './points';
import { notify } from '../notifications/notify';

export interface GrantInput {
  uid: string;
  /** Optional points reward with a deterministic ledger id `{refType}_{refId}_{uid}_REWARD`. */
  reward?: { refType: LedgerRefType; refId: string; points: number; note: string };
  /** Badges to award once ever (`achievements/{uid}_{badgeId}`) plus their catalogue points (also once). */
  badges?: Array<{ badgeId: string; refId: string }>;
}

export interface GrantResult {
  rewardApplied: boolean;
  newBadges: string[];
}

async function badgePoints(badgeId: string): Promise<number> {
  const snap = await db().collection(COL.adminSettings).doc('badges').get();
  const def = (snap.data()?.[badgeId] ?? BADGE_CATALOGUE[badgeId]) as { points?: number } | undefined;
  return typeof def?.points === 'number' ? def.points : 0;
}

/**
 * Everything in ONE transaction: reward ledger op + badge achievements + badge points. Re-running is a no-op because
 * the ledger ids and achievement ids are deterministic.
 */
export async function grantRewards(g: GrantInput): Promise<GrantResult> {
  const firestore = db();
  const badgePts = new Map<string, number>();
  for (const b of g.badges ?? []) badgePts.set(b.badgeId, await badgePoints(b.badgeId));

  const result = await firestore.runTransaction(async (tx) => {
    const achRefs = (g.badges ?? []).map((b) => firestore.collection(COL.achievements).doc(`${g.uid}_${b.badgeId}`));
    const achSnaps = achRefs.length ? await tx.getAll(...achRefs) : [];
    const ops: LedgerOp[] = [];
    if (g.reward && g.reward.points > 0) ops.push(rewardOp(g.uid, g.reward.refType, g.reward.refId, g.reward.points, g.reward.note));
    const newBadges: Array<{ badgeId: string; refId: string; ref: FirebaseFirestore.DocumentReference }> = [];
    (g.badges ?? []).forEach((b, i) => {
      if (achSnaps[i].exists) return;
      newBadges.push({ ...b, ref: achRefs[i] });
      const pts = badgePts.get(b.badgeId) ?? 0;
      if (pts > 0) ops.push(rewardOp(g.uid, 'BADGE', b.badgeId, pts, `Badge: ${b.badgeId}`));
    });
    const state = ops.length ? await loadPoints(tx, ops) : null;
    for (const nb of newBadges) {
      tx.create(nb.ref, { uid: g.uid, badgeId: nb.badgeId, awardedAt: FieldValue.serverTimestamp(), refId: nb.refId });
    }
    const results = state ? applyPoints(tx, state, ops) : [];
    const rewardApplied = !!g.reward && g.reward.points > 0 && results.some((r) => r.applied && r.entryId.startsWith(`${g.reward!.refType}_${g.reward!.refId}_`));
    return { rewardApplied, newBadges: newBadges.map((n) => n.badgeId) };
  });

  for (const badgeId of result.newBadges) {
    const title = BADGE_CATALOGUE[badgeId]?.title ?? badgeId;
    await notify({
      uid: g.uid,
      type: 'SYSTEM',
      title: 'Badge earned',
      body: `You earned the "${title}" badge.`,
      data: { badgeId },
      dedupeKey: `badge_${badgeId}`,
    }).catch(() => undefined);
  }
  return result;
}
