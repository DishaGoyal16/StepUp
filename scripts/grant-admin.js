#!/usr/bin/env node
/**
 * Grant (or revoke) the `admin` custom claim for a @thapar.edu user.
 *
 *   node scripts/grant-admin.js student@thapar.edu [--revoke] [--project <id>]
 *
 * Emulator:  set FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 and FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
 *            (project defaults to demo-stepup).
 * Real project: run with Application Default Credentials of an authorised account
 *            (`gcloud auth application-default login`) and `--project <your-project-id>`.
 *            No keys or secrets are stored in this repository.
 *
 * The user must already exist in Firebase Auth (sign up in the app first). The user must sign in again (or refresh the
 * ID token) before the new claim is visible to callables / rules.
 */
'use strict';

const path = require('path');

function loadAdmin() {
  const resolved = require.resolve('firebase-admin', { paths: [path.join(__dirname, '..', 'functions')] });
  return require(resolved);
}

function parseArgs(argv) {
  const out = { email: null, revoke: false, project: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--revoke') out.revoke = true;
    else if (a === '--project') out.project = argv[++i];
    else if (!a.startsWith('--') && !out.email) out.email = a;
  }
  return out;
}

async function main() {
  const { email, revoke, project } = parseArgs(process.argv.slice(2));
  if (!email) {
    console.error('usage: node scripts/grant-admin.js <email@thapar.edu> [--revoke] [--project <id>]');
    process.exit(2);
  }
  const normalized = email.trim().toLowerCase();
  if (!/^[^@\s]+@thapar\.edu$/.test(normalized)) {
    console.error('refusing: only exact @thapar.edu addresses can be admins');
    process.exit(2);
  }
  const admin = loadAdmin();
  const projectId = project || process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || 'demo-stepup';
  admin.initializeApp({ projectId });

  const auth = admin.auth();
  let user;
  try {
    user = await auth.getUserByEmail(normalized);
  } catch (e) {
    console.error(`no Firebase Auth user with email ${normalized} (sign up in the app first)`);
    process.exit(1);
  }
  const claims = { ...(user.customClaims || {}), admin: !revoke };
  if (revoke) delete claims.admin;
  await auth.setCustomUserClaims(user.uid, claims);

  const db = admin.firestore();
  const role = revoke ? 'student' : 'admin';
  const userRef = db.collection('users').doc(user.uid);
  if ((await userRef.get()).exists) {
    await userRef.update({ role, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
  }
  await db
    .collection('adminSettings')
    .doc('admins')
    .set(
      {
        changes: admin.firestore.FieldValue.arrayUnion({ uid: user.uid, role, by: 'scripts/grant-admin.js', atMs: Date.now() }),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  console.log(`${revoke ? 'revoked admin from' : 'granted admin to'} ${normalized} (uid ${user.uid}, project ${projectId})`);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
