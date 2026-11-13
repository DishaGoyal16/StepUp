# HANDOFF_FOR_NEXT_AGENT.md — StepUp (Thapar campus fitness app)

Written 2026-11-13 for another LLM agent (or developer) who must continue this project. Read this file first, then `CLAUDE.md`
(project guide), `DATABASE_SCHEMA.md` (binding contract for data/API/channel), `IMPLEMENTATION_PROGRESS.md` (authoritative status log),
`KNOWN_LIMITATIONS.md`, `TESTING_GUIDE.md`, `GENUINE_STEP_ENGINE.md`.

Everything below is stated as it was actually verified. Where something was NOT run, it says so. Do not upgrade a claim to "works"
unless you run the check yourself.

---------------------------------------------------------------------------------------------------------------------------------

## 0. TL;DR — where the project stands

| Question | Honest answer |
|---|---|
| Is there a complete Flutter Android app? | Yes: all screens/features below are implemented (192 Dart files in `lib/`, 53 test files), analyzer clean, 907 Flutter tests pass. |
| Is a real backend connected? | **No.** There is no Firebase project and no credentials. The backend (Cloud Functions, Firestore rules, indexes, Storage rules) is implemented and was verified only against the **local Firebase Emulator Suite** (project id `demo-stepup`). |
| Does it run on a phone? | Yes, on one phone (realme RMX3990, Android 16 / SDK 36) against the emulators. 5 on-device test files pass (register/verify/onboard/tracking service, synthetic step sync, second account, admin, buddies/challenge/bets). |
| Is step counting proven on a real walk with this app? | **No.** Every step in the on-device tests is a hand-built ("SYNTHETIC") bucket sent through the real server path. Nobody has walked with the Flutter app. Accuracy numbers come only from the earlier Kotlin prototype (see §3). |
| Is it "fully functional"? | **Not yet.** What is missing is listed in §9 (real Firebase project, real-walk validation, release build, FCM/Google sign-in verification, etc.). |

Deliverables on the user's Desktop (`<Desktop>\steps\`): `StepUp_Complete_Flutter_App.zip`,
`StepUp_Complete_Flutter_App-debug.apk` (NO backend configured: opens to a "Backend not configured" screen — by design, it never fakes a backend).

---------------------------------------------------------------------------------------------------------------------------------

## 1. What the user asked for (the brief, condensed)

"STEPUP — COMPLETE THAPAR CAMPUS FITNESS APPLICATION": a complete working Flutter Android app for Thapar Institute students, Firebase
backend, reusing the existing tested genuine-step engine through a clean platform-channel architecture (never rewrite the algorithm).

