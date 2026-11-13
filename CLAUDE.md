# CLAUDE.md — StepUp (Thapar campus fitness app)

Read this first when resuming. Keep it current. Source of truth for data/API/channel names: `DATABASE_SCHEMA.md`.

## 1. Objective
Flutter Android app for Thapar Institute students: walking/fitness tracking, buddy finder, individual / buddy / inter-hostel /
campus challenges, virtual-point step bets, leaderboards, rewards, admin tools. **Only verified genuine steps** ever count for
leaderboards, challenges, bets, rewards and hostel competitions. Raw/suspicious steps never become reward-eligible.
Never claim perfect accuracy or reliable fake-step detection; what is measured is in `GENUINE_STEP_ENGINE.md` and
`KNOWN_LIMITATIONS.md`.

## 2. Existing architecture inherited (do NOT rewrite the algorithm)
Before this project there was no Flutter app and no Firebase backend. The only prior work is the tested Kotlin sensor
prototype at `../StepUp_Genuine_Step_Detection_v2` (spec: `../DOCS/StepUp_AntiFraud_Architecture_v2.md`):
* `core/` — pure Kotlin/JVM: counter ledger (sensor-timestamp buckets), DSP, hop classifier (WALK/RUN/SHAKE/VEHICLE/STILL/UNKNOWN),
  bucket verifier (`credited = min(raw, floor(1.15 × IMU gait steps))`), ledgers, replay harness, 117 JVM tests.
* `app/` — Android glue: `WitnessEngine` (sensor listeners), `SensorWitnessService` (foreground, type `health`), `WitnessRuntime`, `ArClient`, `BootReceiver`.
This project **copies** that code into `android/stepup_core` (module) and `android/app/src/main/kotlin/edu/thapar/stepup/steps/`
(glue) and exposes it through a MethodChannel/EventChannel (see schema doc). The algorithm/thresholds/tests are preserved
unchanged. The prototype folder is left untouched.

## 3. Stack
Flutter 3.47 / Dart 3.13, Material 3, `provider`, `go_router`. Android: Kotlin 2.4, AGP 9.1, Gradle 9.3, JDK 17 (see §8).
Backend: Firebase Auth, Cloud Firestore, Cloud Functions (Node 20/TypeScript, region `asia-south1`), FCM, Storage (profile photos).
Layers: `lib/data` (Firebase/channel services + repositories) → `lib/domain` (models, rules, pure logic) → `lib/features/*` (screens + view-models). UI never touches Firebase directly.

## 4. Folder structure
```
lib/  main.dart, app.dart, core/ (theme, config, router, widgets), domain/, data/ (auth, firestore, functions, steps),
      features/{auth,onboarding,home,steps,buddies,challenges,bets,leaderboard,profile,notifications,admin}
android/ stepup_core (copied Kotlin core + its tests), app (Flutter host + steps/ bridge)
functions/ src/ (callables, triggers, steps/validateBatch.ts, seed/), test/ (jest + emulator)
firestore.rules  firestore.indexes.json  storage.rules  firebase.json  scripts/
test/ (Flutter unit/widget tests)   docs: README, DATABASE_SCHEMA, FIREBASE_SETUP, TESTING_GUIDE, IMPLEMENTATION_PROGRESS, KNOWN_LIMITATIONS, GENUINE_STEP_ENGINE
```

## 5. Firebase configuration
No real Firebase project is bundled. The app reads config from `--dart-define`: `FIREBASE_API_KEY`, `FIREBASE_APP_ID`,
`FIREBASE_PROJECT_ID`, `FIREBASE_MESSAGING_SENDER_ID`, optional `FIREBASE_STORAGE_BUCKET`, and `USE_FIREBASE_EMULATOR=true`
(+ `EMULATOR_HOST`, default `10.0.2.2`; use `adb reverse` for a physical phone). If config is missing the app shows a
"Backend not configured" screen — it never fakes a backend. Local development uses the Firebase Emulator Suite with the
credential-free project id `demo-stepup`. Steps: `FIREBASE_SETUP.md`.

