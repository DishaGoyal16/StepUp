// Thin fetch wrapper. When VITE_API_URL is empty the app runs in local demo mode
// and the services below serve data from src/data/demo.ts instead.

export const API_URL = ((import.meta.env.VITE_API_URL as string | undefined) ?? '').replace(/\/$/, '')
export const USE_API = API_URL.length > 0

/** Flip to false once activity records come from a genuine source. Drives every "DEMO DATA" label. */
export const IS_DEMO_DATA = true

export const TOKEN_KEY = 'stepup.token'

export const delay = (ms = 320) => new Promise<void>((resolve) => setTimeout(resolve, ms))

export class ApiError extends Error {
  status: number
  constructor(message: string, status: number) {
    super(message)
    this.status = status
  }
}

export async function http<T>(path: string, init: RequestInit = {}): Promise<T> {
  const token = safeGet(TOKEN_KEY)
  const res = await fetch(`${API_URL}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(init.headers ?? {}),
    },
  })
  const body = await res.json().catch(() => ({}))
  if (!res.ok) throw new ApiError(body?.error ?? `Request failed (${res.status})`, res.status)
  return body as T
}

export function safeGet(key: string): string | null {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}

export function safeSet(key: string, value: string | null) {
  try {
    if (value === null) localStorage.removeItem(key)
    else localStorage.setItem(key, value)
  } catch {
    /* storage unavailable — app still works for this session */
  }
}
