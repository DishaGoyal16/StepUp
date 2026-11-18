import { DEMO_BUDDIES, DEMO_CHALLENGES, DEMO_FRIENDS, DEMO_LEADERS, DEMO_NOTICES } from '../data/demo'
import type { Buddy, Challenge, LeaderboardEntry, Notice } from '../types'
import { delay, http, USE_API } from './http'

export const communityService = {
  async getChallenges(): Promise<Challenge[]> {
    if (USE_API) return (await http<{ challenges: Challenge[] }>('/api/challenges')).challenges
    await delay()
    return DEMO_CHALLENGES
  },

  /** Other users only; the current user is merged in by the page from their own activity. */
  async getLeaderboard(): Promise<LeaderboardEntry[]> {
    if (USE_API) return (await http<{ entries: LeaderboardEntry[] }>('/api/leaderboard')).entries
    await delay()
    return DEMO_LEADERS
  },

  async getBuddies(): Promise<Buddy[]> {
    await delay()
    return DEMO_BUDDIES
  },

  async getFriends() {
    return DEMO_FRIENDS
  },

  async getNotices(): Promise<Notice[]> {
    return DEMO_NOTICES
  },
}
