import crypto from 'node:crypto'

const isProd = process.env.NODE_ENV === 'production'

function jwtSecret(): string {
  const s = process.env.JWT_SECRET
  if (s && s.length >= 16) return s
  if (isProd) {
    throw new Error('JWT_SECRET must be set (16+ characters) in production.')
  }
  // Dev only: random per-process secret so no weak default ever ships.
  console.warn('[config] JWT_SECRET not set — using a random dev secret (tokens reset on restart).')
  return crypto.randomBytes(32).toString('hex')
}

export const config = {
  port: Number(process.env.PORT ?? 4000),
  isProd,
  jwtSecret: jwtSecret(),
  // Comma-separated list of allowed origins, e.g. https://dxxxx.cloudfront.net
  corsOrigins: (process.env.CORS_ORIGIN ?? 'http://localhost:5173').split(',').map((s) => s.trim()).filter(Boolean),
  // When DATABASE_URL is set the Prisma repository should be used (see README). Demo mode otherwise.
  databaseUrl: process.env.DATABASE_URL ?? '',
}
