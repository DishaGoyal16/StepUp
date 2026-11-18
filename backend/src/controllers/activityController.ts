import type { RequestHandler } from 'express'
import { z } from 'zod'
import { buildHistory, sessions } from '../data/store.js'

export const historyQuery = z.object({
  days: z.coerce.number().int().min(1).max(365).default(30),
})

// NOTE: demo data. Replace with records supplied by a real external activity source later.
export const getHistory: RequestHandler = (_req, res) => {
  const { days } = res.locals.data as z.infer<typeof historyQuery>
  res.json({ source: 'demo', days: buildHistory(days) })
}

export const getSessions: RequestHandler = (_req, res) => {
  res.json({ source: 'demo', sessions })
}
