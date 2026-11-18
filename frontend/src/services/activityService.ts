import { buildHistory, DEMO_LIFETIME_STEPS, DEMO_SESSIONS } from '../data/demo'
import type { ActivitySession, DayActivity } from '../types'
import { delay, http, USE_API } from './http'

// Swap point: replace the demo branches with the real activity source / API later.
let historyCache: Promise<DayActivity[]> | null = null

export const activityService = {
  /** Daily activity, oldest → newest, last entry is today. */
  getHistory(): Promise<DayActivity[]> {
    if (!historyCache) {
      historyCache = (
        USE_API
          ? http<{ days: DayActivity[] }>('/api/activity/history?days=90').then((r) => r.days)
          : delay().then(() => buildHistory(90))
      ).catch((err) => {
        historyCache = null
        throw err
      })
    }
    return historyCache
  },

  async getSessions(): Promise<ActivitySession[]> {
    if (USE_API) return (await http<{ sessions: ActivitySession[] }>('/api/activity/sessions')).sessions
    await delay(200)
    return DEMO_SESSIONS
  },

  async getLifetimeSteps(): Promise<number> {
    return DEMO_LIFETIME_STEPS
  },
}
