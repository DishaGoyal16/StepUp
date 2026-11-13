# FIREBASE_SETUP.md

No Firebase project or credentials are bundled with this repository. The app **does not fake a backend**: without configuration it shows a
"Backend not configured" screen. Two ways to run it:

## A. Local development with the Firebase Emulator Suite (no account, no credentials)
Uses the credential-free project id `demo-stepup`.
```powershell
cd functions ; npm ci ; npm run build
npx firebase emulators:start --project demo-stepup          # auth 9099, firestore 8080, functions 5001, storage 9199
node ..\scripts\seed.js                                      # hostels, challenge templates, badges, settings (emulator)
node ..\scripts\grant-admin.js someone@thapar.edu            # make a first admin (after that user registered)
cd .. ; flutter run --dart-define=USE_FIREBASE_EMULATOR=true
```
* Android emulator reaches the PC at `10.0.2.2` (default `EMULATOR_HOST`).
* A **physical phone**: `adb reverse tcp:9099 tcp:9099` (and 8080, 5001, 9199), then `--dart-define=EMULATOR_HOST=127.0.0.1`.
* The emulator does not send real e-mail: open the Emulator UI / read the verification link from the Auth emulator
  (`http://localhost:9099/emulator/v1/projects/demo-stepup/oobCodes`) or use the helper in `TESTING_GUIDE.md`.

## B. A real Firebase project (production)
1. Create a project in the Firebase console; enable **Authentication** (Email/Password, optionally Google), **Cloud Firestore** (production mode),
   **Cloud Functions** (Blaze plan required), **Cloud Messaging**, **Storage**.
2. Upgrade Authentication to **Identity Platform** if you want the `beforeUserCreated` domain-blocking function (extra layer; rules and callables enforce the domain regardless).
3. Add an Android app with package `edu.thapar.stepup`; add your debug/release **SHA-1/SHA-256** (needed for Google sign-in).
4. Deploy: `firebase use <project-id>`, then `firebase deploy --only firestore:rules,firestore:indexes,storage,functions`.
5. Seed data and first admin with the scripts (they accept `GOOGLE_APPLICATION_CREDENTIALS` for a real project — use a service-account key kept OUTSIDE the repo).
6. Build the app with your project's values:
```
flutter build apk --release ^
  --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=... ^
  --dart-define=FIREBASE_PROJECT_ID=... --dart-define=FIREBASE_MESSAGING_SENDER_ID=... ^
  --dart-define=FIREBASE_STORAGE_BUCKET=... --dart-define=GOOGLE_SIGN_IN_ENABLED=true
```
7. Cloud Functions region is `asia-south1`; set budget alerts; keep `adminSettings/global` limits under admin control.
8. Before relying on rewards: run the step-engine hardware tests in `GENUINE_STEP_ENGINE.md` / `TESTING_GUIDE.md` on the phones you target.

Never commit service-account keys, `google-services.json` with private data, or API secrets.
