// On-device E2E, part 4 (step g, admin half): the /admin route guard, admin
// callables denied for a student, an admin made through the legitimate path
// (scripts/grant-admin.js, run by tools/adb-watcher.ps1), admin dashboard.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/core/router/app_routes.dart';

import 'support/emulator.dart';
import 'support/harness.dart';

const String admin = 'admin@thapar.edu';
const String student2 = 'student2@thapar.edu';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('g-admin: guard, permission-denied for students, admin dashboard', (tester) async {
    final deps = await launchApp(tester);

    // ---- a student cannot open /admin and the admin callables are denied ------------------------------------------
    if (FirebaseAuth.instance.currentUser?.email != student2) {
      if (FirebaseAuth.instance.currentUser != null) await pumpWhile(tester, deps.signOut());
      await signInViaUi(tester, student2);
    }
    await waitForText(tester, 'Today', timeout: const Duration(seconds: 60));
    GoRouter.of(appContext(tester)).go(AppRoutes.admin);
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.text('Registered students'), findsNothing, reason: 'student must not see the admin dashboard');
    expect(find.text('Today'), findsWidgets, reason: 'guard sends the student back Home');
    for (final name in ['adminStats', 'adminListStudents', 'adminSetSettings', 'adminSetUserRole']) {
      try {
        await pumpWhile(tester, fn().call(name, {}));
        fail('$name succeeded for a student');
      } on AppException catch (e) {
        expect(e.code, 'permission-denied', reason: name);
        expect(e.reason, 'ADMIN_REQUIRED', reason: name);
      }
    }

    // ---- create the admin account through the real UI -------------------------------------------------------------
    await pumpWhile(tester, deps.signOut());
    await registerViaUi(tester, name: 'Admin User', email: admin, hostel: 'Agira Hall');
    await verifyViaEmulatorAndTap(tester, admin);
    await finishOnboarding(tester);
    final adminUid = currentUid!;
    expect((await Emu.doc('users/$adminUid'))!['role'], 'student', reason: 'a new account is never admin');

    // still not admin: guard
    GoRouter.of(appContext(tester)).go(AppRoutes.admin);
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.text('Registered students'), findsNothing);

    // ---- grant through the legitimate script (scripts/grant-admin.js) ----------------------------------------------
    final granted = await adbCheckpoint('grant_admin', arg: admin);
    expect(granted, isNotNull, reason: 'run with ADB_WATCHER=true and tools/adb-watcher.ps1');
    expect(granted!['result'], contains('granted admin to $admin'));
    await pumpWhile(tester, FirebaseAuth.instance.currentUser!.getIdToken(true));
    await pumpUntil(tester, () => deps.session.state.isAdmin, what: 'profile role=admin reflected in session');

    // ---- admin dashboard -----------------------------------------------------------------------------------------
    GoRouter.of(appContext(tester)).go(AppRoutes.admin);
    await waitForText(tester, 'Registered students', timeout: const Duration(seconds: 30));
    final stats = await pumpWhile(tester, fn().call('adminStats'));
    expect(stats['users'], greaterThanOrEqualTo(3));
    expect(stats['activeUsers'], greaterThanOrEqualTo(3));
    await waitForText(tester, 'Active accounts');
    expect(find.text('${stats['users']}'), findsWidgets, reason: 'dashboard shows the registered-students count');

    // admin creates a rolling individual challenge for the social test
    final created = await pumpWhile(
      tester,
      fn().call('adminCreateChallenge', {
        'type': 'INDIVIDUAL',
        'metric': 'TOTAL_STEPS',
        'windowMode': 'ROLLING',
        'durationDays': 7,
        'target': 1000,
        'title': 'E2E Walk 1000',
        'description': 'created by the on-device E2E run',
      }),
    );
    expect((await Emu.doc('challenges/${created['challengeId']}'))!['status'], 'ACTIVE');
    // audit trail written by the admin callable
    final audit = await Emu.list('adminAudit');
    expect(audit.where((a) => a['action'] == 'adminCreateChallenge' && a['adminUid'] == adminUid), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 12)));
}
