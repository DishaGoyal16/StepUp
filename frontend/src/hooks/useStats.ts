import { useMemo } from 'react'
import { DEMO_LIFETIME_STEPS } from '../data/demo'
import { computeBadges } from '../lib/rewards'
import { bestDay, computeStreak, sum } from '../lib/stats'
import { activityService } from '../services/activityService'
import { useApp } from './useApp'
import { useAsync } from './useAsync'

/** Shared derived numbers for Overview / Activity / Rewards, computed from the activity service. */
export function useStats() {
  const { state } = useApp()
  const history = useAsync(() => activityService.getHistory(), [])

  const derived = useMemo(() => {
    const days = history.data ?? []
    if (!days.length || !state) return null
    const today = days[days.length - 1]
    const week = days.slice(-7)
    const streak = computeStreak(days, state.user.dailyGoal)
    const best = bestDay(days)
    const weekSteps = sum(week)
    const badges = computeBadges({
      streak,
      bestDaySteps: best?.steps ?? 0,
      weekSteps,
      lifetimeSteps: DEMO_LIFETIME_STEPS,
      challengesJoined: Object.keys(state.joined).length,
      battles: state.battles.length,
      buddyRequests: state.requested.length,
    })
    return { days, today, week, streak, best, weekSteps, badges, lifetime: DEMO_LIFETIME_STEPS }
  }, [history.data, state])

  return { ...history, derived }
}
