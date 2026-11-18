import type {
  ActivitySession, Battle, Buddy, Challenge, DayActivity, LeaderboardEntry, Milestone, Notice, StreakReward, User,
} from '../types'

/* ------------------------------------------------------------------ */
/*  ALL VALUES IN THIS FILE ARE DEMO DATA — not from a real tracker.  */
/*  Replace via the services in src/services when a real source or    */
/*  backend is connected.                                             */
/* ------------------------------------------------------------------ */

export const DEMO_DAILY_GOAL = 10000
export const DEMO_LIFETIME_STEPS = 412880
export const DEMO_POINTS = 2450

export const DEMO_ACCOUNT = { email: 'demo@stepup.app', password: 'demo1234' }

export const DEMO_USER: User = {
  id: 'u-demo',
  name: 'Alex Rivera',
  email: DEMO_ACCOUNT.email,
  city: 'Pune',
  bio: 'Morning walker, weekend hiker. Chasing 10k a day.',
  dailyGoal: DEMO_DAILY_GOAL,
  units: 'km',
  joinedAt: '2025-03-14',
}

export function isoDate(d: Date): string {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

function mulberry32(seed: number) {
  let a = seed
  return () => {
    a |= 0
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

// Estimates derived from steps (rough averages, NOT measured values)
export function deriveMetrics(steps: number) {
  return {
    distanceKm: Math.round(steps * 0.00066 * 10) / 10,
    calories: Math.round(steps * 0.0312),
    activeMinutes: Math.round(steps / 186),
  }
}

// Offsets -6..0 (last 7 days, 0 = today). Today is a partial day.
const LAST_WEEK = [8450, 10320, 11180, 10740, 12060, 10480, 7842]

export function buildHistory(days = 90): DayActivity[] {
  const out: DayActivity[] = []
  const now = new Date()
  for (let off = -(days - 1); off <= 0; off++) {
    const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + off)
    let steps: number
    if (off >= -6) {
      steps = LAST_WEEK[off + 6]
    } else {
      const rnd = mulberry32(d.getFullYear() * 400 + d.getMonth() * 31 + d.getDate())
      const weekend = d.getDay() === 0 || d.getDay() === 6
      steps = Math.round((4800 + rnd() * 7400 + (weekend ? 900 : 0)) / 10) * 10
    }
    out.push({ date: isoDate(d), steps, ...deriveMetrics(steps) })
  }
  return out
}

export const DEMO_SESSIONS: ActivitySession[] = [
  { id: 's1', type: 'Walk', title: 'Lunch stroll', when: 'Today · 1:05 PM', steps: 2882, durationMin: 24, distanceKm: 1.9 },
  { id: 's2', type: 'Walk', title: 'Commute walk', when: 'Today · 9:00 AM', steps: 1840, durationMin: 16, distanceKm: 1.2 },
  { id: 's3', type: 'Walk', title: 'Morning walk', when: 'Today · 7:10 AM', steps: 3120, durationMin: 28, distanceKm: 2.1 },
  { id: 's4', type: 'Run', title: 'Evening run', when: 'Yesterday · 6:30 PM', steps: 5200, durationMin: 34, distanceKm: 3.7 },
  { id: 's5', type: 'Hike', title: 'Hill trail loop', when: 'Sunday · 8:00 AM', steps: 8400, durationMin: 82, distanceKm: 5.6 },
]

export const DEMO_CHALLENGES: Challenge[] = [
  { id: 'sprint-7', title: '7-Day Step Sprint', description: 'Walk 70,000 steps in one week. Steady wins.', targetSteps: 70000, durationDays: 7, participants: 1284, icon: 'flame', difficulty: 'Medium', rewardPoints: 300 },
  { id: 'morning-5', title: 'Morning Mover', description: 'Log 25,000 steps over 5 days before noon.', targetSteps: 25000, durationDays: 5, participants: 642, icon: 'sunrise', difficulty: 'Easy', rewardPoints: 150 },
  { id: 'weekend', title: 'Weekend Warrior', description: 'Hit 30,000 steps across Saturday and Sunday.', targetSteps: 30000, durationDays: 2, participants: 903, icon: 'mountain', difficulty: 'Medium', rewardPoints: 200 },
  { id: 'monthly-300k', title: 'Monthly 300K', description: 'The big one: 300,000 steps in 30 days.', targetSteps: 300000, durationDays: 30, participants: 2210, icon: 'trophy', difficulty: 'Hard', rewardPoints: 900 },
  { id: 'explorer', title: 'City Explorer', description: 'Cover 150,000 steps in 14 days on new routes.', targetSteps: 150000, durationDays: 14, participants: 517, icon: 'compass', difficulty: 'Medium', rewardPoints: 450 },
  { id: 'fresh-start', title: 'Fresh Start 5K', description: 'New to this? 5,000 steps a day for 3 days.', targetSteps: 15000, durationDays: 3, participants: 3120, icon: 'sprout', difficulty: 'Easy', rewardPoints: 100 },
]

// Challenges the demo user has already joined, with demo progress (steps counted)
export const DEMO_JOINED: Record<string, number> = { 'sprint-7': 48210, 'morning-5': 17400 }

export const DEMO_BATTLES: Battle[] = [
  {
    id: 'b1', name: 'Office Showdown', durationDays: 7, daysElapsed: 4,
    participants: [
      { id: 'u-demo', name: 'You', steps: 41210, isYou: true },
      { id: 'f1', name: 'Maya Chen', steps: 44980 },
      { id: 'f2', name: 'Jordan Lee', steps: 38400 },
      { id: 'f3', name: 'Priya Nair', steps: 36115 },
    ],
  },
  {
    id: 'b2', name: 'Weekend Face-off', durationDays: 2, daysElapsed: 2,
    participants: [
      { id: 'u-demo', name: 'You', steps: 24300, isYou: true },
      { id: 'f4', name: 'Sam Okafor', steps: 21880 },
    ],
  },
]

export const DEMO_FRIENDS = [
  { id: 'f1', name: 'Maya Chen' },
  { id: 'f2', name: 'Jordan Lee' },
  { id: 'f3', name: 'Priya Nair' },
  { id: 'f4', name: 'Sam Okafor' },
  { id: 'f5', name: 'Lena Fischer' },
]

export const DEMO_LEADERS: LeaderboardEntry[] = [
  { id: 'l1', name: 'Maya Chen', city: 'Singapore', weekly: 98420, monthly: 392300, streak: 21 },
  { id: 'l2', name: 'Carlos Mendes', city: 'Lisbon', weekly: 91760, monthly: 371900, streak: 14 },
  { id: 'l3', name: 'Priya Nair', city: 'Bengaluru', weekly: 86305, monthly: 349800, streak: 17 },
  { id: 'l4', name: 'Jordan Lee', city: 'Toronto', weekly: 79880, monthly: 330450, streak: 9 },
  { id: 'l5', name: 'Lena Fischer', city: 'Berlin', weekly: 74150, monthly: 301200, streak: 12 },
  { id: 'l6', name: 'Sam Okafor', city: 'Lagos', weekly: 68900, monthly: 289700, streak: 6 },
  { id: 'l7', name: 'Aisha Khan', city: 'Dubai', weekly: 64210, monthly: 262100, streak: 4 },
  { id: 'l8', name: 'Tom Becker', city: 'Austin', weekly: 59870, monthly: 248600, streak: 3 },
  { id: 'l9', name: 'Nina Rossi', city: 'Milan', weekly: 55340, monthly: 227400, streak: 8 },
]

export const DEMO_BUDDIES: Buddy[] = [
  { id: 'bd1', name: 'Riya Kapoor', city: 'Pune', avgSteps: 10800, activity: 'Walk', pace: '5.5 km/h', availability: 'Weekday mornings', match: 94, bio: 'Park loops before work. Podcasts welcome.' },
  { id: 'bd2', name: 'Dev Malhotra', city: 'Pune', avgSteps: 13200, activity: 'Run', pace: '6:10 min/km', availability: 'Evenings & weekends', match: 88, bio: 'Training for a first half marathon.' },
  { id: 'bd3', name: 'Ananya Iyer', city: 'Mumbai', avgSteps: 9100, activity: 'Hike', pace: '3.8 km/h', availability: 'Saturdays', match: 81, bio: 'Sahyadri trails, sunrise starts.' },
  { id: 'bd4', name: 'Kabir Singh', city: 'Pune', avgSteps: 11500, activity: 'Walk', pace: '5.2 km/h', availability: 'Lunch breaks', match: 79, bio: 'Desk job escape artist. 20 min laps.' },
  { id: 'bd5', name: 'Meera Joshi', city: 'Nashik', avgSteps: 12400, activity: 'Cycle', pace: '18 km/h', availability: 'Sunday mornings', match: 72, bio: 'Long rides, café stops.' },
  { id: 'bd6', name: 'Arjun Das', city: 'Pune', avgSteps: 8700, activity: 'Walk', pace: '4.8 km/h', availability: 'Weekday evenings', match: 76, bio: 'Easy pace, good conversation.' },
]

export const DEMO_NOTICES: Notice[] = [
  { id: 'n1', title: 'Streak alive', body: 'You are on a 5-day goal streak. Keep it going today!', time: '2h ago' },
  { id: 'n2', title: 'Maya passed you', body: 'Maya Chen took the lead in Office Showdown.', time: '5h ago' },
  { id: 'n3', title: 'New challenge', body: 'Fresh Start 5K is open — 3 easy days.', time: 'Yesterday' },
  { id: 'n4', title: 'Buddy suggestion', body: 'Riya Kapoor is a 94% match near you.', time: '2 days ago' },
]

export const STREAK_REWARDS: StreakReward[] = [
  { days: 3, points: 50, label: '3-day spark' },
  { days: 5, points: 100, label: '5-day flame' },
  { days: 7, points: 200, label: 'Week warrior' },
  { days: 14, points: 500, label: 'Fortnight force' },
  { days: 30, points: 1500, label: 'Monthly legend' },
]

export const MILESTONES: Milestone[] = [
  { id: 'm1', label: '100K lifetime steps', target: 100000 },
  { id: 'm2', label: '250K lifetime steps', target: 250000 },
  { id: 'm3', label: '500K lifetime steps', target: 500000 },
  { id: 'm4', label: '1M lifetime steps', target: 1000000 },
]
