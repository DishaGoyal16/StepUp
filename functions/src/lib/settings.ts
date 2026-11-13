import { COL, DEFAULT_SETTINGS, GlobalSettings } from '../config';
import { db } from './firebase';

/** Read adminSettings/global merged over defaults (missing doc or fields fall back to the schema defaults). */
export async function getSettings(tx?: FirebaseFirestore.Transaction): Promise<GlobalSettings> {
  const ref = db().collection(COL.adminSettings).doc('global');
  const snap = tx ? await tx.get(ref) : await ref.get();
  return mergeSettings(snap.exists ? snap.data() : undefined);
}

export function mergeSettings(stored: Record<string, unknown> | undefined): GlobalSettings {
  const out: Record<string, unknown> = { ...DEFAULT_SETTINGS };
  if (stored) {
    for (const k of Object.keys(DEFAULT_SETTINGS)) {
      const v = stored[k];
      if (v !== undefined && v !== null && typeof v === typeof (DEFAULT_SETTINGS as unknown as Record<string, unknown>)[k]) {
        out[k] = v;
      }
    }
  }
  return out as unknown as GlobalSettings;
}
