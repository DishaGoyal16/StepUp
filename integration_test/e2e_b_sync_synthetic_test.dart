// On-device E2E, part 2 (step f): server round trip of step buckets through the
// REAL syncStepBuckets callable, the Firestore writes and the
// onDailySummaryWritten trigger (Functions emulator).
//
// HONEST LABEL: the buckets below are SYNTHETIC - hand-built payloads sent
// through the real call path. Nobody physically walked them. They prove the
// server pipeline (validation, idempotency, downgrade, summaries, trigger,
// leaderboard, Home), not the sensor engine.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:stepup/domain/day_key.dart';

import 'support/emulator.dart';
import 'support/harness.dart';

const String student1 = 'student1@thapar.edu';

Map<String, dynamic> bucket(
  int startMs, {
  required int raw,
  required int credited,
  required List<(String, int)> hops,
  String state = 'VERIFIED',
}) =>
    {
      'startMs': startMs,
      'bootCount': 1,
      'rawDelta': raw,
      'credited': credited,
      'state': state,
      'reason': null,
      'walkFraction': 1.0,
      'evidenceMode': 'E1',
      'carryMode': 'HAND',
      'hops': [for (final h in hops) {'label': h.$1, 'imuSteps': h.$2}],
    };

int alignedAgo(Duration ago) {
  final t = DateTime.now().millisecondsSinceEpoch - ago.inMilliseconds;
  return (t ~/ 10000) * 10000;
}

