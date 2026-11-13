/** Central constants. Mirrors DATABASE_SCHEMA.md. No secrets live here. */

export const REGION = 'asia-south1';
export const TIMEZONE = 'Asia/Kolkata';
/** IST is a fixed UTC+05:30 offset (no DST), so all period math is plain integer arithmetic. */
export const IST_OFFSET_MS = 330 * 60_000;
export const DAY_MS = 86_400_000;
export const ALLOWED_EMAIL_DOMAIN = 'thapar.edu';

export const COL = {
  hostels: 'hostels',
  users: 'users',
  publicProfiles: 'publicProfiles',
  devices: 'devices',
  stepBuckets: 'stepBuckets',
  dailyStepSummaries: 'dailyStepSummaries',
  leaderboards: 'leaderboards',
  entries: 'entries',
  buddyRequests: 'buddyRequests',
  buddyConnections: 'buddyConnections',
  challenges: 'challenges',
  challengeParticipants: 'challengeParticipants',
  challengeResults: 'challengeResults',
  stepBets: 'stepBets',
  ledger: 'virtualPointsLedger',
  achievements: 'achievements',
  notifications: 'notifications',
  reports: 'reports',
  riskEvents: 'riskEvents',
  adminSettings: 'adminSettings',
  adminAudit: 'adminAudit',
} as const;

export const FITNESS_LEVELS = ['BEGINNER', 'INTERMEDIATE', 'ADVANCED'] as const;
export const PREFERRED_TIMES = ['MORNING', 'AFTERNOON', 'EVENING', 'NIGHT', 'ANYTIME'] as const;
export const BUDDY_TYPES = ['INDIVIDUAL', 'GROUP', 'BOTH'] as const;
export const WEEKDAYS = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'] as const;
export const USER_STATUSES = ['ACTIVE', 'SUSPENDED', 'DELETION_REQUESTED'] as const;
export const BADGE_IDS = [
  'FIRST_1K',
  'TEN_K_WALKER',
  'STREAK_7',
  'CHALLENGE_CHAMPION',
  'HOSTEL_CHAMPION',
  'CAMPUS_FITNESS_STAR',
] as const;
export const REPORT_REASONS = ['SPAM', 'HARASSMENT', 'FAKE_PROFILE', 'INAPPROPRIATE', 'OTHER'] as const;

export type Period = 'DAILY' | 'WEEKLY' | 'MONTHLY' | 'ALL_TIME';
export const PERIODS: readonly Period[] = ['DAILY', 'WEEKLY', 'MONTHLY', 'ALL_TIME'];

export interface GlobalSettings {
  timezone: string;
  dailyGoalDefault: number;
  maxStepsPerBucket: number;
  maxStepsPer30Min: number;
  maxRewardStepsPerDay: number;
  maxBucketAgeHours: number;
  futureToleranceSec: number;
  settlementGraceHours: number;
  pointsDailyGoal: number;
  pointsStreak7: number;
  pointsChallengeComplete: number;
  pointsChallengeWin: number;
  betMinStake: number;
  betMaxStake: number;
  betExpiryHours: number;
  /** Extension: a reward device unseen for this many days may be replaced by a newly registered device. */
  rewardDeviceTakeoverDays: number;
  /** Extension: re-request cooldown after a rejected/cancelled buddy request. */
  buddyRerequestCooldownHours: number;
}

export const DEFAULT_SETTINGS: GlobalSettings = {
  timezone: TIMEZONE,
  dailyGoalDefault: 10_000,
  maxStepsPerBucket: 35,
  maxStepsPer30Min: 6300,
  maxRewardStepsPerDay: 20_000,
  maxBucketAgeHours: 72,
  futureToleranceSec: 120,
  settlementGraceHours: 6,
  pointsDailyGoal: 10,
  pointsStreak7: 50,
  pointsChallengeComplete: 50,
  pointsChallengeWin: 100,
  betMinStake: 10,
  betMaxStake: 1000,
  betExpiryHours: 48,
  rewardDeviceTakeoverDays: 14,
  buddyRerequestCooldownHours: 24,
};

export const BET_LIMITS = { minTarget: 1000, maxTarget: 1_000_000, minDays: 1, maxDays: 30 };
export const SYNC_MAX_BUCKETS = 200;
export const MAX_PENDING_BUDDY_REQUESTS = 30;