## 6. Authentication rules
* Only `@thapar.edu` (case-insensitive, exact domain, no subdomains) — checked in Dart **and** in the `beforeUserCreated` blocking function **and** in every callable **and** in Firestore rules.
* Email verification required: unverified users reach only the verification screen. Duplicate accounts prevented by Firebase Auth (email uniqueness) plus `createProfile` idempotency.
* Admin = custom claim `admin:true` set only by `adminSetUserRole` / `scripts/grant-admin.js`; the displayed team names (Disha, Raghav, Bhavya, Sanveer, Anvi, Kashish) are **text only**, never accounts or roles.

## 7. Genuine step integration
Flutter → `StepEngineChannel` → Kotlin service → `WitnessPipeline` → settled buckets (10 s, 90–100 s settlement). A Dart
`StepSyncService` reads settled buckets (`getBucketsForSync`), calls `syncStepBuckets`, and only then `ackBuckets` (at-least-once +
deterministic server IDs ⇒ no duplicate counting). The UI shows raw / verified / pending / rejected(+suspicious). Verified totals are
read-only everywhere; health data from Health Connect is never used. Server re-validates every bucket (downgrade only).

## 8. Build & test commands (Windows)
```powershell
. ..\StepUp_Genuine_Step_Detection_v2\scripts\dev-env.ps1      # JDK17 + UDS workaround + ANDROID_HOME (needed for Gradle here)
$env:Path = "C:\src\flutter\flutter\bin;" + $env:Path
flutter pub get ; flutter analyze ; flutter test
cd android ; .\gradlew.bat :stepup_core:test ; cd ..            # 117 engine regression tests
flutter build apk --debug
cd functions ; npm ci ; npm run build ; npm test                # fast logic tests (no emulator)
npm run test:rules ; npm run test:emulator ; npm run test:functions-e2e   # each already wraps `emulators:exec` — do NOT nest them
# (Windows: JAVA_TOOL_OPTIONS must carry the UDS workaround, i.e. source dev-env.ps1 first; firebase-tools is pinned ^14 because v15 needs Java 21)
```

## 9. Design system (light fitness theme; never dark by default)
Primary `#35A86B`, Secondary `#8BD6A8`, Background `#F7FAF7`, Surface `#FFFFFF`, Text `#18352A`, soft mint `#E6F5EC`, neutral grey `#E7ECE8`.
Rounded 20 px cards, subtle shadows, Material 3, minimal animation. Bottom nav: Home · Buddies · Challenges · Leaderboard · Profile.

## 10. Phases
0 Inspect/plan · 1 Architecture/theme/nav/auth · 2 Onboarding & hostels · 3 Step engine integration & storage · 4 Dashboard & history ·
5 Buddy finder · 6 Challenges · 7 Step bets & points · 8 Leaderboards · 9 Achievements, notifications, profile · 10 Admin & rules · 11 Integration/test/build/zip.
Status lives in `IMPLEMENTATION_PROGRESS.md`.

## 11. Security rules (summary)
Clients write nothing directly (default deny) except marking own notifications read; all mutations are callables using the Admin
SDK with auth/domain/verified/status checks, input validation, deterministic IDs and transactions. Points/steps/results/roles are
server-only. Admin endpoints check the `admin` claim. Details & tests: `firestore.rules`, `functions/test/`.

## 12. Ownership when working in parallel
`functions/`, `firestore.rules`, `storage.rules`, `firestore.indexes.json`, `firebase.json`, `scripts/` = backend. `android/` = native.
`lib/`, `test/`, `pubspec.yaml` = Flutter. Do not edit another area without need; report contract changes in `DATABASE_SCHEMA.md`.

## 12b. On-device end-to-end tests
`integration_test/` drives the real app on a phone against the emulators (`integration_test/README.md`, results in `TESTING_GUIDE.md` 2b). Start the emulators with
`cd functions; npm run build; npm run emulators`, then `integration_test\tools\run-e2e.ps1 -File e2e_a_...dart -Reset -Watcher` (a, then b, c, d, e).
`flutter test` uninstalls the app after every file (a new install id each time); the realme package verifier sometimes rejects that install, so the runner retries with `adb install -r`.
Never kill processes by name; only touch package `edu.thapar.stepup` on the phone.

## 13. Current progress & known limitations
See `IMPLEMENTATION_PROGRESS.md` and `KNOWN_LIMITATIONS.md`. Nothing is marked "tested" without a real test run recorded there.
