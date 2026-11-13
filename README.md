# StepUp — Thapar campus fitness app

Flutter (Android) app for Thapar Institute students: verified-step tracking, buddy finder, individual / buddy / inter-hostel /
campus challenges, friendly step bets with **virtual points only**, leaderboards, rewards, and an admin panel.
Only **verified genuine steps** count for leaderboards, challenges, bets and rewards.

> **Showing it live to someone? Follow `DEMO_GUIDE.md`** (PC hotspot + local test server, demo accounts, run-of-show, honest status).
>
> **Continuing this project? Start with `HANDOFF_FOR_NEXT_AGENT.md`** (everything done, what is verified, what is left).
>
> Status and honesty: read `IMPLEMENTATION_PROGRESS.md` (what was actually tested), `GENUINE_STEP_ENGINE.md` (measured step-engine accuracy
> on one phone) and `KNOWN_LIMITATIONS.md`. No real Firebase project is bundled; the backend was verified against the local Firebase Emulator Suite.

## What is inside
| Path | Contents |
|---|---|
| `lib/` | Flutter app: `core/` (theme, config, router, widgets), `domain/`, `data/` (Firebase + native channel behind interfaces), `features/` (auth, onboarding, home, buddies, challenges, bets, leaderboard, profile, notifications, admin) |
| `android/stepup_core/` | The existing tested Kotlin genuine-step engine (classifier, verifier, ledgers, replay) + bridge classes and tests |
| `android/app/` | Flutter host app, foreground step service (`health`), boot receiver, `StepEnginePlugin` (MethodChannel/EventChannel) |
| `functions/` | Cloud Functions (TypeScript, region `asia-south1`), server step validation, tests |
| `firestore.rules`, `storage.rules`, `firestore.indexes.json`, `firebase.json` | Security rules, indexes, emulator config |
| `scripts/` | `seed.js` (hostels, challenge templates, badges, settings), `grant-admin.js` |
| `DATABASE_SCHEMA.md` | Data model, callable API, channel contract (source of truth) |

## Quick start (local, no Firebase account needed)
Windows PowerShell:
```powershell
. ..\StepUp_Genuine_Step_Detection_v2\scripts\dev-env.ps1          # JDK 17 + Gradle/emulator socket workaround
$env:Path = "C:\src\flutter\flutter\bin;" + $env:Path
flutter pub get

# 1) backend emulators (separate terminal)
cd functions ; npm ci ; npm run build ; npm run emulators           # auth 9099, firestore 8080, functions 5001, storage 9199
# 2) seed (another terminal, with FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099)
node ..\scripts\seed.js
# 3) run the app (Android emulator reaches the PC at 10.0.2.2; a physical phone needs `adb reverse` for 9099 8080 5001 9199)
cd .. ; flutter run --dart-define=USE_FIREBASE_EMULATOR=true
```
Verification e-mails are not sent by the emulator: use the Auth emulator `oobCodes` endpoint (see `TESTING_GUIDE.md`).
For a real Firebase project see `FIREBASE_SETUP.md`.

## Tests
```powershell
flutter analyze ; flutter test                                       # whole app (fakes; no Firebase needed)
cd android ; .\gradlew.bat :stepup_core:test ; cd ..                  # step engine + bridge
cd functions ; npm test ; npm run test:rules ; npm run test:emulator ; npm run test:functions-e2e
```
See `TESTING_GUIDE.md` for what each suite proves and the manual hardware checklist.

## Build
`flutter build apk --debug` (debug APK is large, ~160 MB, because it contains debug engines for all ABIs). Release signing is not configured.

## Roles
Admins are created only by the `adminSetUserRole` callable or `scripts/grant-admin.js` (custom claim `admin:true`). The team names shown on
the home screen (Disha — project lead, Raghav, Bhavya, Sanveer, Anvi, Kashish) are display text only and carry no privileges.
