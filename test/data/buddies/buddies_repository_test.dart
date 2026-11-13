import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/data/buddies/buddies_repository.dart';
import 'package:stepup/data/buddies/buddy_directory.dart';
import 'package:stepup/data/buddies/buddy_models.dart';
import 'package:stepup/data/buddies/fake_buddies_repository.dart';
import 'package:stepup/data/functions/fake_functions_client.dart';
import 'package:stepup/domain/profile_enums.dart';

class _ThrowingDirectory implements BuddyDirectory {
  @override
  Stream<List<BuddySummary>> watchBuddies(String uid) => Stream.error(StateError('denied'));
}

class _NeverDirectory implements BuddyDirectory {
  @override
  Stream<List<BuddySummary>> watchBuddies(String uid) =>
      StreamController<List<BuddySummary>>().stream;
}

void main() {
  late FakeFunctionsClient fn;
  late FakeBuddiesBackend backend;
  late CallableBuddiesRepository repo;

  setUp(() {
    fn = FakeFunctionsClient();
    backend = FakeBuddiesBackend();
    repo = CallableBuddiesRepository(
      functions: fn,
      requests: backend.requests,
      directory: backend.directory,
      countTimeout: const Duration(milliseconds: 50),
    );
  });

  group('search', () {
    test('sends only the used filters plus limit and cursor, parses profiles', () async {
      fn.on('searchBuddies', (_) => {
            'profiles': [
              {'uid': 'a', 'displayName': 'Asha', 'relation': 'BUDDY', 'hostelId': 'agira'},
              {'displayName': 'no uid'},
              'junk',
              {'uid': 'b', 'displayName': 'Bo', 'relation': 'REQUEST_SENT'},
            ],
            'nextCursor': 'b',
          });
      final page = await repo.search(
        const BuddyFilters(query: 'a', fitnessLevel: FitnessLevel.beginner),
        cursor: 'prev',
        limit: 5,
      );
      final call = fn.callsTo('searchBuddies').single;
      expect(call.params, {
        'fitnessLevel': 'BEGINNER',
        'query': 'a',
        'limit': 5,
        'cursor': 'prev',
      });
      expect(page.profiles.map((p) => p.uid), ['a', 'b']);
      expect(page.profiles.first.relation, BuddyRelation.buddy);
      expect(page.profiles.last.relation, BuddyRelation.requestSent);
      expect(page.nextCursor, 'b');
      expect(page.hasMore, isTrue);
    });

    test('null / missing cursor means no more pages; missing list is empty', () async {
      fn.on('searchBuddies', (_) => {'profiles': null, 'nextCursor': null});
      final page = await repo.search(BuddyFilters.empty);
      expect(page.profiles, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('AppException from the callable is passed through unchanged', () async {
      fn.failNext('searchBuddies', AppException.fromCallable(code: 'unavailable'));
      await expectLater(
        repo.search(BuddyFilters.empty),
        throwsA(isA<AppException>().having((e) => e.isRetryable, 'retryable', isTrue)),
      );
    });

    test('an unexpected error becomes an AppException', () async {
      fn.failNext('searchBuddies', StateError('boom'));
      await expectLater(repo.search(BuddyFilters.empty), throwsA(isA<AppException>()));
    });
  });

  group('callables', () {
    test('sendRequest sends toUid + trimmed message and returns the request id', () async {
      fn.on('sendBuddyRequest', (_) => {'ok': true, 'requestId': 'me_bob'});
      final id = await repo.sendRequest('bob', message: '  hello  ');
      expect(id, 'me_bob');
      expect(fn.callsTo('sendBuddyRequest').single.params, {'toUid': 'bob', 'message': 'hello'});
    });

    test('sendRequest omits an empty message', () async {
      fn.on('sendBuddyRequest', (_) => {'ok': true});
      final id = await repo.sendRequest('bob', message: '   ');
      expect(id, isNull);
      expect(fn.callsTo('sendBuddyRequest').single.params, {'toUid': 'bob'});
    });

    test('respond / cancel / removeBuddy / report use the documented params', () async {
      for (final n in ['respondBuddyRequest', 'cancelBuddyRequest', 'removeBuddy', 'reportProfile']) {
        fn.on(n, (_) => {'ok': true});
      }
      await repo.respond('bob_me', accept: true);
      await repo.respond('bob_me', accept: false);
      await repo.cancel('me_bob');
      await repo.removeBuddy('bob');
      await repo.report('bob', ReportReason.fakeProfile, details: ' looks fake ');
      await repo.report('bob', ReportReason.spam);
      final r = fn.callsTo('respondBuddyRequest').toList();
      expect(r[0].params, {'requestId': 'bob_me', 'accept': true});
      expect(r[1].params, {'requestId': 'bob_me', 'accept': false});
      expect(fn.callsTo('cancelBuddyRequest').single.params, {'requestId': 'me_bob'});
      expect(fn.callsTo('removeBuddy').single.params, {'buddyUid': 'bob'});
      final rep = fn.callsTo('reportProfile').toList();
      expect(rep[0].params, {'targetUid': 'bob', 'reason': 'FAKE_PROFILE', 'details': 'looks fake'});
      expect(rep[1].params, {'targetUid': 'bob', 'reason': 'SPAM'});
    });

    test('a server rejection surfaces the friendly AppException with its reason', () async {
      fn.failNext(
        'sendBuddyRequest',
        AppException.fromCallable(
          code: 'already-exists',
          message: 'request pending',
          details: {'reason': 'REQUEST_PENDING'},
        ),
      );
      await expectLater(
        repo.sendRequest('bob'),
        throwsA(isA<AppException>().having((e) => e.reason, 'reason', 'REQUEST_PENDING')),
      );
    });
  });

  group('reads', () {
    BuddyRequest req(String id, {required bool incoming}) => BuddyRequest(
          id: id,
          fromUid: incoming ? 'bob' : 'me',
          toUid: incoming ? 'me' : 'bob',
          incoming: incoming,
          otherName: 'Bob',
        );

    test('watchIncoming / watchOutgoing / watchBuddies delegate to the sources', () async {
      backend.requests.setIncoming([req('bob_me', incoming: true)]);
      backend.requests.setOutgoing([req('me_bob', incoming: false)]);
      backend.directory.setBuddies([const BuddySummary(uid: 'c', displayName: 'Cy')]);
      expect((await repo.watchIncoming('me').first).single.id, 'bob_me');
      expect((await repo.watchOutgoing('me').first).single.id, 'me_bob');
      expect((await repo.watchBuddies('me').first).single.uid, 'c');
    });

    test('activeBuddyCount counts the directory list', () async {
      backend.directory.setBuddies([
        const BuddySummary(uid: 'a', displayName: 'A'),
        const BuddySummary(uid: 'b', displayName: 'B'),
      ]);
      expect(await repo.activeBuddyCount('me'), 2);
    });

    test('activeBuddyCount is 0 for no buddies (not null)', () async {
      expect(await repo.activeBuddyCount('me'), 0);
    });

    test('activeBuddyCount is null on error', () async {
      final r = CallableBuddiesRepository(
        functions: fn,
        requests: backend.requests,
        directory: _ThrowingDirectory(),
      );
      expect(await r.activeBuddyCount('me'), isNull);
    });

    test('activeBuddyCount is null when the read never answers', () async {
      final r = CallableBuddiesRepository(
        functions: fn,
        requests: backend.requests,
        directory: _NeverDirectory(),
        countTimeout: const Duration(milliseconds: 20),
      );
      expect(await r.activeBuddyCount('me'), isNull);
    });
  });

  group('FakeBuddiesRepository (in-memory)', () {
    BuddyProfile p(String uid, String name, {List<String> sports = const []}) =>
        BuddyProfile(uid: uid, displayName: name, sportsInterests: sports);

    test('filters, paginates and keeps relations consistent', () async {
      final fake = FakeBuddiesRepository(
        myUid: 'me',
        students: [
          p('me', 'Me'),
          for (var i = 0; i < 5; i++) p('u$i', 'Student $i', sports: i.isEven ? ['Gym'] : ['Yoga']),
        ],
      );
      final first = await fake.search(BuddyFilters.empty, limit: 2);
      expect(first.profiles.map((x) => x.uid), ['u0', 'u1'], reason: 'self excluded');
      expect(first.nextCursor, '2');
      final second = await fake.search(BuddyFilters.empty, cursor: first.nextCursor, limit: 10);
      expect(second.profiles.length, 3);
      expect(second.hasMore, isFalse);
      final gym = await fake.search(const BuddyFilters(sports: {'Gym'}));
      expect(gym.profiles.map((x) => x.uid), ['u0', 'u2', 'u4']);

      final id = await fake.sendRequest('u1', message: 'hey');
      expect(id, 'me_u1');
      expect(fake.student('u1')!.relation, BuddyRelation.requestSent);
      expect((await fake.watchOutgoing('me').first).single.otherName, 'Student 1');
      await fake.cancel('me_u1');
      expect(fake.student('u1')!.relation, BuddyRelation.none);
      expect(await fake.watchOutgoing('me').first, isEmpty);

      fake.receiveRequest('u2', message: 'join me');
      expect((await fake.watchIncoming('me').first).single.message, 'join me');
      await fake.respond('u2_me', accept: true);
      expect(fake.student('u2')!.relation, BuddyRelation.buddy);
      expect(await fake.activeBuddyCount('me'), 1);
      await fake.removeBuddy('u2');
      expect(await fake.activeBuddyCount('me'), 0);
    });

    test('failNext throws once', () async {
      final fake = FakeBuddiesRepository();
      fake.failNext('search', FakeBuddiesRepository.error('unavailable'));
      await expectLater(fake.search(BuddyFilters.empty), throwsA(isA<AppException>()));
      expect((await fake.search(BuddyFilters.empty)).profiles, isEmpty);
    });
  });

  test('fakeBuddiesBackendFor returns one backend per owner', () {
    final a = Object();
    final b = Object();
    expect(identical(fakeBuddiesBackendFor(a), fakeBuddiesBackendFor(a)), isTrue);
    expect(identical(fakeBuddiesBackendFor(a), fakeBuddiesBackendFor(b)), isFalse);
  });
}
