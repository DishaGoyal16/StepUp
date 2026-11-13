#!/usr/bin/env node
/**
 * DEMO seed for presenting StepUp from the LOCAL Firebase emulators. Run scripts/demo-reset-and-seed.ps1 (wipes + base seed + this).
 *
 *   PRESENTER_EMAIL=you@thapar.edu PRESENTER_PASSWORD=... [PRESENTER_NAME=Disha] node scripts/seed-demo.js
 *
 * What it creates (all through the REAL callables with real ID tokens, so every server rule applies):
 *   * the presenter's own account (verified, onboarded, NO step history: their steps must be walked live),
 *   * demo.admin@thapar.edu (admin) and demo.student@thapar.edu (pre-loaded: points + a bet),
 *   * four clearly labelled "(sample)" students with SYNTHETIC step history for the last 3 days
 *     (hand-built buckets sent through the real syncStepBuckets path, NOT walked) so leaderboards/podium/challenges are not empty,
 *   * one pending + one accepted buddy request for the presenter, a campus challenge and an individual challenge, one active bet.
 * Everything except the presenter's live steps is DEMO DATA and must be presented as such.
 *
 * SAFETY: refuses to run unless the Auth/Firestore/Functions emulators are on this machine (never a real Firebase project).
 * No passwords are stored in this repo: the presenter password comes from the environment; the demo accounts use DEMO_PASSWORD
 * (default below, demo-only, local emulator only).
 */
'use strict';

const path = require('path');
const { randomUUID } = require('crypto');
const { execFileSync } = require('child_process');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
const FN_HOST = process.env.FUNCTIONS_EMULATOR_HOST || '127.0.0.1:5001';
for (const h of [process.env.FIRESTORE_EMULATOR_HOST, process.env.FIREBASE_AUTH_EMULATOR_HOST, FN_HOST]) {
  if (!/^(127\.0\.0\.1|localhost):\d+$/.test(h)) {
    console.error(`refusing to run: ${h} is not a local emulator address`);
    process.exit(2);
  }
}

const PROJECT = 'demo-stepup';
const AUTH = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const FN = `http://${FN_HOST}/${PROJECT}/asia-south1`;
const DEMO_PASSWORD = process.env.DEMO_PASSWORD || 'Demo@12345';
const PRESENTER_EMAIL = (process.env.PRESENTER_EMAIL || '').trim().toLowerCase();
const PRESENTER_PASSWORD = process.env.PRESENTER_PASSWORD || '';
const PRESENTER_NAME = process.env.PRESENTER_NAME || 'Disha';
if (!/^[^@\s]+@thapar\.edu$/.test(PRESENTER_EMAIL) || !PRESENTER_PASSWORD) {
  console.error('set PRESENTER_EMAIL (exact @thapar.edu) and PRESENTER_PASSWORD in the environment');
  process.exit(2);
}

const admin = require(require.resolve('firebase-admin', { paths: [path.join(__dirname, '..', 'functions')] }));
admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function authPost(p, body) {
  const res = await fetch(`http://${AUTH}/identitytoolkit.googleapis.com/v1/${p}?key=fake-api-key`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { status: res.status, json: await res.json() };
}

/** ID token for [uid] through a custom token (no password is used to authenticate the seed). */
async function tokenFor(uid) {
  const custom = await admin.auth().createCustomToken(uid);
  const r = await authPost('accounts:signInWithCustomToken', { token: custom, returnSecureToken: true });
  if (r.status !== 200) throw new Error(`custom token sign-in failed for ${uid}: ${JSON.stringify(r.json)}`);
  return r.json.idToken;
}

async function call(name, data, idToken) {
  const res = await fetch(`${FN}/${name}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${idToken}` },
    body: JSON.stringify({ data }),
  });
  const json = await res.json();
  if (json.error) {
    const reason = json.error.details && json.error.details.reason;
    const e = new Error(`${name}: ${json.error.status}${reason ? ' ' + reason : ''} ${json.error.message || ''}`);
    e.reason = reason;
    throw e;
  }
  return json.result;
}

