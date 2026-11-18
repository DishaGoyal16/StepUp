import { Router } from 'express'
import { getHistory, getSessions, historyQuery } from '../controllers/activityController.js'
import { login, loginSchema, register, registerSchema } from '../controllers/authController.js'
import { listChallenges, listLeaderboard } from '../controllers/communityController.js'
import { getMe, updateMe, updateMeSchema } from '../controllers/userController.js'
import { requireAuth } from '../middleware/auth.js'
import { rateLimit } from '../middleware/rateLimit.js'
import { validate } from '../middleware/validate.js'

export const api = Router()

// Health check (used by App Runner)
api.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'stepup-api', mode: 'demo', time: new Date().toISOString() })
})

// Auth
const authLimiter = rateLimit(20, 60_000)
api.post('/auth/register', authLimiter, validate(registerSchema), register)
api.post('/auth/login', authLimiter, validate(loginSchema), login)

// User
api.get('/users/me', requireAuth, getMe)
api.patch('/users/me', requireAuth, validate(updateMeSchema), updateMe)

// Activity
api.get('/activity/history', requireAuth, validate(historyQuery, 'query'), getHistory)
api.get('/activity/sessions', requireAuth, getSessions)

// Community
api.get('/challenges', requireAuth, listChallenges)
api.get('/leaderboard', requireAuth, listLeaderboard)
