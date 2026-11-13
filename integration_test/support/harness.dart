// Shared driver for the on-device integration tests: launches the REAL app
// (real Firebase plugins -> emulators, real MethodChannel to the Kotlin engine)
// and offers bounded-wait helpers and UI flows (register / verify / onboard).
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/app.dart';
import 'package:stepup/app_dependencies.dart';
import 'package:stepup/core/config/app_config.dart';
import 'package:stepup/data/firebase_bootstrap.dart';
import 'package:stepup/data/functions/functions_client.dart';

import 'emulator.dart';

/// Same code path as `main()` (init Firebase from dart-defines, then
/// `StepUpApp(deps: AppDependencies.firebase(config))`), but re-entrant so
/// several `testWidgets` can run in one process (Firebase may only be
/// initialised once).
Future<AppDependencies> launchApp(WidgetTester tester) async {
  final config = AppConfig.fromEnvironment();
  expect(config.useEmulator, isTrue, reason: 'run with --dart-define=USE_FIREBASE_EMULATOR=true');
  expect(config.isConfigured, isTrue);
  if (Firebase.apps.isEmpty) await initializeFirebase(config);
  final deps = AppDependencies.firebase(config);
  await tester.pumpWidget(StepUpApp(deps: deps));
  await pumpFor(tester, const Duration(milliseconds: 500));
  return deps;
}

/// Pumps frames for [d] of real time.
Future<void> pumpFor(WidgetTester t, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps until [cond] is true; fails with [what] after [timeout].
Future<void> pumpUntil(
  WidgetTester t,
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 30),
  String what = 'condition',
}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('timed out after ${timeout.inSeconds}s waiting for $what\n${_visibleText()}');
    }
    await t.pump(const Duration(milliseconds: 150));
  }
}

String _visibleText() {
  final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText() ?? '').where((s) => s.isNotEmpty).take(40).toList();
  return 'visible texts: $texts';
}

Future<void> waitForText(WidgetTester t, String text, {Duration timeout = const Duration(seconds: 30)}) =>
    pumpUntil(t, () => find.text(text).evaluate().isNotEmpty, timeout: timeout, what: 'text "$text"');

Future<void> waitForFinder(WidgetTester t, Finder f, {Duration timeout = const Duration(seconds: 30), String? what}) =>
    pumpUntil(t, () => f.evaluate().isNotEmpty, timeout: timeout, what: what ?? f.toString());

/// Runs a real-async [action] while pumping frames so the UI keeps updating.
Future<T> pumpWhile<T>(WidgetTester t, Future<T> action, {Duration timeout = const Duration(seconds: 60)}) async {
  var done = false;
  Object? error;
  StackTrace? st;
  T? value;
  action.then((v) {
    value = v;
    done = true;
  }, onError: (Object e, StackTrace s) {
    error = e;
    st = s;
    done = true;
  });
  await pumpUntil(t, () => done, timeout: timeout, what: 'async action');
  if (error != null) Error.throwWithStackTrace(error!, st!);
  return value as T;
}

