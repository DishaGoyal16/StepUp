# IMPLEMENTATION_PROGRESS.md

Authoritative status. A line is only "done" when code exists **and** the stated check was actually run.

## Phase 0 — Inspection & planning (done, 2026-11-13)
Findings:
* No Flutter app, no `pubspec.yaml`, no Firebase backend, no `firestore.rules`, no Cloud Functions existed in `Desktop\steps`.
* Existing work: Kotlin sensor prototype `StepUp_Genuine_Step_Detection_v2` (pure-JVM `core` + Android `app`), 117 JVM tests green,
  spec in `DOCS/StepUp_AntiFraud_Architecture_v2.md`. Measured behaviour: see `GENUINE_STEP_ENGINE.md`.
* Toolchain here: Flutter 3.47/Dart 3.13, Node 24, JDK 17, Android SDK; Firebase CLI **not** installed (use local devDependency `firebase-tools`);
  network available; no Firebase project/credentials ⇒ emulator-based verification only.
* Flutter template uses the same AGP 9.1 / Kotlin 2.4 / Gradle 9.3 as the prototype ⇒ the Kotlin core can be included as a Gradle module.
Plan: contracts first (`DATABASE_SCHEMA.md`, `CLAUDE.md`), then backend ‖ Android bridge ‖ Flutter foundation in parallel, then feature waves, then integration.

| Phase | Scope | Status | Verified by |
|---|---|---|---|
| 0 | Inspect & plan | done | this file |
| 1 | Architecture, theme, nav, auth | implemented | `flutter analyze` clean; `flutter test` 896/896 (fakes). Real Auth only via emulator e2e (blocking fn + callables); not on device |
| 2 | Onboarding & hostel registration | implemented | widget/unit tests (18-hostel seed, domain check, flow); backend `createProfile` emulator tests |
| 3 | Genuine-step engine integration & verified storage | implemented (native + Dart + server) | engine+bridge 164/164 (re-run by me); server validator 148 unit + callable tests; **NOT run on a phone** |
| 4 | Home dashboard & step history | implemented | widget tests with fake engine/summaries; not on device |
| 5 | Buddy finder & requests | implemented | 108 UI tests (fakes) + 231 backend callable tests incl. buddy flows |
| 6 | Challenges (4 types) | implemented | 113 UI tests (fakes) + backend join/leave/finalize/reward tests |
| 7 | Step bets & virtual points | implemented | 113 UI tests (fakes) + backend lifecycle/payout/duplicate/expiry tests |
| 8 | Leaderboards | implemented | 60 UI tests (fakes) + backend aggregation tests |
| 9 | Achievements, notifications, profile | implemented | 98 UI tests (fakes) + backend; FCM push NOT tested (emulator skips) |
| 10 | Admin panel & backend security | implemented | 129 UI tests (fakes) + 59 rules tests + admin callable tests |
| 11 | Integration, tests, APK, zip | done except the items under "NOT verified" | all suites re-run by me (below); on-device E2E run against emulators on the realme phone: all 5 files pass with the final app code (B-E in one sequence, A in a later run because of USB drops); debug APK rebuilt; zip re-created. Steps in these tests are SYNTHETIC; no real walk was done |

## Log
(append dated entries below)

### 2026-11-13 — Android bridge (Phase 3, native half)
* Engine copied to `android/stepup_core` unchanged + 29 new bridge tests (`StepSummaryAggregator`, `SyncExportMapper`, `SyncLedger`); 146/146 pass (re-run independently).
* Foreground service (`health`), boot receiver, `StepEnginePlugin` (MethodChannel + EventChannel) implemented per `DATABASE_SCHEMA.md`.
* Contract additions: bucket items carry `lateRawAdded/lateCreditedAdded` (late-event re-send); `startTracking` may return `START_FAILED`.
* Known risks recorded by the engineer: `hops.tsv` is append-only and loaded at startup (needs pruning > ~48 h before shipping); BootReceiver / Android 12+ background FGS start untested; no on-device test yet; compileSdk raised to 37 (permission_handler_android).

