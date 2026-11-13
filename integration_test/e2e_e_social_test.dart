// On-device E2E, part 5 (step g, social half): buddies, an individual
// challenge and step bets through the app's own repositories (real callables,
// real Firestore queries under the real rules) for student1 and student2.
//
// Points: nobody can grant points directly. They are earned legitimately by
// reaching the daily goal. Here that is done with SYNTHETIC buckets (hand-built
// payloads through the real syncStepBuckets path, ~10k steps per student) - not
// physically walked. The bet SETTLEMENT (time based, scheduler) is not run here;
// it is covered by the emulator callable tests.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/data/bets/bet_models.dart';
import 'package:stepup/data/bets/bets_repository.dart';
import 'package:stepup/data/buddies/buddies_repository.dart';
import 'package:stepup/data/buddies/buddy_directory.dart' show BuddySummary;
import 'package:stepup/data/buddies/buddy_models.dart';
import 'package:stepup/data/challenges/challenge_models.dart';
import 'package:stepup/data/challenges/challenge_repository.dart';
import 'package:stepup/features/bets/bets_environment.dart';

import 'support/emulator.dart';
import 'support/harness.dart';

const String student1 = 'student1@thapar.edu';
const String student2 = 'student2@thapar.edu';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('g: buddies, individual challenge, bets', (tester) async {
    final deps = await launchApp(tester);
    final uid1 = await switchUser(tester, student1);
    final uid2 = (await Emu.authUserByEmail(student2))!['localId'] as String;
    await waitForText(tester, 'Today', timeout: const Duration(seconds: 60));
    final ctx = appContext(tester);
    final BuddiesRepository buddies = ctx.read<BuddiesRepository>();
    final ChallengeRepository challenges = ctx.read<ChallengeRepository>();
    final BetsRepository bets = BetsEnvironment.of(deps).repository;

    // ================================ buddies ================================
    final page = await pumpWhile(tester, buddies.search(const BuddyFilters(query: 'Student Two')));
    expect(page.profiles.map((p) => p.uid), contains(uid2), reason: 'student2 is discoverable');
    expect(page.profiles.map((p) => p.uid), isNot(contains(uid1)), reason: 'own profile is not listed');

    final reqId = (await pumpWhile(tester, buddies.sendRequest(uid2, message: 'walk together?')))!;
    expect((await Emu.doc('buddyRequests/$reqId'))!['status'], 'PENDING');
    final outgoing = await pumpWhile(tester, buddies.watchOutgoing(uid1).first);
    expect(outgoing.map((r) => r.id), contains(reqId));
    // duplicate request is refused
    try {
      await pumpWhile(tester, buddies.sendRequest(uid2));
      fail('duplicate buddy request accepted');
    } on AppException catch (e) {
      expect(e.code, 'already-exists');
    }

    await switchUser(tester, student2);
    final incoming = await pumpWhile(tester, buddies.watchIncoming(uid2).first);
    expect(incoming.map((r) => r.id), contains(reqId));
    await pumpWhile(tester, buddies.respond(reqId, accept: true));
    expect((await Emu.doc('buddyRequests/$reqId'))!['status'], 'ACCEPTED');
    // The app's screens LISTEN to this stream (they do not take the first event), so wait for the live query to deliver
    // the new connection. The first event can be an empty one while a freshly switched account's listener attaches.
    Future<List<BuddySummary>> buddiesWith(String me, String other) =>
        buddies.watchBuddies(me).firstWhere((l) => l.any((b) => b.uid == other)).timeout(const Duration(seconds: 25));
    final b2 = await pumpWhile(tester, buddiesWith(uid2, uid1));
    expect(b2.map((b) => b.uid), contains(uid1));
    await switchUser(tester, student1);
    final b1 = await pumpWhile(tester, buddiesWith(uid1, uid2));
    expect(b1.map((b) => b.uid), contains(uid2));

    // ============================ individual challenge ============================
    final open = await pumpWhile(tester, challenges.fetchOpenChallenges(ChallengeType.individual));
    final ch = open.firstWhere((c) => c.title == 'E2E Walk 1000',
        orElse: () => throw TestFailure('challenge missing; run e2e_d first. Have: ${open.map((c) => c.title)}'));
    await pumpWhile(tester, challenges.join(ch.id));
    // Same as the buddy list: the app listens to this stream, so wait for the live query to include the join.
    final mine = await pumpWhile(
        tester,
        challenges
            .watchMyParticipations(uid1)
            .firstWhere((l) => l.any((p) => p.challengeId == ch.id))
            .timeout(const Duration(seconds: 25)));
    expect(mine.map((p) => p.challengeId), contains(ch.id));
    try {
      await pumpWhile(tester, challenges.join(ch.id));
      fail('second join accepted');
    } on AppException catch (e) {
      expect(e.reason, 'ALREADY_JOINED');
    }
    final lb = await pumpWhile(tester, challenges.leaderboard(ch.id));
    expect(lb.entries.map((e) => e.id), contains(uid1));

    // ================================ bets ================================
    // 0 points -> rejected
    expect((await Emu.doc('users/$uid1'))!['pointsBalance'], 0);
    try {
      await pumpWhile(tester, bets.createBet(opponentUid: uid2, targetSteps: 5000, durationDays: 1, stakePoints: 10));
      fail('bet accepted with 0 points');
    } on AppException catch (e) {
      expect(e.reason, 'INSUFFICIENT_POINTS');
    }
    expect(await Emu.where('stepBets', 'challengerUid', uid1), isEmpty);

    // earn the daily-goal reward (10 points) legitimately, with SYNTHETIC steps, for both students
    for (final (email, uid) in [(student1, uid1), (student2, uid2)]) {
      await switchUser(tester, email);
      final deviceId = await deps.stepEngine.getDeviceId();
      await pumpWhile(tester, deps.stepSync.syncNow(force: true)); // registerDevice for this user
      // New install => not the reward device yet (see Emu.promoteRewardDevice); simulate the takeover.
      if ((await Emu.doc('users/$uid'))!['rewardDeviceId'] != deviceId) await Emu.promoteRewardDevice(uid, deviceId);
      final accepted = await sendSyntheticSteps(tester, deviceId: deviceId, count: 295, rawPerBucket: 34);
      expect(accepted, 295);
      await pumpWhile(
        tester,
        Emu.waitFor<bool>(() async => ((await Emu.doc('users/$uid'))!['pointsBalance'] as int) >= 10 ? true : null,
            timeout: const Duration(seconds: 60), what: 'daily goal reward for $email'),
        timeout: const Duration(seconds: 70),
      );
    }

    await switchUser(tester, student1);
    final reqKey = 'e2e-bet-${DateTime.now().millisecondsSinceEpoch}';
    final created = await pumpWhile(
        tester, bets.createBet(opponentUid: uid2, targetSteps: 5000, durationDays: 1, stakePoints: 10, requestId: reqKey));
    expect(created.duplicate, isFalse);
    final dup = await pumpWhile(
        tester, bets.createBet(opponentUid: uid2, targetSteps: 5000, durationDays: 1, stakePoints: 10, requestId: reqKey));
    expect(dup.betId, created.betId);
    expect(dup.duplicate, isTrue, reason: 'same requestId must not create a second bet');
    expect((await Emu.where('stepBets', 'challengerUid', uid1)).length, 1);
    var u1 = (await Emu.doc('users/$uid1'))!;
    expect(u1['pointsReserved'], 10, reason: 'challenger stake reserved');
    final watched = await pumpWhile(
        tester,
        bets.watchBets(uid1).firstWhere((l) => l.any((b) => b.id == created.betId)).timeout(const Duration(seconds: 25)));
    expect(watched.map((b) => b.id), contains(created.betId));
    expect(watched.firstWhere((b) => b.id == created.betId).status, BetStatus.pending);

    await switchUser(tester, student2);
    await pumpWhile(tester, bets.respond(created.betId, accept: true));
    final betDoc = (await Emu.doc('stepBets/${created.betId}'))!;
    expect(betDoc['status'], 'ACTIVE');
    expect((await Emu.doc('users/$uid2'))!['pointsReserved'], 10, reason: 'opponent stake reserved on accept');
    final ledger = await pumpWhile(tester, bets.fetchLedger(uid2));
    expect(ledger.entries, isNotEmpty);
    u1 = (await Emu.doc('users/$uid1'))!;
    expect(u1['pointsReserved'], 10);
  }, timeout: const Timeout(Duration(minutes: 15)));
}