Future<void> tapText(WidgetTester t, String text, {bool last = false}) async {
  final f = find.text(text);
  await waitForFinder(t, f, what: 'tappable "$text"');
  final target = last ? f.last : f.first;
  await t.ensureVisible(target);
  await t.tap(target);
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> enterField(WidgetTester t, String label, String value) async {
  final f = find.widgetWithText(TextFormField, label);
  await waitForFinder(t, f, what: 'field "$label"');
  await t.ensureVisible(f.first);
  await t.enterText(f.first, value);
  await t.pump(const Duration(milliseconds: 100));
}

/// Fills the profile questionnaire (shared by registration step 2 and onboarding when needed).
Future<void> fillProfileAnswers(WidgetTester t, {String hostel = 'Agira Hall'}) async {
  // Hostel dropdown
  final dd = find.byKey(const ValueKey('hostel-dropdown'));
  await waitForFinder(t, dd, what: 'hostel dropdown');
  await t.ensureVisible(dd);
  await t.tap(dd);
  await pumpFor(t, const Duration(milliseconds: 600));
  final item = find.textContaining(hostel);
  await waitForFinder(t, item, what: 'hostel item $hostel');
  await t.tap(item.last);
  await pumpFor(t, const Duration(milliseconds: 500));
  await tapText(t, 'Intermediate');
  await tapText(t, 'Running');
  await tapText(t, 'Walking');
  final act = find.byKey(const ValueKey('activity-dropdown'));
  await t.ensureVisible(act);
  await t.tap(act);
  await pumpFor(t, const Duration(milliseconds: 600));
  await t.tap(find.text('Walking').last);
  await pumpFor(t, const Duration(milliseconds: 500));
  await tapText(t, 'Morning');
  await tapText(t, 'Either');
}

/// Registration through the real UI up to the "Check your inbox" screen.
Future<void> registerViaUi(
  WidgetTester t, {
  required String name,
  required String email,
  String hostel = 'Agira Hall',
}) async {
  await waitForText(t, 'Welcome to StepUp');
  await tapText(t, 'Register');
  await waitForText(t, 'Create your account');
  await enterField(t, 'Full name', name);
  await enterField(t, 'Thapar email', email);
  await enterField(t, 'Password', kPassword);
  await enterField(t, 'Confirm password', kPassword);
  await tapText(t, 'Next');
  await waitForText(t, 'Step 2 of 2 - Your profile');
  await fillProfileAnswers(t, hostel: hostel);
  await tapText(t, 'Create account');
  await waitForText(t, 'Check your inbox', timeout: const Duration(seconds: 40));
}

/// Opens the verification link (as the student would) and taps "I verified".
Future<void> verifyViaEmulatorAndTap(WidgetTester t, String email) async {
  await pumpWhile(t, Emu.verifyEmail(email));
  await tapText(t, 'I verified');
}

/// Student opens the link and simply returns to the app WITHOUT tapping "I verified": the verification screen's 5 s
/// poll must notice it and the app must reach onboarding without showing "We could not load your profile"
/// (regression: the first profile read right after verification was denied because of a stale ID token).
Future<void> verifyAndWaitForAutoAdvance(WidgetTester t, String email) async {
  await pumpWhile(t, Emu.verifyEmail(email));
  final end = DateTime.now().add(const Duration(seconds: 40));
  while (find.text('Finish setting up').evaluate().isEmpty) {
    if (find.textContaining('We could not load your profile').evaluate().isNotEmpty) {
      throw TestFailure('profile load failed right after e-mail verification (stale ID token race)');
    }
    if (DateTime.now().isAfter(end)) throw TestFailure('app did not advance after verification: ${_visibleText()}');
    await t.pump(const Duration(milliseconds: 150));
  }
}

/// After verification: onboarding (answers restored from registration) -> Finish -> Home.
Future<void> finishOnboarding(WidgetTester t) async {
  await waitForText(t, 'Finish setting up', timeout: const Duration(seconds: 40));
  // Wait for the hostel list/draft to be loaded.
  await waitForFinder(t, find.byKey(const ValueKey('hostel-dropdown')));
  await tapText(t, 'Finish');
  await waitForText(t, 'Today', timeout: const Duration(seconds: 60));
}

/// Sign in through the login form.
Future<void> signInViaUi(WidgetTester t, String email) async {
  await waitForText(t, 'Welcome to StepUp');
  await enterField(t, 'Thapar email', email);
  await enterField(t, 'Password', kPassword);
  await tapText(t, 'Login');
}

/// The real FunctionsClient, authenticated as whoever is signed in right now.
FunctionsClient fn() => FirebaseFunctionsClient();

String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

/// Signs in with the Auth SDK (no UI) and force-refreshes the ID token so
/// custom claims / verification are current. Returns the uid.
Future<String> sdkSignIn(String email) async {
  final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: kPassword);
  await cred.user!.getIdToken(true);
  return cred.user!.uid;
}

