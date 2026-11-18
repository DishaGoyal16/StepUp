/*
 * DEMO STORE — in-memory data so the API runs with no database.
 * Everything here is sample data, reset on every restart.
 * To go real: implement the same functions against PostgreSQL via Prisma
 * (see prisma/schema.prisma) and swap the import in the controllers.
 */
import bcrypt from 'bcryptjs'
import crypto from 'node:crypto'

export interface UserRecord {
  id: string
  name: string
  email: string
  passwordHash: string
  city: string
  bio: string
  dailyGoal: number
  units: 'km' | 'mi'
  joinedAt: string
}

export type PublicUser = Omit<UserRecord, 'passwordHash'>

export const toPublic = ({ passwordHash: _omit, ...rest }: UserRecord): PublicUser => rest

const users = new Map<string, UserRecord>()

export const DEMO_EMAIL = 'demo@stepup.app'

users.set(
  DEMO_EMAIL,
  {
    id: 'u-demo',
    name: 'Alex Rivera',
    email: DEMO_EMAIL,
    passwordHash: bcrypt.hashSync('demo1234', 10),
    city: 'Pune',
    bio: 'Morning walker, weekend hiker. Chasing 10k a day.',
    dailyGoal: 10000,
    units: 'km',
    joinedAt: '2025-03-14',
  },
)

export const userStore = {
  findByEmail: (email: string) => users.get(email.toLowerCase()),
  findById: (id: string) => [...users.values()].find((u) => u.id === id),
  async create(input: { name: string; email: string; password: string }): Promise<UserRecord> {
    const rec: UserRecord = {
      id: `u-${crypto.randomUUID().slice(0, 8)}`,
      name: input.name,
      email: input.email.toLowerCase(),
      passwordHash: await bcrypt.hash(input.password, 10),
      city: '',
      bio: '',
      dailyGoal: 10000,
      units: 'km',
      joinedAt: new Date().toISOString().slice(0, 10),
    }
    users.set(rec.email, rec)
    return rec
  },
  update(id: string, patch: Partial<Pick<UserRecord, 'name' | 'city' | 'bio' | 'dailyGoal' | 'units'>>) {
    const u = userStore.findById(id)
    if (!u) return undefined
    Object.assign(u, patch)
    return u
  },
}

/* --------------------------- Activity (demo) --------------------------- */
const pad = (n: number) => String(n).padStart(2, '0')
const isoDate = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`

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

const LAST_WEEK = [8450, 10320, 11180, 10740, 12060, 10480, 7842]

export function buildHistory(days: number) {
  const out: { date: string; steps: number; distanceKm: number; calories: number; activeMinutes: number }[] = []
  const now = new Date()
  for (let off = -(days - 1); off <= 0; off++) {
    const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + off)
    let steps: number
    if (off >= -6) steps = LAST_WEEK[off + 6]
    else {
      const rnd = mulberry32(d.getFullYear() * 400 + d.getMonth() * 31 + d.getDate())
      const weekend = d.getDay() === 0 || d.getDay() === 6
      steps = Math.round((4800 + rnd() * 7400 + (weekend ? 900 : 0)) / 10) * 10
    }
    out.push({
      date: isoDate(d),
      steps,
      distanceKm: Math.round(steps * 0.00066 * 10) / 10, // estimate
      calories: Math.round(steps * 0.0312), // estimate
      activeMinutes: Math.round(steps / 186), // estimate
    })
  }
  return out
}

export const sessions = [
  { id: 's1', type: 'Walk', title: 'Lunch stroll', when: 'Today · 1:05 PM', steps: 2882, durationMin: 24, distanceKm: 1.9 },
  { id: 's2', type: 'Walk', title: 'Commute walk', when: 'Today · 9:00 AM', steps: 1840, durationMin: 16, distanceKm: 1.2 },
  { id: 's3', type: 'Walk', title: 'Morning walk', when: 'Today · 7:10 AM', steps: 3120, durationMin: 28, distanceKm: 2.1 },
  { id: 's4', type: 'Run', title: 'Evening run', when: 'Yesterday · 6:30 PM', steps: 5200, durationMin: 34, distanceKm: 3.7 },
  { id: 's5', type: 'Hike', title: 'Hill trail loop', when: 'Sunday · 8:00 AM', steps: 8400, durationMin: 82, distanceKm: 5.6 },
]

/* ----------------------- Challenges & leaderboard ---------------------- */
export const challenges = [
  { id: 'sprint-7', title: '7-Day Step Sprint', description: 'Walk 70,000 steps in one week. Steady wins.', targetSteps: 70000, durationDays: 7, participants: 1284, icon: 'flame', difficulty: 'Medium', rewardPoints: 300 },
  { id: 'morning-5', title: 'Morning Mover', description: 'Log 25,000 steps over 5 days before noon.', targetSteps: 25000, durationDays: 5, participants: 642, icon: 'sunrise', difficulty: 'Easy', rewardPoints: 150 },
  { id: 'weekend', title: 'Weekend Warrior', description: 'Hit 30,000 steps across Saturday and Sunday.', targetSteps: 30000, durationDays: 2, participants: 903, icon: 'mountain', difficulty: 'Medium', rewardPoints: 200 },
  { id: 'monthly-300k', title: 'Monthly 300K', description: 'The big one: 300,000 steps in 30 days.', targetSteps: 300000, durationDays: 30, participants: 2210, icon: 'trophy', difficulty: 'Hard', rewardPoints: 900 },
  { id: 'explorer', title: 'City Explorer', description: 'Cover 150,000 steps in 14 days on new routes.', targetSteps: 150000, durationDays: 14, participants: 517, icon: 'compass', difficulty: 'Medium', rewardPoints: 450 },
  { id: 'fresh-start', title: 'Fresh Start 5K', description: 'New to this? 5,000 steps a day for 3 days.', targetSteps: 15000, durationDays: 3, participants: 3120, icon: 'sprout', difficulty: 'Easy', rewardPoints: 100 },
]

export const leaders = [
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
