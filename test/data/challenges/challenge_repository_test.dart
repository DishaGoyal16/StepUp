import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/data/buddies/buddy_directory.dart';
import 'package:stepup/data/challenges/challenge_models.dart';
import 'package:stepup/data/challenges/challenge_repository.dart';
import 'package:stepup/data/challenges/fake_challenge_reader.dart';
import 'package:stepup/data/functions/fake_functions_client.dart';

import '../../features/challenges/challenge_test_support.dart';

void main() {
  late FakeFunctionsClient fn;
  late FakeChallengeReader reader;
  late ChallengeRepository repo;

  setUp(() {
    fn = FakeFunctionsClient();
    reader = FakeChallengeReader();
    repo = ChallengeRepository(reader: reader, functions: fn, buddies: FakeBuddyDirectory());
  });

  group('callables (all writes go through the server)', () {
    test('join / leave send only the challenge id', () async {
      fn
        ..on('joinChallenge', (_) => {'ok': true, 'participant': <String, dynamic>{}})
        ..on('leaveChallenge', (_) => {'ok': true, 'participant': <String, dynamic>{}});
      await repo.join('c1');
      await repo.leave('c1');
      expect(fn.calls.map((c) => c.name), ['joinChallenge', 'leaveChallenge']);
      expect(fn.calls[0].params, {'challengeId': 'c1'});
      expect(fn.calls[1].params, {'challengeId': 'c1'});
    });

    test('createBuddyChallenge sends the contract fields and returns the id', () async {
      fn.on('createBuddyChallenge', (_) => {'challengeId': 'new1'});
      final id = await repo.createBuddyChallenge(
        buddyUid: 'b1',
        title: '  Weekend walk-off ',
        durationDays: 5,
        targetSteps: 30000,
      );
      expect(id, 'new1');
      expect(fn.calls.single.params, {
        'buddyUid': 'b1',
        'title': 'Weekend walk-off',
        'durationDays': 5,
        'targetSteps': 30000,
      });
    });

    test('a blank title is omitted so the server uses its default', () async {
      fn.on('createBuddyChallenge', (_) => {'challengeId': 'new1'});
      await repo.createBuddyChallenge(buddyUid: 'b1', title: '   ', durationDays: 1, targetSteps: 1000);
      expect(fn.calls.single.params.containsKey('title'), isFalse);
    });

    test('a response without challengeId is an AppException', () async {
      fn.on('createBuddyChallenge', (_) => <String, dynamic>{});
      await expectLater(
        repo.createBuddyChallenge(buddyUid: 'b1', durationDays: 1, targetSteps: 1000),
        throwsA(isA<AppException>()),
      );
    });

    test('respondToInvite sends accept true / false', () async {
      fn.on('respondChallengeInvite', (_) => {'ok': true});
      await repo.respondToInvite('c1', accept: true);
      await repo.respondToInvite('c1', accept: false);
      expect(fn.calls[0].params, {'challengeId': 'c1', 'accept': true});
      expect(fn.calls[1].params, {'challengeId': 'c1', 'accept': false});
    });

    test('server errors surface as AppException with the server message', () async {
      fn.failNext(
        'joinChallenge',
        AppException.fromCallable(
          code: 'permission-denied',
          message: 'your hostel is not part of this challenge',
          details: {'reason': 'HOSTEL_NOT_ELIGIBLE'},
        ),
      );
      try {
        await repo.join('c1');
        fail('should throw');
      } on AppException catch (e) {
        expect(e.reason, 'HOSTEL_NOT_ELIGIBLE');
        expect(e.message, 'your hostel is not part of this challenge');
      }
    });

    test('getChallengeLeaderboard is parsed', () async {
      fn.on(
        'getChallengeLeaderboard',
        (p) => leaderboardJson(
          entries: [
            {'rank': 1, 'uid': 'u1', 'name': 'A', 'value': 100, 'progressPct': 10},
          ],
          rank: 4,
          value: 40,
        ),
      );
      final lb = await repo.leaderboard('c1', limit: 20);
      expect(fn.calls.single.params, {'challengeId': 'c1', 'limit': 20});
      expect(lb.entries.single.name, 'A');
      expect(lb.myRank, 4);
      expect(lb.myValue, 40);
    });

  });

  group('reads', () {
    test('open challenges: BUDDY never listed, INDIVIDUAL only templates, only UPCOMING/ACTIVE', () async {
      reader = FakeChallengeReader(challenges: [
        mkChallenge(id: 'tpl', isTemplate: true),
        mkChallenge(id: 'own', isTemplate: false),
        mkChallenge(id: 'done', status: ChallengeStatus.completed),
        mkChallenge(id: 'bud', type: ChallengeType.buddy, status: ChallengeStatus.upcoming),
        mkChallenge(id: 'cam', type: ChallengeType.campus, isTemplate: false, status: ChallengeStatus.upcoming),
      ]);
      repo = ChallengeRepository(reader: reader, functions: fn, buddies: FakeBuddyDirectory());
      // Catalogue template AND the admin-created individual challenge (isTemplate=false) are listed; the completed
      // one and the buddy challenge are not. (Regression: admin-created individual challenges were invisible.)
      expect((await repo.fetchOpenChallenges(ChallengeType.individual)).map((c) => c.id), ['tpl', 'own']);
      expect((await repo.fetchOpenChallenges(ChallengeType.campus)).map((c) => c.id), ['cam']);
    });

    test('fake reader offline throws AppException', () async {
      reader.offline = true;
      await expectLater(repo.fetchChallenge('x'), throwsA(isA<AppException>()));
      await expectLater(repo.fetchOpenChallenges(ChallengeType.campus), throwsA(isA<AppException>()));
    });

    test('watchMyParticipations only returns my documents and is live', () async {
      reader.setParticipations([mkPart('c1', 'me'), mkPart('c2', 'other')]);
      final emitted = <List<String>>[];
      final sub = repo.watchMyParticipations('me').listen((l) => emitted.add([for (final p in l) p.challengeId]));
      await pumpEventQueue();
      reader.putParticipation(mkPart('c3', 'me', progress: 5));
      await pumpEventQueue();
      await sub.cancel();
      expect(emitted.first, ['c1']);
      expect(emitted.last, ['c1', 'c3']);
    });
  });

  group('Home campus activity numbers', () {
    test('countMyActiveChallenges counts only JOINED participations in ACTIVE challenges', () async {
      reader = FakeChallengeReader(
        challenges: [
          mkChallenge(id: 'a1', status: ChallengeStatus.active),
          mkChallenge(id: 'a2', status: ChallengeStatus.active),
          mkChallenge(id: 'up', status: ChallengeStatus.upcoming),
          mkChallenge(id: 'done', status: ChallengeStatus.completed),
          mkChallenge(id: 'left', status: ChallengeStatus.active),
        ],
        participations: [
          mkPart('a1', 'me'),
          mkPart('a2', 'me'),
          mkPart('up', 'me'),
          mkPart('done', 'me'),
          mkPart('left', 'me', status: ParticipantStatus.left),
          mkPart('a1', 'someone-else'),
        ],
      );
      repo = ChallengeRepository(reader: reader, functions: fn, buddies: FakeBuddyDirectory());
      expect(await repo.countMyActiveChallenges('me'), 2);
      expect(await repo.countMyActiveChallenges('nobody'), 0);
    });

    test('countUpcomingHostelCompetitions counts UPCOMING INTER_HOSTEL of my hostel', () async {
      reader = FakeChallengeReader(challenges: [
        mkChallenge(id: 'h1', type: ChallengeType.interHostel, status: ChallengeStatus.upcoming, hostelIds: ['agira', 'tejas']),
        mkChallenge(id: 'h2', type: ChallengeType.interHostel, status: ChallengeStatus.upcoming, hostelIds: ['tejas']),
        mkChallenge(id: 'h3', type: ChallengeType.interHostel, status: ChallengeStatus.active, hostelIds: ['agira']),
      ]);
      repo = ChallengeRepository(reader: reader, functions: fn, buddies: FakeBuddyDirectory());
      expect(await repo.countUpcomingHostelCompetitions('agira'), 1);
      expect(await repo.countUpcomingHostelCompetitions('tejas'), 2);
      expect(await repo.countUpcomingHostelCompetitions('ira'), 0);
    });
  });
}
