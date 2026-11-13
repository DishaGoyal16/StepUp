import { HttpsError } from 'firebase-functions/v2/https';
import { isThaparEmail, requireThaparToken } from '../../src/lib/auth';
import { assertThaparSignup } from '../../src/lib/signup';

describe('@thapar.edu domain check', () => {
  test.each(['a@thapar.edu', 'student.name+tag@thapar.edu', 'A@THAPAR.EDU', 'Mixed.Case@Thapar.Edu', '  a@thapar.edu  '])('accepts %p', (e) => {
    expect(isThaparEmail(e)).toBe(true);
  });

  test.each([
    'a@thapar.edu.evil.com',
    'a@mail.thapar.edu', // no subdomains
    'a@fakethapar.edu',
    'a@thapar.edux',
    'a@thapar.com',
    'a@@thapar.edu',
    'a@evil.com@thapar.edu',
    'a b@thapar.edu',
    '@thapar.edu',
    'thapar.edu',
    '',
    'a@gmail.com',
  ])('rejects %p', (e) => {
    expect(isThaparEmail(e)).toBe(false);
  });

  test.each([null, undefined, 42, {}, [], true])('rejects non-string %p', (v) => {
    expect(isThaparEmail(v)).toBe(false);
  });
});

describe('requireThaparToken (auth layer of requireEligibleUser)', () => {
  const ok = { uid: 'u1', token: { email: 'a@thapar.edu', email_verified: true } };
  const reason = (fn: () => unknown) => {
    try {
      fn();
    } catch (e) {
      expect(e).toBeInstanceOf(HttpsError);
      return { code: (e as HttpsError).code, reason: ((e as HttpsError).details as { reason: string }).reason };
    }
    throw new Error('expected throw');
  };

  test('valid verified thapar token passes and email is normalised', () => {
    const c = requireThaparToken({ auth: { ...ok, token: { ...ok.token, email: 'A@Thapar.EDU' } }, data: {} });
    expect(c.uid).toBe('u1');
    expect(c.email).toBe('a@thapar.edu');
    expect(c.isAdminClaim).toBe(false);
  });

  test('missing auth => unauthenticated', () => {
    expect(reason(() => requireThaparToken({ auth: null, data: {} }))).toEqual({ code: 'unauthenticated', reason: 'UNAUTHENTICATED' });
    expect(reason(() => requireThaparToken({ data: {} }))).toEqual({ code: 'unauthenticated', reason: 'UNAUTHENTICATED' });
  });

  test('non-thapar email => permission-denied INVALID_EMAIL_DOMAIN', () => {
    expect(reason(() => requireThaparToken({ auth: { uid: 'u', token: { email: 'a@gmail.com', email_verified: true } }, data: {} }))).toEqual({
      code: 'permission-denied',
      reason: 'INVALID_EMAIL_DOMAIN',
    });
  });

  test('unverified email => permission-denied EMAIL_NOT_VERIFIED', () => {
    expect(reason(() => requireThaparToken({ auth: { uid: 'u', token: { email: 'a@thapar.edu', email_verified: false } }, data: {} }))).toEqual({
      code: 'permission-denied',
      reason: 'EMAIL_NOT_VERIFIED',
    });
    expect(reason(() => requireThaparToken({ auth: { uid: 'u', token: { email: 'a@thapar.edu' } }, data: {} })).reason).toBe('EMAIL_NOT_VERIFIED');
  });

  test('admin claim must be exactly true', () => {
    expect(requireThaparToken({ auth: { ...ok, token: { ...ok.token, admin: true } }, data: {} }).isAdminClaim).toBe(true);
    expect(requireThaparToken({ auth: { ...ok, token: { ...ok.token, admin: 'true' } }, data: {} }).isAdminClaim).toBe(false);
  });
});

describe('beforeUserCreated logic', () => {
  test('allows thapar.edu', () => {
    expect(() => assertThaparSignup('x@thapar.edu')).not.toThrow();
  });
  test('rejects other domains, subdomains and missing email', () => {
    for (const e of ['x@gmail.com', 'x@a.thapar.edu', undefined, '']) expect(() => assertThaparSignup(e)).toThrow();
  });
});
