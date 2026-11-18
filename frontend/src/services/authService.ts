import { DEMO_ACCOUNT, DEMO_USER } from '../data/demo'
import type { User } from '../types'
import { ApiError, delay, http, safeGet, safeSet, TOKEN_KEY, USE_API } from './http'

/*
 * Local demo auth: accounts live in this browser's localStorage (salted SHA-256).
 * This is NOT real security — it exists so the dashboard is usable without a server.
 * With VITE_API_URL set, login/register go to the Express backend instead.
 */

const USERS_KEY = 'stepup.users.v1'
const SESSION_KEY = 'stepup.session.v1'

interface StoredAccount {
  user: User
  salt: string
  hash: string
}

function readUsers(): Record<string, StoredAccount> {
  try {
    return JSON.parse(safeGet(USERS_KEY) ?? '{}')
  } catch {
    return {}
  }
}

async function sha256(text: string): Promise<string> {
  const data = new TextEncoder().encode(text)
  const buf = await crypto.subtle.digest('SHA-256', data)
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('')
}

const normEmail = (e: string) => e.trim().toLowerCase()

export const authService = {
  getSessionEmail(): string | null {
    return safeGet(SESSION_KEY)
  },

  /** Returns the stored profile for a known session email (demo user or registered account). */
  getUser(email: string): User | null {
    if (email === DEMO_ACCOUNT.email) return DEMO_USER
    return readUsers()[email]?.user ?? null
  },

  async login(emailRaw: string, password: string): Promise<User> {
    const email = normEmail(emailRaw)
    if (USE_API) {
      const res = await http<{ token: string; user: User }>('/api/auth/login', {
        method: 'POST',
        body: JSON.stringify({ email, password }),
      })
      safeSet(TOKEN_KEY, res.token)
      safeSet(SESSION_KEY, email)
      return res.user
    }
    await delay(450)
    if (email === DEMO_ACCOUNT.email && password === DEMO_ACCOUNT.password) {
      safeSet(SESSION_KEY, email)
      return DEMO_USER
    }
    const acct = readUsers()[email]
    if (!acct || (await sha256(acct.salt + password)) !== acct.hash) {
      throw new ApiError('Incorrect email or password.', 401)
    }
    safeSet(SESSION_KEY, email)
    return acct.user
  },

  async register(name: string, emailRaw: string, password: string): Promise<User> {
    const email = normEmail(emailRaw)
    if (USE_API) {
      const res = await http<{ token: string; user: User }>('/api/auth/register', {
        method: 'POST',
        body: JSON.stringify({ name, email, password }),
      })
      safeSet(TOKEN_KEY, res.token)
      safeSet(SESSION_KEY, email)
      return res.user
    }
    await delay(450)
    const users = readUsers()
    if (email === DEMO_ACCOUNT.email || users[email]) {
      throw new ApiError('An account with this email already exists.', 409)
    }
    const salt = crypto.randomUUID()
    const user: User = {
      id: `u-${crypto.randomUUID().slice(0, 8)}`,
      name: name.trim(),
      email,
      city: '',
      bio: '',
      dailyGoal: 10000,
      units: 'km',
      joinedAt: new Date().toISOString().slice(0, 10),
    }
    users[email] = { user, salt, hash: await sha256(salt + password) }
    safeSet(USERS_KEY, JSON.stringify(users))
    safeSet(SESSION_KEY, email)
    return user
  },

  /** Persist profile edits for registered accounts. (Demo user edits live in the app-state blob.) */
  saveUser(user: User) {
    const users = readUsers()
    if (users[user.email]) {
      users[user.email].user = user
      safeSet(USERS_KEY, JSON.stringify(users))
    }
  },

  logout() {
    safeSet(SESSION_KEY, null)
    safeSet(TOKEN_KEY, null)
  },
}
