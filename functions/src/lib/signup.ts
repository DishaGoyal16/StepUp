import { HttpsError } from 'firebase-functions/v2/identity';
import { isThaparEmail } from './auth';

/** Used by the `beforeUserCreated` blocking function. Pure so it is unit-testable. */
export function assertThaparSignup(email: unknown): void {
  if (!isThaparEmail(email)) {
    throw new HttpsError('invalid-argument', 'Only @thapar.edu email addresses can register.');
  }
}
