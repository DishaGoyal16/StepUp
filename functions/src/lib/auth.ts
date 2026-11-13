import { ALLOWED_EMAIL_DOMAIN, COL } from '../config';
import { fail } from './errors';
import { db, FieldValue } from './firebase';

/** Minimal shape shared by CallableRequest and test requests. */
export interface AuthLike {
  uid: string;
  token: Record<string, unknown>;
}
export interface Req<T = unknown> {
  auth?: AuthLike | null;
  data: T;
}

/** Exact-domain check: `local@thapar.edu`, case-insensitive; no subdomains, no look-alikes, no extra '@'. */
export function isThaparEmail(email: unknown): boolean {
  if (typeof email !== 'string') return false;
  const e = email.trim().toLowerCase();
  const m = /^([^@\s]+)@([^@\s]+)$/.exec(e);
  return !!m && m[2] === ALLOWED_EMAIL_DOMAIN;
}

export interface Caller {
  uid: string;
  email: string;
  token: Record<string, unknown>;
  isAdminClaim: boolean;
}

/** Auth present + verified @thapar.edu token. Does NOT require a profile (used by createProfile). */
export function requireThaparToken(req: Req): Caller {
  const auth = req.auth;
  if (!auth || !auth.uid) fail('unauthenticated', 'UNAUTHENTICATED', 'sign in required');
  const email = auth.token.email;
  if (!isThaparEmail(email)) fail('permission-denied', 'INVALID_EMAIL_DOMAIN', 'only @thapar.edu accounts are allowed');
  if (auth.token.email_verified !== true) fail('permission-denied', 'EMAIL_NOT_VERIFIED', 'verify your email first');
  return {
    uid: auth.uid,
    email: String(email).trim().toLowerCase(),
    token: auth.token,
    isAdminClaim: auth.token.admin === true,
  };
}

export interface Eligible extends Caller {
  user: FirebaseFirestore.DocumentData;
}

/** requireEligibleUser: token checks + profile exists + status ACTIVE. */
export async function requireEligibleUser(req: Req, opts: { allowDeletionRequested?: boolean } = {}): Promise<Eligible> {
  const caller = requireThaparToken(req);
  const snap = await db().collection(COL.users).doc(caller.uid).get();
  if (!snap.exists) fail('failed-precondition', 'PROFILE_REQUIRED', 'create your profile first');
  const user = snap.data() as FirebaseFirestore.DocumentData;
  if (user.status === 'DELETION_REQUESTED' && opts.allowDeletionRequested) return { ...caller, user };
  if (user.status === 'DELETION_REQUESTED') fail('permission-denied', 'ACCOUNT_DELETION_REQUESTED', 'account deletion was requested; this action is disabled');
  if (user.status === 'SUSPENDED') fail('permission-denied', 'ACCOUNT_SUSPENDED', 'account is suspended');
  if (user.status !== 'ACTIVE') fail('permission-denied', 'ACCOUNT_NOT_ACTIVE', 'account is not active');
  return { ...caller, user };
}

/** requireAdmin: `token.admin === true`. Every admin call is audit-logged (adminAudit). */
export async function requireAdmin(req: Req, action: string): Promise<Caller> {
  const auth = req.auth;
  if (!auth || !auth.uid) fail('unauthenticated', 'UNAUTHENTICATED', 'sign in required');
  if (auth.token.admin !== true) fail('permission-denied', 'ADMIN_REQUIRED', 'admin only');
  const caller: Caller = {
    uid: auth.uid,
    email: typeof auth.token.email === 'string' ? auth.token.email.toLowerCase() : '',
    token: auth.token,
    isAdminClaim: true,
  };
  await db().collection(COL.adminAudit).add({
    adminUid: caller.uid,
    action,
    details: sanitizeAudit(req.data),
    createdAt: FieldValue.serverTimestamp(),
  });
  return caller;
}

function sanitizeAudit(raw: unknown): Record<string, unknown> {
  const d = raw !== null && typeof raw === 'object' && !Array.isArray(raw) ? (raw as Record<string, unknown>) : {};
  // Keep audit entries small and JSON-ish; never store secrets/tokens (none are passed in).
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(d)) {
    if (v === undefined) continue;
    if (typeof v === 'string') out[k] = v.slice(0, 300);
    else if (typeof v === 'number' || typeof v === 'boolean') out[k] = v;
    else out[k] = '[object]';
  }
  return out;
}
