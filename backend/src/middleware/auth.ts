import type { RequestHandler } from 'express'
import jwt from 'jsonwebtoken'
import { config } from '../config.js'
import { HttpError } from './errors.js'

export function signToken(userId: string): string {
  return jwt.sign({ sub: userId }, config.jwtSecret, { expiresIn: '7d' })
}

export const requireAuth: RequestHandler = (req, res, next) => {
  const header = req.headers.authorization ?? ''
  const token = header.startsWith('Bearer ') ? header.slice(7) : ''
  if (!token) throw new HttpError(401, 'Authentication required')
  try {
    const payload = jwt.verify(token, config.jwtSecret) as jwt.JwtPayload
    if (typeof payload.sub !== 'string') throw new Error('bad payload')
    res.locals.userId = payload.sub
    next()
  } catch {
    throw new HttpError(401, 'Invalid or expired token')
  }
}
