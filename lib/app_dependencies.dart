import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'core/config/app_config.dart';
import 'core/utils/clock.dart';
import 'data/auth/auth_repository.dart';
import 'data/auth/fake_auth_repository.dart';
import 'data/auth/firebase_auth_repository.dart';
import 'data/firestore/fake_firestore_access.dart';
import 'data/firestore/firebase_firestore_access.dart';
import 'data/firestore/firestore_access.dart';
import 'data/firestore/hostel_repository.dart';
import 'data/functions/callables.dart';
import 'data/functions/fake_functions_client.dart';
import 'data/functions/functions_client.dart';
import 'data/notifications/fake_push_service.dart';
import 'data/notifications/notifications_count.dart';
import 'data/notifications/push_service.dart';
import 'data/profile/fake_photo_services.dart';
import 'data/profile/fake_profile_draft_store.dart';
import 'data/profile/fake_profile_repository.dart';
import 'data/profile/photo_services.dart';
import 'data/profile/profile_draft_store.dart';
import 'data/profile/profile_repository.dart';
import 'data/steps/fake_permission_client.dart';
import 'data/steps/fake_step_engine_channel.dart';
import 'data/steps/method_step_engine_channel.dart';
import 'data/steps/step_engine_binding.dart';
import 'data/steps/step_engine_channel.dart';
import 'data/steps/step_permissions.dart';
import 'data/steps/step_sync_service.dart';
import 'data/steps/step_tracking_controller.dart';
import 'domain/campus_activity.dart';
import 'features/auth/session_controller.dart';

/// The shared singletons of the app. Created once in `main()`
/// ([AppDependencies.firebase]) or in tests ([AppDependencies.fake]) and
/// handed to every feature through `<feature>Providers(deps)`.
///
/// Feature engineers READ from this class; they never edit it. Build your
/// repositories from these fields inside `<feature>Providers(deps)`.
class AppDependencies {
  AppDependencies({
    required this.config,
    required this.clock,
    required this.auth,
    required this.profiles,
    required this.functions,
    required this.firestore,
    required this.hostels,
    required this.stepEngine,
    required this.stepBinding,
    required this.stepPermissions,
    required this.stepSync,
    required this.stepTracking,
    required this.push,
    required this.notificationsCount,
    required this.photoPicker,
    required this.photoUploader,
    required this.draftStore,
    CampusActivityRegistry? campusActivity,
    this.rawFirestore,
    this.isFake = false,
  })  : callables = Callables(functions),
        campusActivity = campusActivity ?? CampusActivityRegistry(),
        session = SessionController(auth: auth, profiles: profiles);

  /// Production wiring. Firebase must already be initialised
  /// (see `initializeFirebase`).
  factory AppDependencies.firebase(AppConfig config) {
    const clock = SystemClock();
    final auth = FirebaseAuthRepository(config: config);
    final functions = FirebaseFunctionsClient();
    final callables = Callables(functions);
    final db = FirebaseFirestore.instance;
    final firestore = FirebaseFirestoreAccess(db);
    final profiles = CallableProfileRepository(firestore: firestore, callables: callables);
    final engine = MethodStepEngineChannel();
    final binding = StepEngineBinding(engine);
    final sync = StepSyncService(
      engine: engine,
      binding: binding,
      callables: callables,
      clock: clock,
      appVersion: config.appVersion,
    );
    final permissions = StepPermissions(const PermissionHandlerClient());
    return AppDependencies(
      config: config,
      clock: clock,
      auth: auth,
      profiles: profiles,
      functions: functions,
      firestore: firestore,
      hostels: HostelRepository(firestore),
      stepEngine: engine,
      stepBinding: binding,
      stepPermissions: permissions,
      stepSync: sync,
      stepTracking: StepTrackingController(
        engine: engine,
        binding: binding,
        permissions: permissions,
        clock: clock,
        sync: sync,
      ),
      push: FirebasePushService(),
      notificationsCount: FirestoreNotificationsCount(firestore),
      photoPicker: ImagePickerPhotoPicker(),
      photoUploader: FirebasePhotoUploader(),
      draftStore: SharedPrefsProfileDraftStore(),
      rawFirestore: db,
    );
  }

