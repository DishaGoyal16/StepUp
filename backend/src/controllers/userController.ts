import type { RequestHandler } from 'express'
import { z } from 'zod'
import { HttpError } from '../middleware/errors.js'
import { toPublic, userStore } from '../data/store.js'

export const updateMeSchema = z
  .object({
    name: z.string().trim().min(2).max(60),
    city: z.string().trim().max(60),
    bio: z.string().trim().max(160),
    dailyGoal: z.number().int().min(1000).max(50000),
    units: z.enum(['km', 'mi']),
  })
  .partial()
  .strict()

export const getMe: RequestHandler = (_req, res) => {
  const user = userStore.findById(res.locals.userId)
  if (!user) throw new HttpError(404, 'User not found')
  res.json({ user: toPublic(user) })
}

export const updateMe: RequestHandler = (_req, res) => {
  const patch = res.locals.data as z.infer<typeof updateMeSchema>
  const user = userStore.update(res.locals.userId, patch)
  if (!user) throw new HttpError(404, 'User not found')
  res.json({ user: toPublic(user) })
}
