export interface User {
  id: string
  name: string
  email: string
  city: string
  bio: string
  dailyGoal: number
  units: 'km' | 'mi'
  joinedAt: string
}

export interface DayActivity {
  date: string // YYYY-MM-DD (local)
  steps: number
  distanceKm: number
  calories: number
  activeMinutes: number
}

export type SessionType = 'Walk' | 'Run' | 'Hike' | 'Cycle'

export interface ActivitySession {
  id: string
  type: SessionType
  title: string
  when: string
  steps: number
  durationMin: number
  distanceKm: number
}

export interface Challenge {
  id: string
  title: string
  description: string
  targetSteps: number
  durationDays: number
  participants: number
  icon: string
  difficulty: 'Easy' | 'Medium' | 'Hard'
  rewardPoints: number
}

export interface BattleParticipant {
  id: string
  name: string
  steps: number
  isYou?: boolean
}

export interface Battle {
  id: string
  name: string
  durationDays: number
  daysElapsed: number
  participants: BattleParticipant[]
}

export interface LeaderboardEntry {
  id: string
  name: string
  city: string
  weekly: number
  monthly: number
  streak: number
  isYou?: boolean
}

export interface Buddy {
  id: string
  name: string
  city: string
  avgSteps: number
  activity: SessionType
  pace: string
  availability: string
  match: number
  bio: string
}

export interface Notice {
  id: string
  title: string
  body: string
  time: string
}

export interface Badge {
  id: string
  name: string
  description: string
  icon: string
  earned: boolean
  progress: number // 0..1
}

export interface Milestone {
  id: string
  label: string
  target: number
}

export interface StreakReward {
  days: number
  points: number
  label: string
}
