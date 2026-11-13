import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { beforeUserCreated as onBeforeUserCreated } from 'firebase-functions/v2/identity';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as logger from 'firebase-functions/logger';
import { REGION, TIMEZONE } from './config';
import { callable } from './lib/callable';
import { assertThaparSignup } from './lib/signup';

import {
  handleAdminCancelChallenge,
  handleAdminCreateChallenge,
  handleAdminListReports,
  handleAdminListRiskEvents,
  handleAdminListStudents,
  handleAdminResolveReport,
  handleAdminResolveRiskEvent,
  handleAdminSeedDefaults,
  handleAdminSetHostelActive,
  handleAdminSetSettings,
  handleAdminSetUserRole,
  handleAdminStats,
  handleAdminSuspendUser,
  handleAdminUpsertBadge,
  handleAdminUpsertHostel,
} from './admin/admin';
import { handleCancelStepBet, handleCreateStepBet, handleRespondStepBet } from './bets/bets';
import { runSettleStepBets } from './bets/settle';
import {
  handleCancelBuddyRequest,
  handleRemoveBuddy,
  handleReportProfile,
  handleRespondBuddyRequest,
  handleSearchBuddies,
  handleSendBuddyRequest,
} from './buddies/buddies';
import {
  handleCreateBuddyChallenge,
  handleGetChallengeLeaderboard,
  handleJoinChallenge,
  handleLeaveChallenge,
  handleRespondChallengeInvite,
} from './challenges/callables';
import { runFinalizeChallenges } from './challenges/finalize';
import { runChallengeReminders } from './challenges/reminders';
import { handleGetLeaderboard } from './leaderboards/getLeaderboard';
import { handleMarkNotificationsRead } from './notifications/markRead';
import { handleCreateProfile, handleRegisterDevice, handleRequestAccountDeletion, handleUpdateProfile } from './profile/profile';
import { handleSyncStepBuckets } from './steps/syncStepBuckets';
import { processDailySummary } from './triggers/dailySummary';
import { runRefreshWeeklySteps } from './triggers/weekly';

// ---- Auth blocking function (Identity Platform): reject non-@thapar.edu sign-ups. ------------------------------
export const beforeUserCreated = onBeforeUserCreated({ region: REGION }, (event) => {
  assertThaparSignup(event.data?.email);
});

// ---- Callables --------------------------------------------------------------------------------------------------
export const createProfile = callable(handleCreateProfile);
export const updateProfile = callable(handleUpdateProfile);
export const requestAccountDeletion = callable(handleRequestAccountDeletion);
export const registerDevice = callable(handleRegisterDevice);

export const syncStepBuckets = callable(handleSyncStepBuckets);

export const searchBuddies = callable(handleSearchBuddies);
export const sendBuddyRequest = callable(handleSendBuddyRequest);
export const respondBuddyRequest = callable(handleRespondBuddyRequest);
export const cancelBuddyRequest = callable(handleCancelBuddyRequest);
export const removeBuddy = callable(handleRemoveBuddy);
export const reportProfile = callable(handleReportProfile);

export const createBuddyChallenge = callable(handleCreateBuddyChallenge);
export const respondChallengeInvite = callable(handleRespondChallengeInvite);
export const joinChallenge = callable(handleJoinChallenge);
export const leaveChallenge = callable(handleLeaveChallenge);
export const getChallengeLeaderboard = callable(handleGetChallengeLeaderboard);

export const createStepBet = callable(handleCreateStepBet);
export const respondStepBet = callable(handleRespondStepBet);
export const cancelStepBet = callable(handleCancelStepBet);

export const getLeaderboard = callable(handleGetLeaderboard);
export const markNotificationsRead = callable(handleMarkNotificationsRead);

export const adminUpsertHostel = callable(handleAdminUpsertHostel);
export const adminSetHostelActive = callable(handleAdminSetHostelActive);
export const adminCreateChallenge = callable(handleAdminCreateChallenge);
export const adminCancelChallenge = callable(handleAdminCancelChallenge);
export const adminListStudents = callable(handleAdminListStudents);
export const adminSetUserRole = callable(handleAdminSetUserRole);
export const adminSuspendUser = callable(handleAdminSuspendUser);
export const adminListReports = callable(handleAdminListReports);
export const adminResolveReport = callable(handleAdminResolveReport);
export const adminListRiskEvents = callable(handleAdminListRiskEvents);
export const adminResolveRiskEvent = callable(handleAdminResolveRiskEvent);
export const adminSetSettings = callable(handleAdminSetSettings);
export const adminUpsertBadge = callable(handleAdminUpsertBadge);
export const adminStats = callable(handleAdminStats);
export const adminSeedDefaults = callable(handleAdminSeedDefaults);

// ---- Firestore trigger ------------------------------------------------------------------------------------------
export const onDailySummaryWritten = onDocumentWritten({ document: 'dailyStepSummaries/{docId}', region: REGION }, async (event) => {
  const after = event.data?.after;
  if (!after || !after.exists) return;
  const d = after.data() as { uid?: string; dayKey?: string };
  if (!d.uid || !d.dayKey) return;
  try {
    await processDailySummary(d.uid, d.dayKey);
  } catch (e) {
    logger.error('onDailySummaryWritten failed', { docId: event.params.docId, message: (e as Error).message });
    throw e; // let Firestore retry policy / monitoring see it; processing is idempotent
  }
});

// ---- Scheduled --------------------------------------------------------------------------------------------------
export const finalizeChallenges = onSchedule({ schedule: 'every 15 minutes', timeZone: TIMEZONE, region: REGION }, async () => {
  logger.info('finalizeChallenges', await runFinalizeChallenges());
});
export const settleStepBets = onSchedule({ schedule: 'every 15 minutes', timeZone: TIMEZONE, region: REGION }, async () => {
  logger.info('settleStepBets', await runSettleStepBets());
});
export const challengeReminders = onSchedule({ schedule: '0 18 * * *', timeZone: TIMEZONE, region: REGION }, async () => {
  logger.info('challengeReminders', await runChallengeReminders());
});
export const refreshWeeklySteps = onSchedule({ schedule: 'every 60 minutes', timeZone: TIMEZONE, region: REGION }, async () => {
  logger.info('refreshWeeklySteps', await runRefreshWeeklySteps());
});