### 2026-11-13 — Flutter phases 1-10 UI landed; verified together by me
* `flutter analyze` (whole project): **No issues found**. `flutter test` (whole project): **896 passed, 0 failed** (exit 0).
* Delivered (each by its own engineer, tested with FAKES only): foundation/auth/onboarding/home/step sync (Phases 1-4), buddy finder (5, 108 tests), challenges (6, 113), step bets & points ledger (7, 113), leaderboards (8, 60), notifications/profile/settings/achievements (9, 98), admin panel UI (10, 129).
* Android: `bindUser` per-user ledger binding + hop pruning; engine tests 164 reported (146 re-run by me earlier).
* NOT yet verified: any Firestore read/query against the emulators (rules + indexes), any callable against the real functions, the Flutter app on the phone, the foreground service on hardware. Backend report pending.
* Contract notes folded into DATABASE_SCHEMA.md: `bindUser`, `createStepBet.requestId/duplicate`, late-bucket fields.

### FINAL STATUS 2026-11-13 (independently re-run by the coordinator)
| Suite | Result |
|---|---|
| `flutter analyze` (whole app) | No issues found |
| `flutter test` (whole app) | 896 passed, 0 failed |
| `:stepup_core:test` (engine + bridge) | 164 passed, 0 failed |
| backend `npm run build` / `npm test` | OK / 148 passed |
| backend `npm run test:rules` | 59 passed |
| backend `npm run test:emulator` (single invocation) | 231 passed |
| backend `npm run test:functions-e2e` | 2 passed |
| `flutter build apk --debug` | built (162 MB) |
| zip `StepUp_Complete_Flutter_App.zip` | 420 files, 0.9 MB; extracted copy resolves packages and passes `flutter analyze` |

### 2026-11-13 (evening) - on-device end-to-end against the emulators (realme RMX3990, serial dbc4b60)
Run by me from `integration_test/` (written by the E2E agent, which stopped without a report; I re-ran everything myself). Emulator project `demo-stepup`, no real Firebase.
| Test file | Result | Notes |
|---|---|---|
| e2e_a (register -> verify -> onboarding -> Home -> tracking on) | **passed** (final run 20:57, with `adb` proof: `SensorWitnessService` running as a foreground service + notification posted) | needs a person to tap **Allow** on the 2 permission dialogs: this phone refuses `adb pm grant`. 3 earlier runs failed at this step with the same symptom; in the one that was probed both permissions were `granted=false` and nobody had tapped (the other two were not probed). My helper wrongly reported "granted"; fixed to verify. |
| e2e_b (SYNTHETIC buckets -> real `syncStepBuckets`) | passed | synthetic, not a real walk |
| e2e_c (second user, ledger re-bound) | passed | |
| e2e_d (admin vs student) | passed | |
| e2e_e (buddies, challenge, bets) | passed | points earned via SYNTHETIC buckets |
Real defect found and fixed: admin-created INDIVIDUAL challenges never appeared for students (`lib/data/challenges/firestore_challenge_reader.dart` listed only `isTemplate==true`); test and fake updated.
Test-harness issues fixed (not app bugs): reinstall creates a new non-reward device; empty first listener event; verification-mail timing; racy `BindResult.changed` assertion.
Re-run after the fix: `flutter analyze` No issues; `flutter test` **907 passed**. Backend/engine code was not changed in this stage.

NOT verified: a real 50-step walk with this app; shake/vehicle/bounce with this app; boot restore and killing the app mid-walk on hardware; step accuracy beyond `GENUINE_STEP_ENGINE.md`;
real Firebase project (deploy, FCM, Identity Platform blocking); Firestore composite-index coverage (the emulator does not enforce indexes); visual polish on a device; Google sign-in;
the on-device tests were not all run in ONE unbroken sequence on the final build (A passed in a separate later run; lib code unchanged between them).
