import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../core/config/app_config.dart';

/// Initialises Firebase from `--dart-define` values (no bundled project) and,
/// when `USE_FIREBASE_EMULATOR=true`, points every service at the emulator
/// suite (Auth 9099, Firestore 8080, Functions 5001, Storage 9199).
Future<void> initializeFirebase(AppConfig config) async {
  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: config.apiKey,
      appId: config.appId,
      messagingSenderId: config.messagingSenderId,
      projectId: config.projectId,
      storageBucket: config.storageBucket.isEmpty ? null : config.storageBucket,
    ),
  );
  if (config.useEmulator) {
    final host = config.emulatorHost;
    // FlutterFire silently rewrites "localhost"/"127.0.0.1" to 10.0.2.2 on Android (the Android-emulator alias of the
    // PC). A physical phone using `adb reverse` + EMULATOR_HOST=127.0.0.1 then cannot reach the emulators (found by the
    // on-device E2E run: Auth sign-up timed out with network-request-failed). The host we hand in is already the right
    // one (default 10.0.2.2 for the Android emulator), so never remap it.
    await FirebaseAuth.instance.useAuthEmulator(host, AppConfig.authEmulatorPort, automaticHostMapping: false);
    FirebaseFirestore.instance
        .useFirestoreEmulator(host, AppConfig.firestoreEmulatorPort, automaticHostMapping: false);
    FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion)
        .useFunctionsEmulator(host, AppConfig.functionsEmulatorPort, automaticHostMapping: false);
    await FirebaseStorage.instance
        .useStorageEmulator(host, AppConfig.storageEmulatorPort, automaticHostMapping: false);
  }
}
