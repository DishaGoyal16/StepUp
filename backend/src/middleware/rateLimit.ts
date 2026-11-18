import type { RequestHandler } from 'express'
import { HttpError } from './errors.js'

/** Minimal in-memory fixed-window limiter (per IP). Use a shared store (e.g. Redis/WAF) when running >1 instance. */
export function rateLimit(max: number, windowMs: number): RequestHandler {
  const hits = new Map<string, { count: number; reset: number }>()
  return (req, _res, next) => {
    const now = Date.now()
    const key = req.ip ?? 'unknown'
    const entry = hits.get(key)
    if (!entry || entry.reset < now) {
      hits.set(key, { count: 1, reset: now + windowMs })
      return next()
    }
    entry.count++
    if (entry.count > max) throw new HttpError(429, 'Too many attempts. Please try again shortly.')
    next()
  }
}
