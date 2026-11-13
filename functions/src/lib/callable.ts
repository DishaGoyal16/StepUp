import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { REGION } from '../config';
import { Req } from './auth';
import { isHttpsError } from './errors';

/** Wrap a plain handler `(req) => result` as a v2 callable in `asia-south1`. Handlers stay unit/integration testable. */
export function callable<R>(handler: (req: Req) => Promise<R>) {
  return onCall({ region: REGION, cors: true }, async (r: CallableRequest) => {
    try {
      return await handler({
        auth: r.auth ? { uid: r.auth.uid, token: r.auth.token as unknown as Record<string, unknown> } : null,
        data: r.data,
      });
    } catch (e) {
      if (isHttpsError(e)) throw e;
      logger.error('callable failed', { message: (e as Error).message });
      throw new HttpsError('internal', 'internal error', { reason: 'INTERNAL' });
    }
  });
}
