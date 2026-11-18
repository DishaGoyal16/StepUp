import type { Badge } from '../types'

export interface BadgeInputs {
  streak: number
  bestDaySteps: number
  weekSteps: number
  lifetimeSteps: number
  challengesJoined: number
  battles: number
  buddyRequests: number
}

const ratio = (v: number, t: number) => Math.max(0, Math.min(1, v / t))

/** Badges are computed from current (demo) stats so they respond to the user's actions. */
export function computeBadges(i: BadgeInputs): Badge[] {
  const defs: Omit<Badge, 'earned'>[] = [
    { id: 'first-10k', name: 'First 10K', description: 'Hit 10,000 steps in a day', icon: 'footprints', progress: ratio(i.bestDaySteps, 10000) },
    { id: 'spark', name: '3-Day Spark', description: 'Reach a 3-day goal streak', icon: 'zap', progress: ratio(i.streak, 3) },
    { id: 'week-warrior', name: 'Week Warrior', description: 'Keep a 7-day goal streak', icon: 'flame', progress: ratio(i.streak, 7) },
    { id: 'big-week', name: '70K Week', description: '70,000 steps in the last 7 days', icon: 'rocket', progress: ratio(i.weekSteps, 70000) },
    { id: '100k', name: '100K Club', description: '100,000 lifetime steps', icon: 'medal', progress: ratio(i.lifetimeSteps, 100000) },
    { id: '500k', name: 'Half Million', description: '500,000 lifetime steps', icon: 'crown', progress: ratio(i.lifetimeSteps, 500000) },
    { id: 'challenger', name: 'Challenger', description: 'Join a challenge', icon: 'target', progress: ratio(i.challengesJoined, 1) },
    { id: 'duelist', name: 'Duelist', description: 'Start a step battle', icon: 'swords', progress: ratio(i.battles, 1) },
    { id: 'social', name: 'Team Player', description: 'Send a buddy request', icon: 'users', progress: ratio(i.buddyRequests, 1) },
  ]
  return defs.map((d) => ({ ...d, earned: d.progress >= 1 }))
}
