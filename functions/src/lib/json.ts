import { Timestamp } from 'firebase-admin/firestore';

/** Convert Firestore data to a callable-safe JSON value: Timestamps become epoch milliseconds. */
export function toJson<T = unknown>(v: unknown): T {
  if (v instanceof Timestamp) return v.toMillis() as unknown as T;
  if (Array.isArray(v)) return v.map((x) => toJson(x)) as unknown as T;
  if (v !== null && typeof v === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, x] of Object.entries(v as Record<string, unknown>)) out[k] = toJson(x);
    return out as T;
  }
  return v as T;
}
