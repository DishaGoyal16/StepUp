export interface BadgeDef {
  title: string;
  description: string;
  icon: string;
  rule: string;
  points: number;
}

/** Badge catalogue (`adminSettings/badges`). Points are virtual and awarded once per badge per user. */
export const BADGE_CATALOGUE: Record<string, BadgeDef> = {
  FIRST_1K: {
    title: 'First 1,000',
    description: 'Walk your first 1,000 verified steps.',
    icon: 'directions_walk',
    rule: 'lifetimeVerifiedSteps >= 1000',
    points: 10,
  },
  TEN_K_WALKER: {
    title: '10K Walker',
    description: 'Reach 10,000 verified steps in a single day.',
    icon: 'emoji_events',
    rule: 'a day with verifiedSteps >= 10000',
    points: 20,
  },
  STREAK_7: {
    title: '7-Day Streak',
    description: 'Hit your daily goal 7 days in a row.',
    icon: 'local_fire_department',
    rule: 'streak >= 7 (the streak points are paid separately)',
    points: 0,
  },
  CHALLENGE_CHAMPION: {
    title: 'Challenge Champion',
    description: 'Win a buddy or campus challenge.',
    icon: 'military_tech',
    rule: 'winnerUid of a finalized BUDDY/CAMPUS challenge',
    points: 25,
  },
  HOSTEL_CHAMPION: {
    title: 'Hostel Champion',
    description: 'Your hostel won an inter-hostel challenge.',
    icon: 'apartment',
    rule: 'participant of the winning hostel in an INTER_HOSTEL challenge',
    points: 25,
  },
  CAMPUS_FITNESS_STAR: {
    title: 'Campus Fitness Star',
    description: 'Finish first in a campus-wide challenge.',
    icon: 'star',
    rule: 'rank 1 of a finalized CAMPUS challenge',
    points: 50,
  },
};
