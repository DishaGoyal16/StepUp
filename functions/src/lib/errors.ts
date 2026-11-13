import { HttpsError, FunctionsErrorCode } from 'firebase-functions/v2/https';

/** Throw an HttpsError whose `details.reason` is a stable machine-readable code. */
export function fail(code: FunctionsErrorCode, reason: string, message?: string): never {
  throw new HttpsError(code, message ?? reason.toLowerCase().replace(/_/g, ' '), { reason });
}

export function isHttpsError(e: unknown): e is HttpsError {
  return e instanceof HttpsError;
}
