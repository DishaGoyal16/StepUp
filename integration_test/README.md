# On-device end-to-end tests

These drive the REAL app (real Firebase Auth / Firestore / Functions plugins, real MethodChannel to the Kotlin engine)
on a physical Android phone against the Firebase Emulator Suite. They are not part of `flutter test`.

## One-time per session
```powershell
. ..\StepUp_Genuine_Step_Detection_v2\scripts\dev-env.ps1                    # JDK 17 + UDS workaround
$env:Path = "C:\src\flutter\flutter\bin;" + $env:Path
cd functions ; npm run build ; npm run emulators                              # leave running (auth 9099, firestore 8080, functions 5001, storage 9199)
```

## Run (in this order; each file is one `flutter test` run)
```powershell
# window 1: PC-side helper (grants the 2 runtime permissions to the app, answers adb checkpoints, runs scripts/grant-admin.js)
.\integration_test\tools\adb-watcher.ps1 -Serial <adb-serial> -OutDir $env:TEMP\stepup-adb-evidence

# window 2:
.\integration_test\tools\run-e2e.ps1 -File e2e_a_auth_onboarding_tracking_test.dart -Reset -Watcher   # a-d  (-Reset wipes emulator data and re-seeds)
.\integration_test\tools\run-e2e.ps1 -File e2e_b_sync_synthetic_test.dart                              # f    (SYNTHETIC buckets)
.\integration_test\tools\run-e2e.ps1 -File e2e_c_second_user_test.dart                                 # e
.\integration_test\tools\run-e2e.ps1 -File e2e_d_admin_test.dart -Watcher                              # g (admin)
.\integration_test\tools\run-e2e.ps1 -File e2e_e_social_test.dart                                      # g (buddies/challenge/bets)
```
`run-e2e.ps1` passes `--dart-define=USE_FIREBASE_EMULATOR=true --dart-define=EMULATOR_HOST=127.0.0.1`; the phone needs
`adb reverse tcp:9099/8080/5001/9199` (done by `-Reset`). Debug builds allow cleartext HTTP
(`android/app/src/debug/AndroidManifest.xml`) because the emulators are plain HTTP; release builds do not.

Notes
* `flutter test` uninstalls the app when a run ends. Re-install (`flutter install`/`adb install`) afterwards.
* Steps in e2e_b / e2e_e are SYNTHETIC: hand-built buckets sent through the real `syncStepBuckets` path. They prove the
  server pipeline, not the sensor engine.
* The tests assert server state through the emulators' REST endpoints with the emulator "owner" token (`support/emulator.dart`).