Future<int> verifiedToday(String uid, String dayKey) async {
  final s = await Emu.doc('dailyStepSummaries/${uid}_$dayKey');
  return (s?['verifiedSteps'] as int?) ?? 0;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('f: synthetic buckets round trip (valid, duplicate, over-claim, shake)', (tester) async {
    final deps = await launchApp(tester);
    if (FirebaseAuth.instance.currentUser == null) {
      await signInViaUi(tester, student1);
    }
    await waitForText(tester, 'Today', timeout: const Duration(seconds: 60));
    final uid = currentUid!;
    expect((await Emu.doc('users/$uid'))!['email'], student1);

    await pumpUntil(tester, () => deps.stepBinding.isReady, what: 'engine bound');
    final deviceId = await deps.stepEngine.getDeviceId();
    final rep = await pumpWhile(tester, deps.stepSync.syncNow(force: true));
    expect(rep.error, isNull);
    // This install is a NEW device (flutter test uninstalled the app after e2e_a). The server keeps the account's first
    // device as its single reward device, so it must register this one as NOT reward -> assert that, then simulate
    // the 14-day takeover (bookkeeping only) so the buckets below are reward-eligible.
    final reg = (await Emu.doc('users/$uid/devices/$deviceId'))!;
    final firstDevice = (await Emu.doc('users/$uid'))!['rewardDeviceId'];
    if (firstDevice != deviceId) {
      expect(reg['isRewardDevice'], isFalse, reason: 'a second device must not become the reward device');
      await Emu.promoteRewardDevice(uid, deviceId);
    }
    expect((await Emu.doc('users/$uid/devices/$deviceId'))!['isRewardDevice'], isTrue);

    final dayKey = DayKey.of(DateTime.now());
    final before = await verifiedToday(uid, dayKey);

    // ---- valid walking bucket: 5 WALK hops, 16 IMU steps, raw 16, credited 16 -------------------------------
    final s1 = alignedAgo(const Duration(minutes: 10));
    final valid = bucket(s1, raw: 16, credited: 16, hops: [('WALK', 3), ('WALK', 3), ('WALK', 3), ('WALK', 3), ('WALK', 4)]);
    final r1 = await pumpWhile(tester, fn().call('syncStepBuckets', {'deviceId': deviceId, 'buckets': [valid]}));
    expect(r1['accepted'], 1);
    expect(r1['duplicates'], 0);
    expect(r1['rejected'], isEmpty);
    expect(r1['downgraded'], 0);

    final docId = '${uid}_${deviceId}_$s1';
    final stored = (await Emu.doc('stepBuckets/$docId'))!;
    expect(stored['uid'], uid);
    expect(stored['serverCredited'], 16);
    expect(stored['state'], 'VERIFIED');
    expect(stored['rewardEligible'], isTrue);
    final summary1 = (await Emu.doc('dailyStepSummaries/${uid}_$dayKey'))!;
    expect(summary1['verifiedSteps'], before + 16);

    // Home reflects it (live Firestore stream of dailyStepSummaries) ----------------------------------------
    await pumpUntil(tester, () => find.text('${before + 16}').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20), what: 'Home shows ${before + 16} verified steps');

    // The onDailySummaryWritten trigger runs in the Functions emulator -> leaderboard entry ---------------------
    Map<String, dynamic>? mine;
    await pumpWhile(
      tester,
      Emu.waitFor<bool>(() async {
        final lb = await fn().call('getLeaderboard', {'scope': 'CAMPUS', 'period': 'DAILY'});
        final entries = (lb['entries'] as List).cast<Map<String, dynamic>>();
        for (final e in entries) {
          if (e['uid'] == uid && (e['value'] as int) >= before + 16) {
            mine = e;
            return true;
          }
        }
        return null;
      }, timeout: const Duration(seconds: 45), what: 'leaderboard entry via trigger'),
      timeout: const Duration(seconds: 60),
    );
    expect(mine!['value'], before + 16);
    // processDailySummary refreshes the leaderboards first and updates the lifetime total a moment later.
    final lifetime = await pumpWhile(
      tester,
      Emu.waitFor<int>(() async {
        final v = (await Emu.doc('users/$uid'))!['lifetimeVerifiedSteps'] as int?;
        return (v != null && v >= before + 16) ? v : null;
      }, timeout: const Duration(seconds: 30), what: 'lifetimeVerifiedSteps via trigger'),
    );
    expect(lifetime, before + 16, reason: 'trigger processDailySummary updated lifetime total');

    // ---- duplicate: identical re-send changes nothing -------------------------------------------------------
    final r2 = await pumpWhile(tester, fn().call('syncStepBuckets', {'deviceId': deviceId, 'buckets': [valid]}));
    expect(r2['accepted'], 0);
    expect(r2['duplicates'], 1);
    expect(r2['rejected'], isEmpty);
    expect((await Emu.doc('stepBuckets/$docId'))!['serverCredited'], 16);
    expect(await verifiedToday(uid, dayKey), before + 16);
    expect((await Emu.where('stepBuckets', 'uid', uid)).where((b) => b['startMs'] == s1).length, 1);

    // ---- over-claim: IMU saw 10 gait steps -> allowed floor(1.15*10)=11, client claims 20 -> downgraded ------
    final s2 = alignedAgo(const Duration(minutes: 20));
    final over = bucket(s2, raw: 20, credited: 20, hops: [('WALK', 5), ('WALK', 5), ('WALK', 0), ('WALK', 0), ('WALK', 0)]);
    final r3 = await pumpWhile(tester, fn().call('syncStepBuckets', {'deviceId': deviceId, 'buckets': [over]}));
    expect(r3['downgraded'], 1);
    final overDoc = (await Emu.doc('stepBuckets/${uid}_${deviceId}_$s2'))!;
    expect(overDoc['serverCredited'], 11);
    expect(overDoc['clientCredited'], 20);
    expect(overDoc['state'], 'PARTIAL');
    expect(overDoc['flags'], contains('DOWNGRADED'));
    expect(await verifiedToday(uid, dayKey), before + 16 + 11);

    // ---- shaking: hops labelled SHAKE are rejected and add no verified steps ----------------------------------
    final s3 = alignedAgo(const Duration(minutes: 30));
    final shake = bucket(s3, raw: 20, credited: 20, hops: [('SHAKE', 9), ('SHAKE', 9), ('SHAKE', 9), ('SHAKE', 9), ('SHAKE', 9)]);
    final r4 = await pumpWhile(tester, fn().call('syncStepBuckets', {'deviceId': deviceId, 'buckets': [shake]}));
    expect(r4['accepted'], 0);
    expect((r4['rejected'] as List).single['reason'], 'SHAKE_PATTERN');
    final shakeDoc = (await Emu.doc('stepBuckets/${uid}_${deviceId}_$s3'))!;
    expect(shakeDoc['serverCredited'], 0);
    expect(shakeDoc['rewardEligible'], isFalse);
    expect(await verifiedToday(uid, dayKey), before + 16 + 11);

    // Home total follows after the extra buckets
    await pumpUntil(tester, () => find.text('${before + 27}').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20), what: 'Home shows ${before + 27}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