async function ensureUser(email, password, displayName) {
  try {
    const u = await admin.auth().getUserByEmail(email);
    await admin.auth().updateUser(u.uid, { password, emailVerified: true, displayName });
    return u.uid;
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    const u = await admin.auth().createUser({ email, password, displayName, emailVerified: true });
    return u.uid;
  }
}

function syntheticBucket(startMs, raw) {
  const base = Math.floor(raw / 5);
  const hops = [0, 1, 2, 3, 4].map((i) => ({ label: 'WALK', imuSteps: i === 4 ? raw - 4 * base : base }));
  return { startMs, bootCount: 1, rawDelta: raw, credited: raw, state: 'VERIFIED', reason: null, walkFraction: 1.0, evidenceMode: 'E1', carryMode: 'HAND', hops };
}

const IST_MS = 19_800_000;
const DAY_MS = 86_400_000;
const todayMidnightIst = () => Math.floor((Date.now() + IST_MS) / DAY_MS) * DAY_MS - IST_MS;

/** SYNTHETIC steps: `count` consecutive 10 s buckets of `raw` steps ending at `endMs` (<= 72 h old). */
async function sendSyntheticSteps(token, deviceId, count, raw, endMs) {
  const end = Math.floor(endMs / 10_000) * 10_000;
  let accepted = 0;
  for (let from = 0; from < count; from += 100) {
    const n = Math.min(100, count - from);
    const buckets = [];
    for (let i = from; i < from + n; i++) buckets.push(syntheticBucket(end - (count - i) * 10_000, raw));
    const r = await call('syncStepBuckets', { deviceId, buckets }, token);
    accepted += r.accepted;
  }
  return accepted;
}

async function waitFor(fn, what, timeoutMs = 90_000) {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    const v = await fn();
    if (v) return v;
    await sleep(1000);
  }
  throw new Error(`timed out waiting for ${what}`);
}

const PEOPLE = [
  // email, name, hostel, [raw steps per bucket, bucket count] for day 0 (today), 1, 2  — SYNTHETIC
  { email: 'aarav.sample@thapar.edu', name: 'Aarav (sample)', hostel: 'agira', days: [[34, 295], [34, 295], [30, 280]] },
  { email: 'riya.sample@thapar.edu', name: 'Riya (sample)', hostel: 'ira', days: [[30, 240], [32, 260], [28, 200]] },
  { email: 'kabir.sample@thapar.edu', name: 'Kabir (sample)', hostel: 'tejas', days: [[28, 180], [30, 200], [26, 150]] },
  { email: 'meera.sample@thapar.edu', name: 'Meera (sample)', hostel: 'vahni', days: [[32, 260], [34, 295], [32, 270]] },
  { email: 'demo.student@thapar.edu', name: 'Demo Student (sample)', hostel: 'vyom', days: [[34, 295], [34, 295], [34, 295]] },
];

async function onboard(uid, name, hostelId, bio) {
  const token = await tokenFor(uid);
  await call('createProfile', {
    displayName: name, hostelId, fitnessLevel: 'INTERMEDIATE', sportsInterests: ['Walking', 'Running'],
    preferredActivity: 'Walking', preferredTime: 'MORNING', buddyType: 'BOTH', bio,
  }, token);
  return token;
}

