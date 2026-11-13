import * as admin from 'firebase-admin';
import { getFirestore, FieldValue, Timestamp, Firestore } from 'firebase-admin/firestore';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

export function db(): Firestore {
  return getFirestore();
}

export { FieldValue, Timestamp, admin };

export function tsFromMs(ms: number): Timestamp {
  return Timestamp.fromMillis(ms);
}
