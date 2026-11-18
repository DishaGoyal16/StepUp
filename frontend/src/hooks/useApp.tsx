import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { DEMO_ACCOUNT, DEMO_BATTLES, DEMO_JOINED, DEMO_POINTS } from '../data/demo'
import { authService } from '../services/authService'
import { safeGet, safeSet } from '../services/http'
import type { Battle, User } from '../types'

export interface AppState {
  user: User
  joined: Record<string, number> // challengeId -> steps counted (demo)
  battles: Battle[]
  requested: string[] // buddy ids with a pending request
  claimed: number[] // streak reward day-thresholds already claimed
  points: number
  noticesRead: boolean
  prefs: { daily: boolean; battles: boolean; weekly: boolean }
}

interface Toast {
  id: number
  message: string
}

interface AppContextValue {
  state: AppState | null
  user: User | null
  login: (email: string, password: string) => Promise<void>
  register: (name: string, email: string, password: string) => Promise<void>
  logout: () => void
  updateUser: (patch: Partial<User>) => void
  updatePrefs: (patch: Partial<AppState['prefs']>) => void
  joinChallenge: (id: string, startSteps: number) => void
  leaveChallenge: (id: string) => void
  createBattle: (name: string, friends: { id: string; name: string }[], durationDays: number) => void
  simulateBattleDay: (id: string) => void
  removeBattle: (id: string) => void
  toggleBuddy: (id: string) => void
  claimStreak: (days: number, points: number) => void
  markNoticesRead: () => void
  resetDemo: () => void
  toast: (message: string) => void
  toasts: Toast[]
}

const AppContext = createContext<AppContextValue | null>(null)
const stateKey = (email: string) => `stepup.state.v1.${email}`

function initialState(user: User): AppState {
  const isDemo = user.email === DEMO_ACCOUNT.email
  return {
    user,
    joined: isDemo ? { ...DEMO_JOINED } : {},
    battles: isDemo ? structuredClone(DEMO_BATTLES) : [],
    requested: [],
    claimed: [],
    points: isDemo ? DEMO_POINTS : 0,
    noticesRead: false,
    prefs: { daily: true, battles: true, weekly: false },
  }
}

function loadState(email: string): AppState | null {
  try {
    const raw = safeGet(stateKey(email))
    if (raw) return JSON.parse(raw) as AppState
  } catch {
    /* corrupted blob — fall through to a fresh state */
  }
  const user = authService.getUser(email)
  return user ? initialState(user) : null
}

export function AppProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AppState | null>(() => {
    const email = authService.getSessionEmail()
    return email ? loadState(email) : null
  })
  const [toasts, setToasts] = useState<Toast[]>([])
  const toastId = useRef(0)

  // Persist on every change
  useEffect(() => {
    if (state) safeSet(stateKey(state.user.email), JSON.stringify(state))
  }, [state])

  const toast = useCallback((message: string) => {
    const id = ++toastId.current
    setToasts((t) => [...t, { id, message }])
    setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 3200)
  }, [])

  const patch = useCallback((fn: (s: AppState) => AppState) => setState((s) => (s ? fn(s) : s)), [])

  const value = useMemo<AppContextValue>(
    () => ({
      state,
      user: state?.user ?? null,
      toasts,
      toast,

      async login(email, password) {
        const user = await authService.login(email, password)
        setState(loadState(user.email) ?? initialState(user))
      },
      async register(name, email, password) {
        const user = await authService.register(name, email, password)
        setState(initialState(user))
      },
      logout() {
        authService.logout()
        setState(null)
      },

      updateUser(p) {
        patch((s) => {
          const user = { ...s.user, ...p }
          authService.saveUser(user)
          return { ...s, user }
        })
      },
      updatePrefs(p) {
        patch((s) => ({ ...s, prefs: { ...s.prefs, ...p } }))
      },

      joinChallenge(id, startSteps) {
        patch((s) => ({ ...s, joined: { ...s.joined, [id]: startSteps } }))
      },
      leaveChallenge(id) {
        patch((s) => {
          const joined = { ...s.joined }
          delete joined[id]
          return { ...s, joined }
        })
      },

      createBattle(name, friends, durationDays) {
        patch((s) => ({
          ...s,
          battles: [
            {
              id: `b-${Date.now()}`,
              name,
              durationDays,
              daysElapsed: 0,
              participants: [
                { id: s.user.id, name: 'You', steps: 0, isYou: true },
                ...friends.map((f) => ({ id: f.id, name: f.name, steps: 0 })),
              ],
            },
            ...s.battles,
          ],
        }))
      },
      simulateBattleDay(id) {
        patch((s) => ({
          ...s,
          battles: s.battles.map((b) => {
            if (b.id !== id || b.daysElapsed >= b.durationDays) return b
            return {
              ...b,
              daysElapsed: b.daysElapsed + 1,
              participants: b.participants.map((p) => ({
                ...p,
                steps: p.steps + 5000 + Math.floor(Math.random() * 7500),
              })),
            }
          }),
        }))
      },
      removeBattle(id) {
        patch((s) => ({ ...s, battles: s.battles.filter((b) => b.id !== id) }))
      },

      toggleBuddy(id) {
        patch((s) => ({
          ...s,
          requested: s.requested.includes(id) ? s.requested.filter((x) => x !== id) : [...s.requested, id],
        }))
      },

      claimStreak(days, points) {
        patch((s) => (s.claimed.includes(days) ? s : { ...s, claimed: [...s.claimed, days], points: s.points + points }))
      },

      markNoticesRead() {
        patch((s) => ({ ...s, noticesRead: true }))
      },

      resetDemo() {
        patch((s) => initialState(s.user))
      },
    }),
    [state, toasts, toast, patch],
  )

  return <AppContext.Provider value={value}>{children}</AppContext.Provider>
}

export function useApp(): AppContextValue {
  const ctx = useContext(AppContext)
  if (!ctx) throw new Error('useApp must be used inside <AppProvider>')
  return ctx
}

/** For pages rendered behind <RequireAuth>, where the state is guaranteed. */
export function useAppState(): AppState {
  const { state } = useApp()
  if (!state) throw new Error('No signed-in user')
  return state
}
