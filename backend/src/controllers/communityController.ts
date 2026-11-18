import type { RequestHandler } from 'express'
import { challenges, leaders } from '../data/store.js'

export const listChallenges: RequestHandler = (_req, res) => {
  res.json({ source: 'demo', challenges })
}

export const listLeaderboard: RequestHandler = (_req, res) => {
  res.json({ source: 'demo', entries: leaders })
}
