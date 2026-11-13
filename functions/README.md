# StepUp backend (`functions/`)

Firebase Cloud Functions v2 (TypeScript, region `asia-south1`), Firestore rules, Storage rules, indexes, emulator setup and tests.
The data/API contract is `../DATABASE_SCHEMA.md` (see its last section for the implementation notes and contract additions).

```
functions/src/
  config.ts                 constants, defaults (adminSettings/global), collection names
  index.ts                  exports every callable / trigger / scheduled function / Auth blocking function
  lib/                      auth (requireEligibleUser, requireAdmin), validate, errors, time (Asia/Kolkata), points (ledger tx),
                            rewards (reward + badges), settings, clock (injectable), callable wrapper
  steps/                    validateBatch.ts (pure port of BucketVerifier.kt + hard limits), syncStepBuckets.ts, summaries.ts
  profile/ buddies/ challenges/ bets/ leaderboards/ notifications/ admin/ triggers/ seed/
functions/test/unit/        fast jest tests (no emulator)
functions/test/emulator/    callables/ (handler logic against Firestore+Auth emulators), rules/ (Firestore + Storage rules)
../firestore.rules ../storage.rules ../firestore.indexes.json ../firebase.json ../.firebaserc
../scripts/grant-admin.js ../scripts/seed.js
```

## Requirements
* Node 20+ (tests run fine on Node 24; `engines` is 20 for deployment), npm.
* **Java 17+** for the Firestore emulator. `firebase-tools` is a **local** devDependency pinned to `^14.27` because firebase-tools 15 requires Java 21.
* Windows quirk (seen on this machine): the emulator JVM fails with `failed to open a new selector` unless Java's Unix-domain-socket temp dir is short.
  Set once per shell:
  * PowerShell: `$env:JAVA_TOOL_OPTIONS = "-Djdk.net.unixdomain.tmpdir=C:/jt"` (create `C:\jt` first), optionally `$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot"`
  * bash: `export JAVA_TOOL_OPTIONS="-Djdk.net.unixdomain.tmpdir=C:/jt"`
  (The repo's `../StepUp_Genuine_Step_Detection_v2/scripts/dev-env.ps1` sets exactly this.)

## Commands (run inside `functions/`)
```powershell
npm ci                    # or npm install
npm run build             # tsc -> lib/
npm test                  # fast jest logic tests (no emulator): validateBatch golden vectors, time, domain, bets, challenges, leaderboards...
npm run test:emulator     # emulators:exec (firestore+auth) -> callable end-to-end tests in test/emulator/callables
npm run test:rules        # emulators:exec (firestore+storage) -> Firestore + Storage rules tests in test/emulator/rules
npm run test:all          # all of the above
npm run emulators         # start auth 9099, functions 5001, firestore 8080, storage 9199 (UI disabled) for the Flutter app
npm run seed              # seed an already running emulator (needs `npm run build` first)
```
`test:emulator` / `test:rules` already wrap their jest run in `npx firebase emulators:exec --project demo-stepup ...`, so do **not** nest them
inside another `emulators:exec`. If you prefer to run your own emulators, use `npm run test:emulator:inner` / `npm run test:rules:inner`
with `FIRESTORE_EMULATOR_HOST`/`FIREBASE_AUTH_EMULATOR_HOST` set.

The callable tests call the exported **handler logic** (`handleXxx(req)`) - exactly what `onCall` wraps in `src/lib/callable.ts` - against the real
Firestore/Auth emulators, with an injectable clock (`src/lib/clock.ts`) so expiry, settlement and bucket-age rules are deterministic.
Scheduled/trigger bodies are exported too (`runFinalizeChallenges`, `runSettleStepBets`, `runChallengeReminders`, `runRefreshWeeklySteps`,
`processDailySummary`) and are invoked directly by the tests; the Cloud Functions trigger/scheduler wiring itself is only compiled
(`npm run build`), not exercised by the emulator tests.

## Local development with the Flutter app
```powershell
cd functions; npm run build
npx firebase emulators:start --project demo-stepup      # from functions/ (firebase.json is in the parent folder and is found automatically)
node ../scripts/seed.js                                  # hostels, 6 individual challenge templates, badges, adminSettings/global
node ../scripts/grant-admin.js someone@thapar.edu        # needs FIREBASE_AUTH_EMULATOR_HOST / FIRESTORE_EMULATOR_HOST set; user must exist
```
The app connects with `USE_FIREBASE_EMULATOR=true` (see `../CLAUDE.md`). The project id `demo-stepup` needs no credentials.
In production run `adminSeedDefaults` (admin callable) or `scripts/seed.js --project <id>` once, then `scripts/grant-admin.js <email> --project <id>`
with Application Default Credentials (`gcloud auth application-default login`). No keys or secrets are stored in this repository.

## Deploy checklist (NOT done here; no real Firebase project is bundled)
1. `firebase use <project>`; enable Auth (email/password or email link), Firestore, Storage, Cloud Functions (Blaze plan), and **Identity Platform** (required for `beforeUserCreated` blocking functions).
2. `npm run build && firebase deploy --only firestore:rules,firestore:indexes,storage,functions`.
3. Seed + grant admin as above.

## Behaviour summary
* Every callable: `requireEligibleUser` (auth, `token.email` ends with exactly `@thapar.edu` case-insensitively, `email_verified`, profile exists and `status == ACTIVE`; `createProfile` skips only the profile check). Admin callables: `requireAdmin` (`token.admin === true`) and write an `adminAudit` entry.
* Errors are `HttpsError` with a stable `details.reason`.
* Virtual points: balance changes only inside Firestore transactions that also `create` a ledger doc with a deterministic id; bets reserve on create/accept, release on decline/cancel/expire/refund, winner receives both stakes. No currency anywhere.
* Server step validation never raises a client claim: `serverCredited = min(clientCredited, recomputed)`, hard limits 35/bucket, 6,300/rolling 30 min, 20,000 reward steps/day, 72 h bucket age, 120 s future tolerance. See `DATABASE_SCHEMA.md` for late-event updates.
* Not implemented / limits: Play Integrity / signed batches (L6), the cross-account fleet analysis and the soft anomaly features of L7.3/7.4 (only the listed riskEvents kinds are produced), real FCM delivery is untested (push is skipped in the emulator), blocking-function behaviour under the Auth emulator is only unit tested.
