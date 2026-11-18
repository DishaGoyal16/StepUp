import type { RequestHandler } from 'express'
import bcrypt from 'bcryptjs'
import { z } from 'zod'
import { signToken } from '../middleware/auth.js'
import { HttpError } from '../middleware/errors.js'
import { toPublic, userStore } from '../data/store.js'

export const registerSchema = z.object({
  name: z.string().trim().min(2, 'Name must be at least 2 characters').max(60),
  email: z.string().trim().toLowerCase().pipe(z.email('Enter a valid email address')),
  password: z.string().min(8, 'Password must be at least 8 characters').max(128),
})

export const loginSchema = z.object({
  email: z.string().trim().toLowerCase().pipe(z.email('Enter a valid email address')),
  password: z.string().min(1, 'Password is required').max(128),
})

export const register: RequestHandler = async (_req, res) => {
  const { name, email, password } = res.locals.data as z.infer<typeof registerSchema>
  if (userStore.findByEmail(email)) throw new HttpError(409, 'An account with this email already exists.')
  const user = await userStore.create({ name, email, password })
  res.status(201).json({ token: signToken(user.id), user: toPublic(user) })
}

export const login: RequestHandler = async (_req, res) => {
  const { email, password } = res.locals.data as z.infer<typeof loginSchema>
  const user = userStore.findByEmail(email)
  // Same message for unknown email and wrong password
  if (!user || !(await bcrypt.compare(password, user.passwordHash))) {
    throw new HttpError(401, 'Incorrect email or password.')
  }
  res.json({ token: signToken(user.id), user: toPublic(user) })
}