Hard requirements (all still binding):
* Only **verified genuine steps** may feed leaderboards, challenges, buddy competitions, step bets, rewards, hostel competitions.
* **`@thapar.edu` only** for login/registration, enforced on frontend AND backend, **email verification required**.
* **18 hostels** exactly as seeded (11 general + 7 girls'), admin-configurable, blocks never merged.
* Team credits shown on Home: **Disha = project lead (most prominent)**, then Raghav, Bhavya, Sanveer, Anvi, **Kashish with lower visual
  priority**. These names are display text only and carry **no admin privileges**; admin is role-based and enforced by the backend.
* Features: home dashboard (progress ring, streak, weekly bars, quick actions, campus activity), buddy finder (filters, requests, buddy
  challenges), challenges (individual, buddy, inter-hostel, campus), **step bets with VIRTUAL POINTS ONLY** (atomic transactions, no
  real money), leaderboards (podium, my-rank row, hostel average-per-participant), badges/rewards, profile/settings, FCM + in-app
  notifications, admin panel.
* Light fitness theme: Primary `#35A86B`, Secondary `#8BD6A8`, Background `#F7FAF7`, Surface `#FFFFFF`, Text `#18352A`; bottom nav
  Home · Buddies · Challenges · Leaderboard · Profile.
* If Firebase credentials are missing: implement the integration, document setup, **do not pretend the backend is connected**.
* No mock data presented as proof; "Do not claim completion until the features have been implemented and tested."
* Never claim perfect accuracy or reliable fake-step detection.

User working preferences observed: wants fast progress, wants honest reporting, tolerates but dislikes repeated reconnects; phone work must be
limited to package `edu.thapar.stepup` (no phone settings changes; the user explicitly authorised installs/launches of the app on the phone).

---------------------------------------------------------------------------------------------------------------------------------

## 2. History in two parts

### Part A — evaluate and improve the Kotlin genuine-step prototype (before the Flutter work)
Prototype folder (NOT in the zip, left in place on the Desktop): `<Desktop>\steps\StepUp_Genuine_Step_Detection_v2`
(pure-JVM `core` + Android `app`; spec `..\DOCS\StepUp_AntiFraud_Architecture_v2.md`). The user tested on a realme RMX3990 and pasted CSV
exports (hops/diagnostics/tests/counters/buckets/sensors). I analysed them, found the first test procedure was flawed, ran replays of the
recordings, and improved the engine with no further user testing. Findings and changes:
* Main causes of lost genuine steps: the **periodicity gate**, the **heel-strike asymmetry gate**, and counter-cadence artefacts at walk start/end.
* Threshold/logic changes in `HopClassifier.kt` / `ClassifierConfig.kt` (now part of the engine copied into the Flutter project):
  `asymGateMin` 0.10; `r0Floor` 0.20 with `weakPeriodicityExtraMargin` 1.0 (weak-periodicity path, with a vehicle-spectrum guard);
  the cadence-disagreement rule made **one-sided** (only penalise when the counter cadence is HIGHER than the body cadence;
  `lowCounterDisagreePoints` 0, `highCounterDisagreePoints` 2); new **H3 extreme-shake veto** (dynRms ≥ 8 m/s² and churn ≥ 150 deg/s).
* `RawRecording.read` now drops an unterminated/implausible last line (a truncated recording produced 0 hops → UNWITNESSED); regression test added.
* New prototype tests: `WeakPeriodicityTest`, `ShakeVetoTest`, `GenuineWalkRetentionTest`, `RawRecordingRobustnessTest`.
* Further threshold loosening gave no safe gain, so it was left.

### Part B — the Flutter app (this repository)
Phase plan 0–11 (see `IMPLEMENTATION_PROGRESS.md`). Work was done by parallel engineers (backend / Android bridge / Flutter features) against
contracts written first (`DATABASE_SCHEMA.md`, `CLAUDE.md`), then integrated and re-verified by the coordinator. A final E2E agent wrote
`integration_test/` and stopped without reporting; the coordinator re-ran everything itself.

---------------------------------------------------------------------------------------------------------------------------------

## 3. The genuine-step engine (do NOT rewrite it)

Source of truth: `GENUINE_STEP_ENGINE.md`. Summary:
1. `TYPE_STEP_COUNTER` deltas are bucketed by **sensor timestamp** into 10 s buckets (first event after (re)registration/reboot is baseline only).
2. Accelerometer (+gyro) → 25 Hz → 4 s windows / 2 s hops → explainable classifier (WALK, RUN, SHAKE, VEHICLE, STILL, UNKNOWN) with hard rules
   H1 still, H2 vehicle (Activity Recognition, downgrade-only), H3 extreme-shake veto.
3. Bucket verifier: UNWITNESSED if IMU hop coverage < 0.8; REJECTED if < 50 % WALK/RUN hops; else `credited = min(raw, floor(1.15 × Σ IMU gait steps))`.
4. Ledgers: raw/display vs verified; states PENDING, VERIFIED, PARTIAL, REJECTED, UNWITNESSED, GAP (GAP = service not listening, display-only).
   Settlement ≈ 90–100 s, so verified numbers appear ~2 minutes after walking.

Measured (one phone, one person; NOT a validated accuracy): hand-held walks with ground truth credited 50/52 and 54/59 counter steps;
pooled over 5 walking recordings 237/350 (68 %) — steps taken while handling the phone are deliberately not credited; fast phone shaking
~7 runs: 0 of 562 counter steps credited; sitting still: nothing counted. **Not tested on hardware:** slow rhythmic shake, leg bounce,
pendulum, vehicle, cycling, bag, stairs, running, other phones/people. Server re-validation can only DOWNGRADE; it cannot re-observe sensors.
There is no device attestation / Play Integrity (rooted/instrumented phones can fabricate evidence).

---------------------------------------------------------------------------------------------------------------------------------

## 4. Repository layout

```
StepUp_Complete_Flutter_App/
  lib/            192 Dart files
    core/         config (AppConfig, dart-define reader), errors, router (go_router), theme, utils, widgets
    domain/       pure Dart models/rules (no Flutter, no Firebase)
    data/         admin, auth, bets, buddies, challenges, firestore, functions (callables client), leaderboard, notifications,
                  notifications_center, profile, profile_extras, steps (channel, binding, tracking, sync) — all behind interfaces, plus Fakes
    features/     admin auth bets buddies challenges home leaderboard notifications onboarding profile
    app_dependencies.dart  (single composition root; fields incl. stepEngine, stepBinding, stepTracking, stepSync, session, callables, ...)
    app.dart  main.dart
  test/           53 files (fakes only; no Firebase)
  integration_test/   on-device E2E (e2e_a..e), support/{emulator.dart,harness.dart}, tools/{run-e2e.ps1,reset-and-seed.ps1,adb-watcher.ps1}, README.md
  android/
    stepup_core/  Gradle module = the copied Kotlin engine (57 Kotlin files) + bridge classes
                  (StepSummaryAggregator, SyncExportMapper, SyncLedger, UserBinding) + tests (164 JVM tests)
    app/          Flutter host; package edu.thapar.stepup.steps: StepEnginePlugin (MethodChannel/EventChannel), WitnessEngine,
                  SensorWitnessService (foreground, type "health"), WitnessRuntime, ArClient, BootReceiver, Prefs, SensorProbe
                  app/src/debug/AndroidManifest.xml allows cleartext HTTP (emulators are plain HTTP) — debug only
  functions/      Cloud Functions v2 (TypeScript, region asia-south1): 39 src files, 18 test files
  firestore.rules  storage.rules  firestore.indexes.json (19 composite indexes)  firebase.json  .firebaserc
  scripts/        seed.js (hostels, 6 challenge templates, badges, settings), grant-admin.js
  docs: CLAUDE.md README.md DATABASE_SCHEMA.md FIREBASE_SETUP.md GENUINE_STEP_ENGINE.md IMPLEMENTATION_PROGRESS.md KNOWN_LIMITATIONS.md TESTING_GUIDE.md HANDOFF_FOR_NEXT_AGENT.md
```
Layering: `lib/data` (Firebase + channel behind interfaces) → `lib/domain` → `lib/features/*`. UI never touches Firebase directly. Each feature
exports `<feature>Providers(AppDependencies)` and `<feature>Routes` (extension-point pattern). Stack: Flutter 3.47 / Dart 3.13, Material 3,
`provider`, `go_router`, `permission_handler`, `image_picker`, `shared_preferences`, firebase_core/auth/firestore/functions/storage/messaging, google_sign_in.
Android: Kotlin 2.4, AGP 9.1, Gradle 9.3, JDK 17, minSdk 26, compileSdk = max(flutter's, 37) (permission_handler_android needs 37).

---------------------------------------------------------------------------------------------------------------------------------

## 5. Architecture and the decisions behind it

* **Clients never write Firestore directly** (except marking their own notifications read). All mutations are callables using the Admin SDK with
  deterministic document IDs and transactions. Points, steps, results and roles are server-only.
* **Step pipeline:** Flutter `StepEngineChannel` (MethodChannel `edu.thapar.stepup/engine`, EventChannel `edu.thapar.stepup/engine_events`) →
  Kotlin service → `WitnessPipeline` → settled buckets → Dart `StepSyncService` reads `getBucketsForSync`, calls `syncStepBuckets`, and **only then**
  `ackBuckets` (at-least-once + deterministic server IDs ⇒ no double counting). Late step-counter events on settled buckets are re-sent with
  `lateRawAdded/lateCreditedAdded`.
* **Server can only downgrade:** `serverCredited = min(clientCredited, recomputed)`. Hard limits: 35 steps/bucket, 6,300 per rolling 30 min,
  20,000 reward steps/day, bucket age ≤ 72 h, 120 s future tolerance. Port of the Kotlin verifier lives in `functions/src/steps/validateBatch.ts`
  (golden vectors V1–V9).
* **One reward device per account.** First registered device is the reward device; others store buckets with `rewardEligible:false`.
  Takeover only after `rewardDeviceTakeoverDays` (14, admin setting) unseen. Consequence: reinstall/new phone = no reward steps for up to 14 days
  (KNOWN_LIMITATIONS 11). Device id is a random per-install id.
* **Per-user ledger binding** (`bindUser {uid}` → `{bound, changed, sinceMs}`): the native ledger is install-wide; `UserBinding` persists
  `uid`+`sinceMs` so one account's steps never appear under another; consumers ignore buckets with `startMs < sinceMs`. Hop log is pruned (> ~48 h).
  `BindResult.changed` is not reliable as a "first bind" signal (repeat binds report false) and nothing in the app reads it.
* **Step bets:** virtual points only; stake reserved on create (challenger) / accept (opponent); released on decline/cancel/expire/refund;
  winner receives both stakes; `createStepBet` takes `requestId` for idempotency (`{betId, duplicate}`); ledger in `virtualPointsLedger`.
* **Time zone:** daily/weekly/monthly keys use `Asia/Kolkata` server-side; device clock does not matter.
* **Auth:** `@thapar.edu` enforced in Dart, in `beforeUserCreated` (blocking function), in every callable, and in Firestore rules. Admin =
  custom claim `admin:true` set only by `adminSetUserRole` or `scripts/grant-admin.js`. Accounts in `DELETION_REQUESTED` are refused by mutating
  callables with reason `ACCOUNT_DELETION_REQUESTED`.
* **Firebase config** comes only from `--dart-define` (`FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_PROJECT_ID`, `FIREBASE_MESSAGING_SENDER_ID`,
  optional `FIREBASE_STORAGE_BUCKET`; `USE_FIREBASE_EMULATOR=true` + `EMULATOR_HOST`, default `10.0.2.2`). Missing config ⇒ "Backend not configured" screen.

Backend surface (42 exports in `functions/src/index.ts`): callables — createProfile, updateProfile, registerDevice, syncStepBuckets, searchBuddies,
sendBuddyRequest, respondBuddyRequest, cancelBuddyRequest, removeBuddy, reportProfile, createBuddyChallenge, respondChallengeInvite, joinChallenge,
leaveChallenge, getChallengeLeaderboard, getLeaderboard, createStepBet, respondStepBet, cancelStepBet, markNotificationsRead, requestAccountDeletion,
admin* (Stats, ListStudents, SuspendUser, SetUserRole, UpsertHostel, SetHostelActive, CreateChallenge, CancelChallenge, UpsertBadge, SetSettings,
ListReports, ResolveReport, ListRiskEvents, ResolveRiskEvent, SeedDefaults); triggers/schedules — beforeUserCreated, onDailySummaryWritten,
finalizeChallenges, settleStepBets, challengeReminders, refreshWeeklySteps. Collections and fields: `DATABASE_SCHEMA.md` (hostels, users,
publicProfiles, users/{uid}/devices, stepBuckets, dailyStepSummaries, leaderboards(+entries), buddyRequests, buddyConnections, challenges,
challengeParticipants, challengeResults, stepBets, virtualPointsLedger, achievements, notifications, reports, riskEvents, adminSettings).

---------------------------------------------------------------------------------------------------------------------------------

## 6. What was built, by phase (all "implemented"; verification in §7)

1 architecture/theme/nav/auth · 2 onboarding & hostel registration (18 hostels grouped Hostels + Girls' hostels; draft kept across registration) ·
3 step engine integration + verified storage (native + Dart + server) · 4 Home dashboard + step history (progress ring, streak, weekly bars,
raw/verified/pending/rejected breakdown, quick actions, campus activity, team credits) · 5 buddy finder, requests, buddy challenges ·
6 challenges (4 types, join/leave, leaderboard, finalize + single reward) · 7 step bets & points ledger · 8 leaderboards (daily/weekly/monthly/
hostel/campus, podium, my rank, hostel average-per-participant) · 9 achievements, notifications (in-app + FCM plumbing), profile/settings ·
10 admin panel + security rules · 11 integration, tests, APK, zip.

---------------------------------------------------------------------------------------------------------------------------------

## 7. Verification actually performed (2026-11-13)

| Suite | Command | Result |
|---|---|---|
| Flutter static | `flutter analyze` | No issues found |
| Flutter tests | `flutter test` | **907 passed** (fakes; no Firebase) |
| Engine + bridge (JVM) | `cd android; .\gradlew.bat :stepup_core:test` | 164 passed (last run before the E2E stage; native code not changed after) |
| Backend unit | `cd functions; npm test` | 148 passed (re-run at the end) |
| Firestore/Storage rules | `npm run test:rules` | 59 passed (earlier run; backend unchanged since) |
| Callables on emulators | `npm run test:emulator` | 231 passed (earlier run; single invocation) |
| Functions e2e | `npm run test:functions-e2e` | 2 passed (earlier run) |
| On-device E2E | `integration_test/tools/run-e2e.ps1` on realme RMX3990 vs emulators | e2e_a, b, c, d, e all **passed** (B–E in one sequence; A in a later run because USB dropped; lib code identical) |
| APK / zip | `flutter build apk --debug`, manual zip | built; zip extract passes `pub get` + `analyze` |

On-device files: **a** gmail refused, register, server refuses profile before verification, verify via emulator oobCodes, onboarding with 18 live hostels,
Home + team credits, tracking on → `adb` shows `SensorWitnessService` as foreground service + notification, first sync, reward device;
**b** SYNTHETIC buckets through real `syncStepBuckets` (valid, duplicate, over-claim downgrade, shake rejection, Home number);
**c** sign out, register student2, ledger re-bound (`sinceMs` moved), nothing of student1 shown; **d** admin vs student access, admin creates a
challenge, audit entry; **e** buddies request/accept, individual challenge join, bet rejected with 0 points, bet create/accept with reserved points
(points earned via SYNTHETIC buckets).

### Defects found by the E2E stage and fixed
* **Real app bug:** admin-created INDIVIDUAL challenges were invisible to students (`firestore_challenge_reader.dart` listed only `isTemplate==true`). Fixed in
  the reader and fake; test updated.
* Test-harness issues (not app bugs): reinstall ⇒ new non-reward device (`Emu.promoteRewardDevice` simulates the 14-day takeover); first Firestore listener
  event can be empty right after a user switch (tests now wait for the live update); verification-mail timing race; racy `BindResult.changed` assertion;
  the adb helper reported "granted" when `pm grant` had actually been refused (now verifies).

### Agent-made app changes during the E2E stage (reviewed through the test suites, not line-by-line)
`lib/data/firebase_bootstrap.dart`, `lib/core/config/app_config.dart`, `lib/features/home/step_breakdown_card.dart` (narrow-screen layout),
`lib/data/steps/step_tracking_controller.dart` + `fake_step_engine_channel.dart`, `lib/features/auth/session_controller.dart`, with unit tests.

---------------------------------------------------------------------------------------------------------------------------------

## 8. What is NOT verified (be explicit about these)

* **Any real walk with the Flutter app**; shake/bounce/vehicle/pocket/bag/stairs with it; other phones. (All E2E steps are synthetic.)
* A **real Firebase project**: deploy, Identity Platform blocking function, FCM delivery, Google sign-in, real emails, Storage uploads for profile photos on a real bucket.
* **Firestore composite-index coverage** — the emulator does not enforce indexes. `searchBuddies` may need one; the `buddyType` filter does not match profiles stored as `BOTH`.
* Foreground service survival (OEM battery killers on realme), **boot restore** (`BootReceiver`), Android 12+ background foreground-service start rules,
  kill-app-mid-walk recovery — all untested on hardware.
* Visual polish on different screen sizes/OS versions; accessibility; localisation.
* Release build/signing/R8, Play Store policy declarations (foreground service type `health`, Activity Recognition).
* Account-deletion processing (admin-handled request only), push content/links.

---------------------------------------------------------------------------------------------------------------------------------

## 9. What is left to reach a fully functional app (suggested order)

1. **Real backend.** Create a Firebase project; enable Auth (email/password; Identity Platform/Blaze for the `beforeUserCreated` blocker), Firestore,
   Functions (region `asia-south1`), Storage, FCM. Follow `FIREBASE_SETUP.md`. Deploy rules, `firestore.indexes.json`, functions. Run `scripts/seed.js` against
   it (or `adminSeedDefaults`), then `scripts/grant-admin.js <email>` for the first admin. Build with the `--dart-define` values (no committed secrets).
   Check whether Android needs a `google-services.json` for FCM/Google sign-in in addition to the dart-define options.
2. **Index audit on the real project:** run each query (search buddies, challenges lists, leaderboards, notifications, ledger) and add any missing composite
   index; fix the `buddyType: BOTH` filter mismatch.
3. **Real-walk validation** (manual, with a person): 50 steps hand-held, 50 in pocket, 30 s hard shake, slow rhythmic shake seated, leg bounce seated, sit
   still, passenger in a vehicle, kill app mid-walk, reboot with tracking on, switch accounts. Record the numbers in `GENUINE_STEP_ENGINE.md`. Tune the
   engine only with recorded evidence; keep the 164 JVM tests green. Consider more phones and Play Integrity/attestation (v2 L6).
4. **Reliability on real devices:** battery-optimisation/OEM autostart guidance in-app, verify `BootReceiver` and Android 12+ FGS restrictions, make tracking
   restart after process death, verify the notification text "StepUp is counting verified steps".
5. **Reward device UX:** add a self-service "make this my reward device" flow (or admin action) so reinstall/new phone does not cost 14 days.
6. **FCM end-to-end:** token registration (`registerDevice` fcmToken), push on buddy request / challenge / bet events, notification tap routing.
7. **Google sign-in:** register OAuth client + SHA-1/SHA-256 and enable `AppConfig.googleSignInEnabled`; confirm it still enforces `@thapar.edu` (domain
   check on the resulting account, backend block).
8. **Release build:** signing config, R8/ProGuard keep rules for the plugin and Kotlin engine, remove debug cleartext, shrink (the debug APK is ~190 MB with
   all ABIs), Play Console declarations for the foreground service and Activity Recognition.
9. **Polish/QA:** screen-size sweep, dark-mode decision (spec says light by default), accessibility labels, error/empty/offline states on every screen,
   performance of leaderboards at campus scale, admin panel with real data volumes.
10. **Operational:** Cloud Scheduler/cost review, backups, monitoring of `riskEvents`, privacy policy/data deletion process for `requestAccountDeletion`.
11. **CI:** run analyze + all suites on every change; the on-device suite needs a human tap on the permission dialogs on realme phones (see §10).

---------------------------------------------------------------------------------------------------------------------------------

## 10. Environment and traps (Windows 11, PowerShell 5.1; Git Bash also present)

* Flutter: `C:\src\flutter\flutter\bin` (add to PATH). JDK 17 (Temurin). `ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk`.
  **Gradle/emulator socket workaround:** set `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:/jt` (create `C:\jt`). The project docs call
  `. ..\StepUp_Genuine_Step_Detection_v2\scripts\dev-env.ps1` which does this — **that script lives outside the zip**; recreate it if the prototype folder is absent.
* `firebase-tools` is pinned `^14` (v15 needs Java 21). Emulator project id `demo-stepup`. Ports: auth 9099, firestore 8080, functions 5001, storage 9199.
  Start: `cd functions; npm run build; npm run emulators`. The `test:*` npm scripts already wrap `firebase emulators:exec` — **never nest** them or run them while
  `npm run emulators` is running (port clash).
* Verification emails are not sent by the emulator: read `http://127.0.0.1:9099/emulator/v1/projects/demo-stepup/oobCodes` and open the `oobLink`.
* Physical phone → PC emulators needs `adb reverse tcp:9099 tcp:9099` (and 8080, 5001, 9199) and a build with
  `--dart-define=USE_FIREBASE_EMULATOR=true --dart-define=EMULATOR_HOST=127.0.0.1`. The reverse rules vanish when USB drops.
* `flutter test integration_test/...` **uninstalls the app at the end** and **overwrites `build/app/outputs/flutter-apk/app-debug.apk` with a test-harness build**;
  rebuild the real APK afterwards. Each file ⇒ a new install id ⇒ a new (non-reward) device.
* realme RMX3990: `adb shell pm grant` is refused (`GRANT_RUNTIME_PERMISSIONS`) unless the developer option "USB debugging (Security settings)" is on, and
  `pm clear` is refused. The package verifier sometimes rejects `flutter test`'s install (`INSTALL_FAILED_VERIFICATION_FAILURE`); `run-e2e.ps1` retries with
  `adb install -r`. A person must tap **Install** and **Allow** (physical activity, notifications). USB drops often; the `adb` server can hang — re-plug the cable.
* Never kill processes by name (a blanket kill was blocked once); only stop processes you started. Phone work is limited to package `edu.thapar.stepup`;
  do not change phone settings.
* Zip creation on PowerShell 5.1: `Compress-Archive` writes backslash entries; build the zip with `System.IO.Compression.ZipArchive` and forward slashes
  (exclude `build`, `.dart_tool`, `node_modules`, `.gradle`, `.idea`, `local.properties`, `functions/lib`, `*.log`).
* Streams: do not use `.first` on Firestore `snapshots()` streams in tests/code that must see fresh data — the first event may be empty.
* `/bets/ledger` must be declared before `/bets/:id` in the router. Test password constant `Passw0rd123` in `integration_test/support/emulator.dart` is test-only.
* Do not commit secrets (no `google-services.json`, keys, or passwords are in the repo; keep it that way).

---------------------------------------------------------------------------------------------------------------------------------

## 10b. Live-demo kit (added after the first version of this file)
For presenting to a professor with NO paid cloud: `DEMO_GUIDE.md`. Files: `firebase.demo.json` (emulators bound to 0.0.0.0), `scripts/demo-start-emulators.ps1`,
`scripts/demo-reset-and-seed.ps1` + `scripts/seed-demo.js` (presenter account + `demo.admin@` + `demo.student@` + four "(sample)" students with SYNTHETIC 3-day history,
buddies, a campus and an individual challenge, one active bet — all created through the real callables; the script refuses non-local emulators),
`scripts/demo-preflight.ps1` (read-only), `scripts/demo-verify-email.ps1`, `scripts/demo-build-apk.ps1 -HostIp 192.168.137.1` (APK for the PC's Windows-hotspot address).
Verified on this PC: seed completes (7 accounts, points awarded by the real daily-goal rule, bet active, presenter has 0 step records), and over the PC's LAN address
a password login, `getLeaderboard`, and the gmail-refusal all work. NOT verified: the phone reaching the PC over the hotspot (the USB link was down), the Windows
firewall rule, the hotspot itself, or a live real walk through the demo build.
Free-hosting options considered (answer given to the user): Firebase Spark cannot deploy Cloud Functions and (since 2026-02-03) Storage needs Blaze; alternatives are
Firebase free tier + free Node host (HTTP adapter for the existing `handleX` functions, GitHub Actions cron, no photo upload; Spark Firestore ≈ 20K writes/day),
Supabase free tier (full rewrite of backend + `lib/data`), or self-hosting.

---------------------------------------------------------------------------------------------------------------------------------

## 11. Ground rules for whoever continues

1. Keep the claims honest: update `IMPLEMENTATION_PROGRESS.md` only with checks you actually ran, with the real result.
2. Do not rewrite the step engine; extend it with tests. Keep it behind the channel. Do not weaken server-side validation.
3. Virtual points only — no real money, ever. Team names are display text, never privileges.
4. Don't fake a backend or ship mock data as proof. Fakes belong in tests only.
5. When something is flaky, find the cause (probe the real state) before changing the test; several "failures" here were test-harness problems, one was a real bug.
