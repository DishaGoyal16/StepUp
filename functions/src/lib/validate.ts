import { fail } from './errors';

/** Small strict input validators. All failures are `invalid-argument` with `details.reason = INVALID_<FIELD>`. */

export type Rec = Record<string, unknown>;

export function asRecord(v: unknown, reason = 'INVALID_PAYLOAD'): Rec {
  if (v === null || typeof v !== 'object' || Array.isArray(v)) fail('invalid-argument', reason);
  return v as Rec;
}

function reasonFor(key: string): string {
  return `INVALID_${key.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toUpperCase()}`;
}

export interface StrOpts {
  min?: number;
  max?: number;
  pattern?: RegExp;
  trim?: boolean;
}

export function str(d: Rec, key: string, o: StrOpts = {}): string {
  const v = d[key];
  if (typeof v !== 'string') fail('invalid-argument', reasonFor(key));
  const s = o.trim === false ? v : v.trim();
  if (s.length < (o.min ?? 1) || s.length > (o.max ?? 500)) fail('invalid-argument', reasonFor(key));
  if (o.pattern && !o.pattern.test(s)) fail('invalid-argument', reasonFor(key));
  return s;
}

export function optStr(d: Rec, key: string, o: StrOpts = {}): string | undefined {
  if (d[key] === undefined || d[key] === null) return undefined;
  return str(d, key, { min: 0, ...o });
}

export function int(d: Rec, key: string, min: number, max: number): number {
  const v = d[key];
  if (typeof v !== 'number' || !Number.isInteger(v) || v < min || v > max) fail('invalid-argument', reasonFor(key));
  return v;
}

export function optInt(d: Rec, key: string, min: number, max: number): number | undefined {
  if (d[key] === undefined || d[key] === null) return undefined;
  return int(d, key, min, max);
}

export function bool(d: Rec, key: string): boolean {
  const v = d[key];
  if (typeof v !== 'boolean') fail('invalid-argument', reasonFor(key));
  return v;
}

export function optBool(d: Rec, key: string): boolean | undefined {
  if (d[key] === undefined || d[key] === null) return undefined;
  return bool(d, key);
}

export function oneOf<T extends string>(d: Rec, key: string, allowed: readonly T[]): T {
  const v = d[key];
  if (typeof v !== 'string' || !(allowed as readonly string[]).includes(v)) fail('invalid-argument', reasonFor(key));
  return v as T;
}

export function optOneOf<T extends string>(d: Rec, key: string, allowed: readonly T[]): T | undefined {
  if (d[key] === undefined || d[key] === null) return undefined;
  return oneOf(d, key, allowed);
}

export function strArray(
  d: Rec,
  key: string,
  o: { maxItems: number; maxLen: number; allowed?: readonly string[] },
): string[] {
  const v = d[key];
  if (!Array.isArray(v) || v.length > o.maxItems) fail('invalid-argument', reasonFor(key));
  const out: string[] = [];
  for (const item of v) {
    if (typeof item !== 'string') fail('invalid-argument', reasonFor(key));
    const s = item.trim();
    if (s.length < 1 || s.length > o.maxLen) fail('invalid-argument', reasonFor(key));
    if (o.allowed && !o.allowed.includes(s)) fail('invalid-argument', reasonFor(key));
    if (!out.includes(s)) out.push(s);
  }
  return out;
}

export function optStrArray(
  d: Rec,
  key: string,
  o: { maxItems: number; maxLen: number; allowed?: readonly string[] },
): string[] | undefined {
  if (d[key] === undefined || d[key] === null) return undefined;
  return strArray(d, key, o);
}

/** Firestore document-id safe token (uids, ids passed by clients). */
export const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

export function id(d: Rec, key: string): string {
  return str(d, key, { min: 1, max: 128, pattern: ID_PATTERN });
}

export function optId(d: Rec, key: string): string | undefined {
  if (d[key] === undefined || d[key] === null) return undefined;
  return id(d, key);
}

export function limitParam(d: Rec, def = 50, max = 100): number {
  const v = d.limit;
  if (v === undefined || v === null) return def;
  if (typeof v !== 'number' || !Number.isInteger(v) || v < 1) fail('invalid-argument', 'INVALID_LIMIT');
  return Math.min(v, max);
}