const bool kAdbWatcher = bool.fromEnvironment('ADB_WATCHER');

/// Handshake with the PC-side `tools/adb-watcher.ps1` (read-only adb queries, or the admin-grant script).
/// Returns null when the watcher is not enabled (`--dart-define=ADB_WATCHER=true`).
Future<Map<String, dynamic>?> adbCheckpoint(String name, {String? arg}) async {
  if (!kAdbWatcher) return null;
  final seq = DateTime.now().microsecondsSinceEpoch.toString();
  await Emu.setControl('phase', {'name': name, 'seq': seq, 'arg': ?arg});
  return Emu.waitFor(() async {
    final c = await Emu.control('adb_$name');
    return (c != null && c['seq'] == seq) ? c : null;
  }, timeout: const Duration(seconds: 90), what: 'watcher checkpoint $name');
}

/// Switches the signed-in account with the Auth SDK (the app UI follows via its session stream)
/// and returns the uid. Used where the test must act as several students in turn.
Future<String> switchUser(WidgetTester t, String email) async {
  final uid = await pumpWhile(t, sdkSignIn(email));
  await pumpFor(t, const Duration(seconds: 2));
  return uid;
}

/// The BuildContext of a screen inside the app's Provider tree (for `context.read<Repo>()`).
BuildContext appContext(WidgetTester t) => t.element(find.byType(Scaffold).first);

/// A hand-built SYNTHETIC walking bucket (see e2e_b header). 5 WALK hops whose IMU steps sum to [raw].
Map<String, dynamic> syntheticBucket(int startMs, int raw) {
  final base = raw ~/ 5;
  final hops = [for (var i = 0; i < 5; i++) {'label': 'WALK', 'imuSteps': i == 4 ? raw - 4 * base : base}];
  return {
    'startMs': startMs,
    'bootCount': 1,
    'rawDelta': raw,
    'credited': raw,
    'state': 'VERIFIED',
    'reason': null,
    'walkFraction': 1.0,
    'evidenceMode': 'E1',
    'carryMode': 'HAND',
    'hops': hops,
  };
}

/// Sends [count] consecutive synthetic buckets (10 s apart) ending ~[endedAgo] ago, in batches of 100.
/// Returns the number of accepted buckets.
Future<int> sendSyntheticSteps(
  WidgetTester t, {
  required String deviceId,
  required int count,
  required int rawPerBucket,
  Duration endedAgo = const Duration(minutes: 9),
}) async {
  final end = ((DateTime.now().millisecondsSinceEpoch - endedAgo.inMilliseconds) ~/ 10000) * 10000;
  final first = end - (count - 1) * 10000;
  var accepted = 0;
  for (var i = 0; i < count; i += 100) {
    final batch = [for (var j = i; j < count && j < i + 100; j++) syntheticBucket(first + j * 10000, rawPerBucket)];
    final r = await pumpWhile(t, fn().call('syncStepBuckets', {'deviceId': deviceId, 'buckets': batch}),
        timeout: const Duration(seconds: 90));
    accepted += r['accepted'] as int;
  }
  return accepted;
}

/// Scrolls the screen's first vertical list until [target] is built and visible (Home is a lazy ListView, so
/// things near the bottom do not exist in the tree until scrolled to). Tolerates the list being rebuilt meanwhile.
Future<void> scrollToFinder(WidgetTester t, Finder target, {int maxTries = 30}) async {
  for (var i = 0; i < maxTries; i++) {
    if (target.evaluate().isNotEmpty) {
      await t.ensureVisible(target.first);
      await t.pump(const Duration(milliseconds: 200));
      return;
    }
    final lists = find.byType(Scrollable);
    if (lists.evaluate().isNotEmpty) {
      await t.drag(lists.first, const Offset(0, -300));
    }
    await t.pump(const Duration(milliseconds: 250));
  }
  throw TestFailure('could not scroll to $target');
}
