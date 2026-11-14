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

## Hotspot recovery — 14 November 2026
- Restarted demo backend and installed existing hotspot APK on RMX3990.
- Added import/export persistence and `scripts/demo-save-data.ps1`; `.demo-data` ignored by git.
- Recreated local demo accounts because the previous emulator state was lost.
- Phone Wi-Fi was still on college subnet 172.16.145.x; direct request to 192.168.137.1 failed with No route to host. Awaiting phone joining laptop hotspot before Wi-Fi login can be verified.
- No real-walk accuracy result or production deployment claimed.

### Hotspot connection verified — 14 November 2026
Phone RMX3990 at 192.168.137.103 reached laptop 192.168.137.1 directly over Wi-Fi.
Verified from the phone shell: Auth config HTTP 200, disha@thapar.edu password login, and authenticated getLeaderboard returned five entries.
No adb reverse port forwarding was used for these network requests; USB was used to execute the diagnostic commands.
Hotspot APK installed and StepUp opened. Manual app-screen login and a fresh real walk remain to be checked.
Demo accounts were recreated with the documented demo password; the presenter has no synthetic step history.
Saved `.demo-data` export exists. Launcher imports it and exports on clean shutdown; demo-save-data.ps1 can save explicitly.

## Walking fix — 14 November 2026
Added the stride-corroborated alternative impact path, LowImpactWalkTest and sanitized low-impact-walk.tsv feature fixture.
Engine suite: 168 tests, 0 failures. Private replay details and limitations: GENUINE_STEP_ENGINE.md (latest section).
New test walk improves from 0 to 37/56 in replay; not fully corrected. Old settled rejections preserved. Build and live walk verification pending installation.

### Pocket walk from zero daily totals

Manual count 50, Android counter 44, verified 10. The four settled intervals credited 0/9, 0/12, 10/13 and 0/10 with full motion coverage. A de-identified feature replay is stored in pocket-walk-50.tsv. Two candidate classifier adjustments failed to improve credit and were discarded. This session remains an open walking-retention defect.

### Paired normal walk and 20-second shake calibration

The recorded walk had 53 hardware counts for 50 manual steps. Original interval credits were 0/15, 14/14, 12/12 and 0/12. Settlement now allows two consecutive gait windows to support nearby ambiguous windows with contiguous timing, matching cadence, gyro and motion evidence. An explicit shake vetoes this recovery throughout its interval. Feature replay credited 53 on this walk (three above the manual count), zero of 24 on the paired shake, and 10 of 44 on the earlier pocket walk. These results are recording-specific. Existing settled credits are immutable.

### Follow-up normal walk with 54 raw counts

Device credits were 14/20, 9/12, 12/12 and 0/10. Allowing a bounded peak-rate discrepancy during adjacent-gait recovery when spectral periodicity, frequency distribution and counter cadence corroborate the motion recovered the last interval. Replay credits 45/54, compared with 35/54 on device. The other nine counts exceed the motion-based credit limits of their intervals. The matched shake replay credits 0/24 and the older pocket walk credits 10/44. No independent manual count was supplied for the 54-count test.

### Profile, home credits and notification fixes

Disha's local demo profile was updated through updateProfile to hostel ID vahni (Vahni Hall). Home credits now list Disha, Raghav, Anvi and Kashish with matching name styles and retain Disha as project lead. Notification navigation now uses go to enter the existing destination tab instead of pushing another stateful navigation shell. Profile URL validation accepts Storage emulator HTTP download URLs on the known demo hosts only when FUNCTIONS_EMULATOR is true; deployed validation still requires HTTPS. Flutter analysis passes and 102 relevant home/profile/notification tests pass. Backend TypeScript and hotspot APK builds pass. Manual photo selection and notification interaction on the phone still need confirmation.
