import type { RequestHandler } from 'express'
import type { ZodType } from 'zod'

/** Validates req.body or req.query with a zod schema; parsed value is stored in res.locals.data. */
export const validate =
  (schema: ZodType, source: 'body' | 'query' = 'body'): RequestHandler =>
  (req, res, next) => {
    res.locals.data = schema.parse(req[source]) // ZodError is turned into a 400 by errorHandler
    next()
  }
