import type { DayActivity } from '../types'

/** Consecutive days meeting the goal, counting back from yesterday (today counts once it hits the goal). */
export function computeStreak(history: DayActivity[], goal: number): number {
  let streak = 0
  const last = history.length - 1
  if (last >= 0 && history[last].steps >= goal) streak++
  for (let i = last - 1; i >= 0; i--) {
    if (history[i].steps >= goal) streak++
    else break
  }
  return streak
}

export const sum = (days: DayActivity[], key: 'steps' | 'distanceKm' | 'calories' | 'activeMinutes' = 'steps') =>
  days.reduce((a, d) => a + d[key], 0)

export function average(days: DayActivity[]): number {
  return days.length ? Math.round(sum(days) / days.length) : 0
}

export function bestDay(days: DayActivity[]): DayActivity | null {
  return days.reduce<DayActivity | null>((best, d) => (!best || d.steps > best.steps ? d : best), null)
}

export const pct = (value: number, goal: number) => (goal > 0 ? Math.min(100, Math.round((value / goal) * 100)) : 0)
