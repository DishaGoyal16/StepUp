# TESTING_GUIDE.md

"Tested" in this project means: the command below was run and its real result is recorded in `IMPLEMENTATION_PROGRESS.md`.
Fakes prove the code follows its own rules; only the emulator and hardware sections touch real behaviour.

## 1. Automated suites
| Suite | Command | Proves | Does NOT prove |
|---|---|---|---|
| Flutter analyze | `flutter analyze` | no analyzer issues | behaviour |
| Flutter unit/widget | `flutter test` | auth rules (domain check incl. lookalikes), route guards, hostel directory (18), UI flows for every feature, step-sync idempotency (ack only after server confirm), channel contract against a mocked MethodChannel | real Firebase/Firestore queries, real native bridge |
| Engine + bridge (JVM) | `cd android; .\gradlew.bat :stepup_core:test` | classifier/verifier/ledger (original 117 tests) + summary aggregation, sync ledger/acks, per-user binding, hop pruning | sensors on a phone |
| Backend unit | `cd functions; npm test` | server step validator (Kotlin golden vectors V1-V9 ported), period keys (Asia/Kolkata), bet/challenge/leaderboard math | Firestore behaviour |
| Rules | `cd functions; npm run test:rules` | Firestore + Storage rules: no client writes to steps/points/results/roles/hostels, admin-only reads, domain/verified gates, notifications `read`-only update | production rules deployment |
| Callables | `cd functions; npm run test:emulator` | registration/profile, step sync (valid, duplicate, over-cadence, old, shake hops, over-claim downgrade, late upsert), buddy flows, buddy challenges, join/leave/duplicate, finalize + single reward, bet lifecycle + payout + duplicate prevention + expiry, leaderboards (daily/weekly/monthly/hostel/campus), admin authorization | FCM delivery, deployed triggers/schedulers |
| Functions e2e | `cd functions; npm run test:functions-e2e` | blocking function rejects non-thapar sign-up, real HTTP callable protocol, trigger creating leaderboard entry | production Identity Platform |
(`test:*` scripts already wrap `firebase emulators:exec`; do not nest.) Windows needs the `JAVA_TOOL_OPTIONS` workaround from `dev-env.ps1`.

## 2. Manual end-to-end (emulators + phone)
1. Start emulators + seed (README quick start). Physical phone: `adb reverse tcp:9099 tcp:9099` (and 8080, 5001, 9199); run with `--dart-define=USE_FIREBASE_EMULATOR=true --dart-define=EMULATOR_HOST=127.0.0.1`.
2. Register `name@thapar.edu`; a `gmail.com` address must be refused on the form. Verify the e-mail using the emulator:
   `curl "http://127.0.0.1:9099/emulator/v1/projects/demo-stepup/oobCodes"` -> open the `oobLink` of type VERIFY_EMAIL (or POST it).
3. Complete onboarding (hostel, level, sports) -> home. Grant a first admin: `node scripts/grant-admin.js name@thapar.edu` (re-sign-in).
4. Home -> turn step tracking on -> grant Activity Recognition + notifications -> a foreground notification "StepUp is counting verified steps" appears.

### 2b. Automated on-device end-to-end (`integration_test/`) - what was actually run (2026-11-13, realme RMX3990, emulators only)
Runner: `integration_test/tools/run-e2e.ps1 -File <file> [-Reset] [-Watcher]` (see `integration_test/README.md`). The phone-side helper
`tools/adb-watcher.ps1` grants the two runtime permissions to this app, and does read-only `adb` queries of this app's service and notification.
| File | What it drives on the phone | Result in the final sequence |
|---|---|---|
| `e2e_a_...` | gmail refused; register; server refuses profile before verification; verify via emulator; onboarding (18 live hostels); Home + team credits; tracking on -> foreground service + notification; first sync + reward device | passed (3 of the 6 runs that reached the tracking step) with `adb` evidence (`SensorWitnessService` foreground + notification). It needs a person to tap **Allow** on the two permission dialogs because this phone refuses `adb pm grant` (KNOWN_LIMITATIONS 12); the failed runs had the "permission needed" symptom, and the one probed showed both permissions not granted |
| `e2e_b_...` | SYNTHETIC buckets through the real `syncStepBuckets`: valid, duplicate, over-claim downgrade, shake rejection, Home number | passed |
| `e2e_c_...` | sign out, register student2, ledger re-bound (`sinceMs` moved), nothing of student1 shown | passed |
| `e2e_d_...` | admin vs student access, admin creates a challenge, audit entry | passed |
| `e2e_e_...` | buddies request/accept, individual challenge join, bet rejected with 0 points, bet create/accept with reserved points (points earned via SYNTHETIC buckets) | passed |
The steps in b/e are hand-built payloads sent through the real call path: they prove the server pipeline, NOT that the sensor engine counted a real walk.
Defects found by this run and fixed: admin-created INDIVIDUAL challenges were invisible to students (the list only showed `isTemplate==true`); test-harness races (reward device after reinstall, first empty listener event, verification mail timing).
Not done: a physical 50-step walk, shake/vehicle tests with this app, reboot with tracking on, FCM, Google sign-in, real Firebase project.

## 3. Step hardware checklist (NOT TESTED until a human runs it; see `GENUINE_STEP_ENGINE.md` for the one-phone results so far)
Walk 50 counted steps hand-held; walk 50 with the phone in the pocket; shake hard 30 s; shake slowly and rhythmically seated; bounce the leg seated;
sit still; ride as a passenger; kill the app mid-walk and relaunch; reboot the phone with tracking on; switch accounts on one phone.
Expected: genuine steps credited (verified) after ~100 s settlement and visible on the server; shakes/vehicle rejected ("Rejected/Suspicious");
nothing double counts after restart; the second account never inherits the first account's steps.

## 4. Security checks (automated; see rules + callable suites)
Unauthorized step modification, point/reward modification, role/status self-edit, hostel edits by students, challenge winner edits,
admin-only reads/callables with a student token, non-thapar and unverified tokens — all denied (59 rules tests + admin callable tests).
