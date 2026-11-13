/**
 * Challenge catalogue. The six INDIVIDUAL templates are written to Firestore (`challenges/tpl_*`, isTemplate=true,
 * ROLLING window starting at the day the user joins). The campus / hostel / buddy templates are *suggestions* stored in
 * `adminSettings/challengeTemplates` for the admin UI; they are not joinable until an admin creates a real challenge.
 */

export type ChallengeMetric = 'TOTAL_STEPS' | 'DAILY_TARGET_DAYS' | 'STREAK_DAYS';

export interface ChallengeTemplate {
  key: string;
  type: 'INDIVIDUAL' | 'BUDDY' | 'INTER_HOSTEL' | 'CAMPUS';
  title: string;
  description: string;
  metric: ChallengeMetric;
  /** TOTAL_STEPS: steps; DAILY_TARGET_DAYS / STREAK_DAYS: number of days. */
  target: number;
  dailyTarget: number | null;
  windowMode: 'FIXED' | 'ROLLING';
  durationDays: number;
  rewardPoints: number;
}

export const INDIVIDUAL_TEMPLATES: ChallengeTemplate[] = [
  {
    key: 'steps-5k-daily',
    type: 'INDIVIDUAL',
    title: '5,000 Steps Daily',
    description: 'Walk 5,000 verified steps in a single day.',
    metric: 'DAILY_TARGET_DAYS',
    target: 1,
    dailyTarget: 5000,
    windowMode: 'ROLLING',
    durationDays: 1,
    rewardPoints: 20,
  },
  {
    key: 'steps-10k-daily',
    type: 'INDIVIDUAL',
    title: '10,000 Steps Daily',
    description: 'Walk 10,000 verified steps in a single day.',
    metric: 'DAILY_TARGET_DAYS',
    target: 1,
    dailyTarget: 10000,
    windowMode: 'ROLLING',
    durationDays: 1,
    rewardPoints: 40,
  },
  {
    key: 'steps-50k-weekly',
    type: 'INDIVIDUAL',
    title: '50,000 Steps Weekly',
    description: 'Reach 50,000 verified steps within 7 days of joining.',
    metric: 'TOTAL_STEPS',
    target: 50000,
    dailyTarget: null,
    windowMode: 'ROLLING',
    durationDays: 7,
    rewardPoints: 60,
  },
  {
    key: 'steps-100k-weekly',
    type: 'INDIVIDUAL',
    title: '100,000 Steps Weekly',
    description: 'Reach 100,000 verified steps within 7 days of joining.',
    metric: 'TOTAL_STEPS',
    target: 100000,
    dailyTarget: null,
    windowMode: 'ROLLING',
    durationDays: 7,
    rewardPoints: 120,
  },
  {
    key: 'streak-7',
    type: 'INDIVIDUAL',
    title: '7-Day Walking Streak',
    description: 'Hit 5,000 verified steps on 7 days in a row.',
    metric: 'STREAK_DAYS',
    target: 7,
    dailyTarget: 5000,
    windowMode: 'ROLLING',
    durationDays: 7,
    rewardPoints: 70,
  },
  {
    key: 'fitness-30',
    type: 'INDIVIDUAL',
    title: '30-Day Fitness Challenge',
    description: 'Hit 5,000 verified steps on at least 25 of the next 30 days.',
    metric: 'DAILY_TARGET_DAYS',
    target: 25,
    dailyTarget: 5000,
    windowMode: 'ROLLING',
    durationDays: 30,
    rewardPoints: 300,
  },
];

export const ADMIN_SUGGESTED_TEMPLATES: ChallengeTemplate[] = [
  {
    key: 'campus-week-million',
    type: 'CAMPUS',
    title: 'Campus Step Week',
    description: 'Who walks the most verified steps this week?',
    metric: 'TOTAL_STEPS',
    target: 70000,
    dailyTarget: null,
    windowMode: 'FIXED',
    durationDays: 7,
    rewardPoints: 150,
  },
  {
    key: 'hostel-clash-week',
    type: 'INTER_HOSTEL',
    title: 'Hostel Clash',
    description: 'Hostels compete on average verified steps per participant.',
    metric: 'TOTAL_STEPS',
    target: 50000,
    dailyTarget: null,
    windowMode: 'FIXED',
    durationDays: 7,
    rewardPoints: 100,
  },
  {
    key: 'buddy-duel-3d',
    type: 'BUDDY',
    title: 'Buddy Duel',
    description: 'First buddy to the higher total over 3 days wins.',
    metric: 'TOTAL_STEPS',
    target: 20000,
    dailyTarget: null,
    windowMode: 'FIXED',
    durationDays: 3,
    rewardPoints: 100,
  },
];

export function templateChallengeId(key: string): string {
  return `tpl_${key}`;
}
