// On-device E2E, part 1 (steps a-d): registration -> e-mail verification ->
// onboarding -> Home -> step tracking, on the REAL app against the emulators.
//
// Run (see integration_test/README.md): the emulators must be running and reset+seeded.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:stepup/core/errors/app_exception.dart';

import 'support/emulator.dart';
import 'support/harness.dart';

const String student1 = 'student1@thapar.edu';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a-d: register, verify, onboard, home, tracking', (tester) async {
    // Clean session (a previous run may have left someone signed in).
    // Firebase must be initialised first; launchApp does that, then we sign out.
    var deps = await launchApp(tester);
    if (FirebaseAuth.instance.currentUser != null) {
      await pumpWhile(tester, deps.signOut());
      await pumpFor(tester, const Duration(seconds: 1));
    }

    // ---- (a) @gmail.com refused on the form; no account created -------------------------------------------------
    await waitForText(tester, 'Welcome to StepUp');
    await tapText(tester, 'Register');
    await waitForText(tester, 'Create your account');
    await enterField(tester, 'Full name', 'Student One');
    await enterField(tester, 'Thapar email', 'student1@gmail.com');
    await enterField(tester, 'Password', kPassword);
    await enterField(tester, 'Confirm password', kPassword);
    await tapText(tester, 'Next');
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text('Use your @thapar.edu email address'), findsWidgets);
    expect(find.text('Step 1 of 2 - Account'), findsOneWidget, reason: 'must not advance to step 2 with gmail');
    expect(await Emu.authUserByEmail('student1@gmail.com'), isNull);

    // lookalike domains must also be refused
    await enterField(tester, 'Thapar email', 'student1@thapar.edu.evil.com');
    await tapText(tester, 'Next');
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(find.text('Step 1 of 2 - Account'), findsOneWidget);

    // ---- (a) thapar address: continue to step 2, check hostel list (c), create the account -----------------------
    await enterField(tester, 'Thapar email', student1);
    await tapText(tester, 'Next');
    await waitForText(tester, 'Step 2 of 2 - Your profile');
    // grouped hostel list: 18 selectable + 2 group headings
    final hostelDd = find.byKey(const ValueKey('hostel-dropdown'));
    await waitForFinder(tester, hostelDd);
    await pumpFor(tester, const Duration(seconds: 2));
    final dd = tester.widget<DropdownButton<String>>(find.descendant(of: hostelDd, matching: find.byType(DropdownButton<String>)));
    final items = dd.items!;
    final selectable = items.where((i) => i.enabled).length;
    final headings = items.where((i) => !i.enabled).length;
    expect(selectable, 18, reason: 'seeded hostels');
    expect(headings, 2, reason: 'grouped: Hostels + Girls\' hostels');
    // Signed out, the rules (hostels: eligible() only) deny the read, so by design this step shows the built-in list.
    expect(find.textContaining('built-in hostel list'), findsOneWidget);
    final seeded = await Emu.list('hostels');
    expect(seeded.length, 18);

    await fillProfileAnswers(tester);
    await tapText(tester, 'Create account');
    await waitForText(tester, 'Check your inbox', timeout: const Duration(seconds: 40));

    // account exists in the Auth emulator, unverified
    final authUser = (await Emu.authUserByEmail(student1))!;
    expect(authUser['emailVerified'] ?? false, isFalse);
    final uid1 = authUser['localId'] as String;

    // server refuses createProfile before verification
    try {
      await pumpWhile(tester, fn().call('createProfile', {'displayName': 'x'}));
      fail('createProfile succeeded for an unverified user');
    } on AppException catch (e) {
      expect(e.code, 'permission-denied');
      expect(e.reason, 'EMAIL_NOT_VERIFIED');
    }
    expect(await Emu.doc('users/$uid1'), isNull);
    // and a verify mail was issued by the real app
    // (the app sends it right after showing "Check your inbox", so poll instead of reading once)
    final codes = await pumpWhile(
      tester,
      Emu.waitFor<List<Map<String, dynamic>>>(() async {
        final all = await Emu.oobCodes();
        final mine = all.where((c) => c['email'] == student1 && c['requestType'] == 'VERIFY_EMAIL').toList();
        return mine.isEmpty ? null : mine;
      }, timeout: const Duration(seconds: 20), what: 'verification mail for $student1'),
    );
    expect(codes, isNotEmpty);

    // ---- (b) verify through the emulator link, tap "I verified" -------------------------------------------------
    await pumpWhile(tester, Emu.verifyEmail(student1));
    expect((await Emu.authUserByEmail(student1))!['emailVerified'], isTrue);
    await tapText(tester, 'I verified');

    // ---- (c) onboarding restored the registration answers; Finish -> createProfile ------------------------------
    await waitForText(tester, 'Finish setting up', timeout: const Duration(seconds: 40));
    expect(find.textContaining('We kept the answers you gave while registering'), findsOneWidget);
    await waitForFinder(tester, find.byKey(const ValueKey('hostel-dropdown')));
    // After verification the list is read from the seeded Firestore collection (no fallback note), grouped.
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.textContaining('built-in hostel list'), findsNothing, reason: 'live hostels expected after verification');
    final liveDd = tester.widget<DropdownButton<String>>(
        find.descendant(of: find.byKey(const ValueKey('hostel-dropdown')), matching: find.byType(DropdownButton<String>)));
    expect(liveDd.items!.where((i) => i.enabled).length, 18);
    expect(liveDd.items!.where((i) => !i.enabled).length, 2);
    await tapText(tester, 'Finish');
    await waitForText(tester, 'Today', timeout: const Duration(seconds: 60));

    final user = (await Emu.doc('users/$uid1'))!;
    expect(user['email'], student1);
    expect(user['hostelId'], 'agira');
    expect(user['status'], 'ACTIVE');
    expect(user['pointsBalance'], 0);
    expect(user['dailyGoal'], 10000);
    final pub = await Emu.doc('publicProfiles/$uid1');
    expect(pub, isNotNull, reason: 'publicProfiles/{uid} must exist');
    expect(pub!['displayName'], 'Student One');

    // ---- (d) Home from real data -----------------------------------------------------------------------------
    expect(find.text('Hi, Student'), findsOneWidget);
    await waitForText(tester, 'of 10,000');
    expect(find.text('0'), findsWidgets);
    await scrollToFinder(tester, find.text('Kashish'));
    expect(find.textContaining('Project Lead: Disha'), findsOneWidget);
    final kashish = tester.widget<Text>(find.text('Kashish'));
    final disha = tester.widget<Text>(find.text('Raghav'));
    expect(kashish.style!.fontSize!, lessThan(disha.style!.fontSize!));
    expect(kashish.style!.fontWeight!.value, lessThan(disha.style!.fontWeight!.value));

    // session -> engine bound to this user
    await pumpUntil(tester, () => deps.stepBinding.isReady, what: 'bindUser');
    expect(deps.stepBinding.uid, uid1);
    expect(deps.stepBinding.lastResult!.bound, isTrue);

    // Turn tracking on. The two runtime permissions are granted for this app only with `adb shell pm grant`
    // (done by the PC-side watcher), so no system permission dialog blocks the run.
    await adbCheckpoint('grant_permissions');
    await scrollToFinder(tester, find.byKey(const ValueKey('tracking-switch')));
    await pumpFor(tester, const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('tracking-switch')));
    await pumpFor(tester, const Duration(milliseconds: 600));
    if (find.text('Allow step tracking?').evaluate().isNotEmpty) {
      await tapText(tester, 'Continue');
    }
    try {
      // If `adb pm grant` is refused by the phone (realme), Android shows its own permission dialogs: a person must tap
      // Allow on them (physical activity, then notifications). Give that time; with the grant working it is instant.
      await pumpUntil(tester, () => deps.stepTracking.tracking, timeout: const Duration(seconds: 150), what: 'tracking on (tap Allow on the phone)');
    } catch (_) {
      final ps = deps.stepTracking.permissionStatus;
      // ignore: avoid_print
      print('DIAG tracking=${deps.stepTracking.tracking} activity=${ps?.activityRecognition} notifications=${ps?.notifications} '
          'engineError=${deps.stepTracking.engineError} bindingReady=${deps.stepBinding.isReady}');
      rethrow;
    }
    expect(await deps.stepEngine.isTracking(), isTrue);
    await waitForText(tester, 'On - counting your steps');
    expect(deps.stepTracking.engineError, isNull);
    expect(deps.stepTracking.permissionStatus!.canTrack, isTrue);

    // Real foreground service + notification, observed by the PC-side watcher.
    final adb = await adbCheckpoint('tracking_on');
    if (adb != null) {
      expect(adb['service'], 'true', reason: 'SensorWitnessService must appear in dumpsys activity services');
      expect(adb['foreground'], 'true');
      expect(adb['notification'], 'true', reason: 'notification "StepUp is counting verified steps"');
    }

    // Device registration + zero-bucket sync cycle
    final report = await pumpWhile(tester, deps.stepSync.syncNow(force: true));
    expect(report.error, isNull);
    expect(report.skipped, isFalse);
    expect(deps.stepSync.lastError, isNull);
    expect(deps.stepSync.lastSyncAt, isNotNull);
    final deviceId = await deps.stepEngine.getDeviceId();
    final dev = await Emu.waitFor(() => Emu.doc('users/$uid1/devices/$deviceId'), what: 'device doc');
    expect(dev['isRewardDevice'], isTrue);
    expect((await Emu.doc('users/$uid1'))!['rewardDeviceId'], deviceId);
    expect(deps.stepSync.isRewardDevice, isTrue);
  }, timeout: const Timeout(Duration(minutes: 12)));
}
