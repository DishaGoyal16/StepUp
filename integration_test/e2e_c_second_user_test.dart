// On-device E2E, part 3 (step e): the SECOND student on the same phone.
// Sign out student1, register + verify + onboard student2, and check that the
// native step ledger is re-bound to student2 and nothing of student1 leaks.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:stepup/domain/day_key.dart';

import 'support/emulator.dart';
import 'support/harness.dart';

const String student1 = 'student1@thapar.edu';
const String student2 = 'student2@thapar.edu';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('e: second user - sign out, register student2, ledger re-bound', (tester) async {
    final deps = await launchApp(tester);
    if (FirebaseAuth.instance.currentUser == null) await signInViaUi(tester, student1);
    await waitForText(tester, 'Today', timeout: const Duration(seconds: 60));
    final uid1 = currentUid!;
    await pumpUntil(tester, () => deps.stepBinding.isReady, what: 'student1 bound');
    final dayKey = DayKey.of(DateTime.now());
    final v1 = ((await Emu.doc('dailyStepSummaries/${uid1}_$dayKey'))?['verifiedSteps'] as int?) ?? 0;

    // ---- sign out: engine unbound, numbers cleared --------------------------------------------------------------
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    await pumpWhile(tester, deps.signOut());
    await waitForText(tester, 'Welcome to StepUp');
    expect(deps.stepBinding.isReady, isFalse);
    expect(deps.stepBinding.uid, isNull);
    expect(deps.stepTracking.today, isNull, reason: 'previous user numbers must not stay visible');

    // ---- register student2 through the UI ----------------------------------------------------------------------
    await registerViaUi(tester, name: 'Student Two', email: student2);
    await verifyAndWaitForAutoAdvance(tester, student2); // no tap: the poll notices
    await finishOnboarding(tester);
    final uid2 = currentUid!;
    expect(uid2, isNot(uid1));
    expect((await Emu.doc('users/$uid2'))!['email'], student2);
    expect(await Emu.doc('publicProfiles/$uid2'), isNotNull);

    // ---- engine bound to student2; only buckets after the bind --------------------------------------------------
    await pumpUntil(tester, () => deps.stepBinding.isReady && deps.stepBinding.uid == uid2, what: 'student2 bound');
    final bind = deps.stepBinding.lastResult!;
    expect(bind.bound, isTrue);
    // NOT asserted: `bind.changed`. The app may bind the same account twice in a row (unbind->bind on a repeated session
    // event) and `lastResult` keeps only the newest result, a legitimate changed=false repeat; nothing in the app reads it.
    // The guarantee that matters is checked below: the persisted boundary `sinceMs` moved to THIS bind (student1 was bound
    // minutes earlier), so nothing counted before it can be shown or synced under student2.
    expect(bind.sinceMs, greaterThanOrEqualTo(startedAt - 10000), reason: 'sinceMs = bind time (10 s floor), not the old window');
    final b = DayKey.boundsMs(DateTime.now());
    final summary = await deps.stepEngine.getTodaySummary(dayStartMs: b.startMs, dayEndMs: b.endMs);
    // Nobody walked during this test; the engine summary for student2 only covers time after the bind.
    expect(summary.verified, 0);
    final offered = await deps.stepEngine.getBucketsForSync(limit: 200);
    expect(offered.where((e) => e.startMs < bind.sinceMs), isEmpty, reason: 'no bucket from before the bind is offered to student2');

    // Home of student2 shows 0 and not student1's number
    await waitForText(tester, 'of 10,000');
    if (v1 > 0) expect(find.text('$v1'), findsNothing);
    final s2 = await Emu.doc('dailyStepSummaries/${uid2}_$dayKey');
    expect(s2?['verifiedSteps'] ?? 0, 0);
    // student1's server data is untouched
    expect(((await Emu.doc('dailyStepSummaries/${uid1}_$dayKey'))?['verifiedSteps'] as int?) ?? 0, v1);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