  /// In-memory wiring for tests: nothing touches Firebase or the platform.
  /// Any piece can be replaced; the rest is consistent with it.
  factory AppDependencies.fake({
    AppConfig? config,
    Clock? clock,
    FakeAuthRepository? auth,
    FakeFunctionsClient? functions,
    FakeFirestoreAccess? firestore,
    FakeProfileRepository? profiles,
    FakeStepEngineChannel? stepEngine,
    FakePermissionClient? permissions,
    PushService? push,
    NotificationsCount? notificationsCount,
    PhotoPicker? photoPicker,
    PhotoUploader? photoUploader,
    ProfileDraftStore? draftStore,
    Duration syncInterval = const Duration(seconds: 60),
  }) {
    final theClock = clock ?? FakeClock();
    final theAuth = auth ?? FakeAuthRepository();
    final fn = functions ??
        (FakeFunctionsClient()
          ..on('registerDevice', (_) => {'isRewardDevice': true})
          ..on('syncStepBuckets', (_) => {'accepted': 0, 'duplicates': 0, 'rejected': <Object>[]}));
    final fs = firestore ?? FakeFirestoreAccess();
    final engine = stepEngine ?? FakeStepEngineChannel();
    final callables = Callables(fn);
    final binding = StepEngineBinding(engine);
    final sync = StepSyncService(
      engine: engine,
      binding: binding,
      callables: callables,
      clock: theClock,
      interval: syncInterval,
    );
    final perms = StepPermissions(permissions ?? FakePermissionClient());
    return AppDependencies(
      config: config ?? const AppConfig(apiKey: 'fake', appId: 'fake', projectId: 'fake'),
      clock: theClock,
      auth: theAuth,
      profiles: profiles ?? FakeProfileRepository(auth: theAuth),
      functions: fn,
      firestore: fs,
      hostels: HostelRepository(fs, timeout: const Duration(milliseconds: 200)),
      stepEngine: engine,
      stepBinding: binding,
      stepPermissions: perms,
      stepSync: sync,
      stepTracking: StepTrackingController(
        engine: engine,
        binding: binding,
        permissions: perms,
        clock: theClock,
        sync: sync,
      ),
      push: push ?? FakePushService(),
      notificationsCount: notificationsCount ?? FirestoreNotificationsCount(fs),
      photoPicker: photoPicker ?? FakePhotoPicker(),
      photoUploader: photoUploader ?? FakePhotoUploader(),
      draftStore: draftStore ?? InMemoryProfileDraftStore(),
      isFake: true,
    );
  }

  final AppConfig config;
  final Clock clock;

  final AuthRepository auth;
  final ProfileRepository profiles;

  /// Typed callable access. All server mutations go through this.
  final FunctionsClient functions;
  final Callables callables;

  /// Typed read-only Firestore readers (own profile, summaries, hostels,
  /// unread notifications).
  final FirestoreAccess firestore;
  final HostelRepository hostels;

  /// The raw Firestore instance, for feature repositories that need their own
  /// queries. `null` in fake mode - take an interface in your repository and
  /// provide a fake when this is null.
  final FirebaseFirestore? rawFirestore;

  final StepEngineChannel stepEngine;

  /// Which user the native ledger is bound to; sync/summary wait on it.
  final StepEngineBinding stepBinding;
  final StepPermissions stepPermissions;
  final StepSyncService stepSync;
  final StepTrackingController stepTracking;

  final PushService push;
  final NotificationsCount notificationsCount;
  final PhotoPicker photoPicker;
  final PhotoUploader photoUploader;
  final ProfileDraftStore draftStore;

  /// Register numbers for the Home "Campus activity" block from your feature:
  /// `deps.campusActivity.register(CampusSlot.activeChallenges, (uid) async => n)`.
  final CampusActivityRegistry campusActivity;

  /// Auth + profile state used by the router and the whole app.
  final SessionController session;

  /// True when built by [AppDependencies.fake].
  final bool isFake;

  /// Signs out. Best effort first: flush unsent step buckets to the server and
  /// stop tracking, so the next account on this phone does not inherit them.
  Future<void> signOut() async {
    try {
      await stepSync.syncNow(force: true).timeout(const Duration(seconds: 8));
    } catch (_) {}
    try {
      await stepTracking.setTracking(false);
    } catch (_) {}
    await auth.signOut();
  }

  void dispose() {
    stepSync.dispose();
    stepTracking.dispose();
    stepBinding.dispose();
    session.dispose();
  }
}
