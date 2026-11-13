/// Build-time configuration read from `--dart-define` values.
///
/// No real Firebase project is bundled with the app. If the required keys are
/// missing `main()` shows the "Backend not configured" screen instead of
/// pretending to work. See `FIREBASE_SETUP.md`.
class AppConfig {
  const AppConfig({
    this.apiKey = '',
    this.appId = '',
    this.projectId = '',
    this.messagingSenderId = '',
    this.storageBucket = '',
    this.useEmulator = false,
    this.emulatorHost = defaultEmulatorHost,
    this.googleSignInEnabled = false,
    this.googleServerClientId = '',
    this.appVersion = '1.0.0',
  });

  /// Reads the real `--dart-define` values.
  factory AppConfig.fromEnvironment() => AppConfig.resolve(
        apiKey: const String.fromEnvironment('FIREBASE_API_KEY'),
        appId: const String.fromEnvironment('FIREBASE_APP_ID'),
        projectId: const String.fromEnvironment('FIREBASE_PROJECT_ID'),
        messagingSenderId:
            const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
        storageBucket: const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
        useEmulator: const bool.fromEnvironment('USE_FIREBASE_EMULATOR'),
        emulatorHost: const String.fromEnvironment('EMULATOR_HOST'),
        googleSignInEnabled: const bool.fromEnvironment('GOOGLE_SIGN_IN_ENABLED'),
        googleServerClientId:
            const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID'),
        appVersion: const String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0'),
      );

  /// Builds a config from raw values, applying the emulator defaults:
  /// when [useEmulator] is true any missing key falls back to the
  /// credential-free `demo-stepup` values.
  factory AppConfig.resolve({
    String apiKey = '',
    String appId = '',
    String projectId = '',
    String messagingSenderId = '',
    String storageBucket = '',
    bool useEmulator = false,
    String emulatorHost = '',
    bool googleSignInEnabled = false,
    String googleServerClientId = '',
    String appVersion = '1.0.0',
  }) {
    String pick(String value, String demo) =>
        value.isNotEmpty ? value : (useEmulator ? demo : '');
    final project = pick(projectId, demoProjectId);
    return AppConfig(
      apiKey: pick(apiKey, demoApiKey),
      appId: pick(appId, '1:000000000000:android:0000000000000000'),
      projectId: project,
      messagingSenderId: pick(messagingSenderId, '000000000000'),
      storageBucket: storageBucket.isNotEmpty
          ? storageBucket
          : (useEmulator ? '$project.appspot.com' : ''),
      useEmulator: useEmulator,
      emulatorHost: emulatorHost.isEmpty ? defaultEmulatorHost : emulatorHost,
      googleSignInEnabled: googleSignInEnabled,
      googleServerClientId: googleServerClientId,
      appVersion: appVersion,
    );
  }

  static const String demoProjectId = 'demo-stepup';

  /// Credential-free API key used with the emulators. The Auth/Firestore emulators accept any key, but on Android
  /// Firebase Installations (used by Functions/Messaging) rejects a key that is not `A` + 38 chars of `[A-Za-z0-9_-]`
  /// ("Please set a valid API key"), which made EVERY callable fail on a real phone with the old `demo-api-key`.
  static const String demoApiKey = 'AIzaSyDemoStepupEmulatorKey000000000000';
  static const String defaultEmulatorHost = '10.0.2.2';

  /// All callables are deployed to this region (see DATABASE_SCHEMA.md).
  static const String functionsRegion = 'asia-south1';

  static const int authEmulatorPort = 9099;
  static const int firestoreEmulatorPort = 8080;
  static const int functionsEmulatorPort = 5001;
  static const int storageEmulatorPort = 9199;

  final String apiKey;
  final String appId;
  final String projectId;
  final String messagingSenderId;
  final String storageBucket;
  final bool useEmulator;
  final String emulatorHost;
  final bool googleSignInEnabled;
  final String googleServerClientId;
  final String appVersion;

  /// True only if the three mandatory Firebase values are present.
  bool get isConfigured =>
      apiKey.isNotEmpty && appId.isNotEmpty && projectId.isNotEmpty;
}