async function main() {
  console.log('== accounts');
  const presenterUid = await ensureUser(PRESENTER_EMAIL, PRESENTER_PASSWORD, PRESENTER_NAME);
  const adminUid = await ensureUser('demo.admin@thapar.edu', DEMO_PASSWORD, 'Demo Admin');
  const uids = {};
  for (const p of PEOPLE) uids[p.email] = await ensureUser(p.email, DEMO_PASSWORD, p.name);

  console.log('== onboarding (real createProfile)');
  const presenterToken = await onboard(presenterUid, PRESENTER_NAME, 'agira', 'Project lead - live demo account (real steps).');
  const adminToken0 = await onboard(adminUid, 'Demo Admin', 'agira', 'Demo admin account.');
  void adminToken0;
  const tokens = {};
  for (const p of PEOPLE) tokens[p.email] = await onboard(uids[p.email], p.name, p.hostel, 'SAMPLE account with synthetic demo data.');

  console.log('== admin role');
  execFileSync(process.execPath, [path.join(__dirname, 'grant-admin.js'), 'demo.admin@thapar.edu'], { stdio: 'inherit', env: process.env });
  const adminToken = await tokenFor(adminUid); // fresh token carries the admin claim

  console.log('== SYNTHETIC step history for the sample students (3 days)');
  const mid = todayMidnightIst();
  for (const p of PEOPLE) {
    const token = tokens[p.email];
    const deviceId = randomUUID();
    await call('registerDevice', { deviceId, model: 'Demo seed (synthetic)', appVersion: 'demo' }, token);
    for (let d = 0; d < 3; d++) {
      const [raw, count] = p.days[d];
      const endMs = d === 0 ? Date.now() - 9 * 60_000 : mid - d * DAY_MS + 18 * 3_600_000;
      const accepted = await sendSyntheticSteps(token, deviceId, count, raw, endMs);
      console.log(`  ${p.name} day -${d}: ${accepted}/${count} buckets accepted (~${raw * count} steps)`);
    }
  }

  console.log('== buddies (presenter gets one pending request and one connection)');
  await call('sendBuddyRequest', { toUid: presenterUid, message: 'Walk together after class?' }, tokens['riya.sample@thapar.edu']);
  const aaravReq = await call('sendBuddyRequest', { toUid: presenterUid, message: 'Morning walks?' }, tokens['aarav.sample@thapar.edu']);
  await call('respondBuddyRequest', { requestId: aaravReq.requestId, accept: true }, presenterToken);

  console.log('== challenges (created by the admin through adminCreateChallenge)');
  const week = await call('adminCreateChallenge', {
    type: 'CAMPUS', metric: 'TOTAL_STEPS', windowMode: 'FIXED', target: 50000, title: 'Campus Step Week',
    description: 'Whole campus, verified steps only.', startAt: mid, endAt: mid + 7 * DAY_MS, rewardPoints: 50,
  }, adminToken);
  await call('adminCreateChallenge', {
    type: 'INDIVIDUAL', metric: 'TOTAL_STEPS', windowMode: 'ROLLING', durationDays: 7, target: 20000, title: '20,000 Steps in a Week',
    description: 'Walk 20,000 verified steps within 7 days of joining.', rewardPoints: 30,
  }, adminToken);
  for (const p of PEOPLE) await call('joinChallenge', { challengeId: week.challengeId }, tokens[p.email]);

  console.log('== points + one active bet (points are only earned by reaching the daily goal)');
  for (const email of ['aarav.sample@thapar.edu', 'demo.student@thapar.edu']) {
    await waitFor(async () => ((await db.collection('users').doc(uids[email]).get()).data() || {}).pointsBalance >= 10, `points for ${email}`);
  }
  // bets are only allowed between active buddies
  const dsReq = await call('sendBuddyRequest', { toUid: uids['aarav.sample@thapar.edu'], message: 'Friendly bet?' }, tokens['demo.student@thapar.edu']);
  await call('respondBuddyRequest', { requestId: dsReq.requestId, accept: true }, tokens['aarav.sample@thapar.edu']);
  const bet = await call('createStepBet', { opponentUid: uids['aarav.sample@thapar.edu'], targetSteps: 8000, durationDays: 1, stakePoints: 10, requestId: `demo-${Date.now()}` }, tokens['demo.student@thapar.edu']);
  await call('respondStepBet', { betId: bet.betId, accept: true }, tokens['aarav.sample@thapar.edu']);

  console.log('\nDONE. Accounts:');
  console.log(`  presenter : ${PRESENTER_EMAIL} (your password; real steps only)`);
  console.log(`  admin     : demo.admin@thapar.edu  / ${DEMO_PASSWORD}`);
  console.log(`  pre-loaded: demo.student@thapar.edu / ${DEMO_PASSWORD}   (points + an active bet, SYNTHETIC history)`);
  console.log('  samples   : aarav|riya|kabir|meera.sample@thapar.edu / same demo password (SYNTHETIC history)');
}

main().then(() => process.exit(0)).catch((e) => {
  console.error('\nSEED FAILED:', e.message || e);
  process.exit(1);
});
