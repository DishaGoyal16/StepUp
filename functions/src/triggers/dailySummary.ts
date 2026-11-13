import { COL } from '../config';
import { updateBetProgressForUser } from '../bets/settle';
import { updateChallengeProgressForUser } from '../challenges/service';
import { periodTotal, refreshUserBoards } from '../leaderboards/aggregate';
import { nowMs } from '../lib/clock';
import { db, FieldValue } from '../lib/firebase';
import { grantRewards } from '../lib/rewards';
import { getSettings } from '../lib/settings';
import { dayKeyOf, weekKeyOfDay } from '../lib/time';
import { loadUserDays } from '../steps/summaries';
import { computeStreak } from './streak';

/**
 * Everything derived from a changed day summary. IDEMPOTENT: it recomputes from stored summaries and every payment
 * uses a deterministic ledger id / achievement id, so trigger re-delivery or a manual re-run never double-pays.
 */
export async function processDailySummary(uid: string, dayKey: string): Promise<void> {
  const firestore = db();
  const userRef = firestore.collection(COL.users).doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) return;
  const user = userSnap.data() as FirebaseFirestore.DocumentData;
  const settings = await getSettings();
  const days = await loadUserDays(uid);
  const today = dayKeyOf(nowMs());

  // 1) leaderboards (daily / weekly / monthly / all-time) + hostel aggregates
  await refreshUserBoards(uid, { touchedDayKey: dayKey, days });

  // 2) challenge progress and bet totals
  await updateChallengeProgressForUser(uid, days);
  await updateBetProgressForUser(uid, days);

  // 3) lifetime total, streak, public weekly steps
  let lifetime = 0;
  for (const v of days.values()) lifetime += v;
  const goal = Number(user.dailyGoal ?? settings.dailyGoalDefault);
  const goalDays = [...days.entries()].filter(([, v]) => v >= goal).map(([k]) => k);
  const streak = computeStreak(goalDays, today);
  const best = Math.max(Number(user.bestStreak ?? 0), streak.longest);
  await userRef.update({
    lifetimeVerifiedSteps: lifetime,
    currentStreak: streak.current,
    bestStreak: best,
    lastGoalDayKey: streak.lastGoalDayKey,
    updatedAt: FieldValue.serverTimestamp(),
  });
  const privacy = (user.privacy ?? {}) as Record<string, boolean>;
  await firestore
    .collection(COL.publicProfiles)
    .doc(uid)
    .set({ weeklyVerifiedSteps: privacy.showWeeklySteps === false ? null : periodTotal(days, 'WEEKLY', weekKeyOfDay(today)) }, { merge: true });

  if (user.status !== 'ACTIVE') return;

  // 4) daily goal reward (once per user per day)
  if ((days.get(dayKey) ?? 0) >= goal && settings.pointsDailyGoal > 0) {
    await grantRewards({ uid, reward: { refType: 'DAILY_GOAL', refId: dayKey, points: settings.pointsDailyGoal, note: `Daily goal reached (${dayKey})` } });
  }

  // 5) streak reward (once per streak run) and badges
  const badges: Array<{ badgeId: string; refId: string }> = [];
  if (lifetime >= 1000) badges.push({ badgeId: 'FIRST_1K', refId: dayKey });
  if ([...days.values()].some((v) => v >= 10_000)) badges.push({ badgeId: 'TEN_K_WALKER', refId: dayKey });
  if (streak.current >= 7 && streak.currentStart) {
    badges.push({ badgeId: 'STREAK_7', refId: streak.currentStart });
    await grantRewards({
      uid,
      reward: { refType: 'STREAK', refId: streak.currentStart, points: settings.pointsStreak7, note: `7-day streak starting ${streak.currentStart}` },
      badges,
    });
  } else if (badges.length) {
    await grantRewards({ uid, badges });
  }
}
