import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/data/buddies/buddy_directory.dart';
import 'package:stepup/data/buddies/buddy_models.dart';
import 'package:stepup/data/buddies/fake_buddies_repository.dart';
import 'package:stepup/domain/hostel.dart';
import 'package:stepup/domain/hostel_seed.dart';
import 'package:stepup/domain/profile_enums.dart';
import 'package:stepup/features/buddies/buddy_action_result.dart';
import 'package:stepup/features/buddies/buddy_finder_view_model.dart';
import 'package:stepup/features/buddies/buddy_requests_view_model.dart';
import 'package:stepup/features/buddies/my_buddies_view_model.dart';

BuddyProfile student(String uid, String name, {BuddyRelation relation = BuddyRelation.none}) =>
    BuddyProfile(uid: uid, displayName: name, relation: relation, hostelId: 'agira');

Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 5));

AppException serverError(String code, String reason) =>
    FakeBuddiesRepository.error(code, reason: reason);

void main() {
  group('BuddyFinderViewModel', () {
    late FakeBuddiesRepository repo;
    late BuddyFinderViewModel vm;

    BuddyFinderViewModel make({int pageSize = 20, int students = 3}) {
      repo = FakeBuddiesRepository(
        myUid: 'me',
        students: [for (var i = 0; i < students; i++) student('u$i', 'Student $i')],
      );
      return vm = BuddyFinderViewModel(
        repository: repo,
        uid: 'me',
        loadHostels: () async => const HostelDirectory(hostels: hostelSeed, isFallback: true),
        debounce: const Duration(milliseconds: 10),
        pageSize: pageSize,
      );
    }

    tearDown(() => vm.dispose());

    test('start loads hostels and the first page', () async {
      make();
      expect(vm.status, FinderStatus.idle);
      expect(vm.hostelName('agira'), isNull, reason: 'not loaded yet: no raw slug shown');
      await vm.start();
      await flush();
      expect(vm.status, FinderStatus.ready);
      expect(vm.profiles.length, 3);
      expect(vm.hasMore, isFalse);
      expect(vm.hostelName('agira'), 'Agira Hall');
      expect(vm.hostelName(null), isNull);
      expect(vm.hostelName('unknown-id'), isNull);
    });

    test('first-load failure -> error state; retry recovers', () async {
      make();
      repo.failNext('search', FakeBuddiesRepository.error('unavailable'));
      await vm.start();
      expect(vm.status, FinderStatus.error);
      expect(vm.error!.isRetryable, isTrue);
      await vm.retry();
      expect(vm.status, FinderStatus.ready);
      expect(vm.error, isNull);
    });

    test('non-AppException failure still ends in the error state', () async {
      make();
      repo.failNext('search', StateError('boom'));
      await vm.start();
      expect(vm.status, FinderStatus.error);
      expect(vm.error, isA<AppException>());
    });

    test('typing is debounced into a single search', () async {
      make();
      await vm.start();
      repo.calls.clear();
      vm.setQuery('S');
      vm.setQuery('St');
      vm.setQuery('Stu');
      expect(repo.callsTo('search'), isEmpty, reason: 'nothing before the debounce');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final searches = repo.callsTo('search').toList();
      expect(searches.length, 1);
      expect((searches.single.args['filters'] as Map)['query'], 'Stu');
    });

    test('re-typing the same text does not search again', () async {
      make();
      await vm.start();
      vm.setQuery('abc');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      repo.calls.clear();
      vm.setQuery('abc ');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(repo.callsTo('search'), isEmpty);
    });

    test('applyFilters keeps the typed query and restarts from page one', () async {
      make(students: 3);
      await vm.start();
      vm.setQuery('Student 1');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(vm.profiles.map((p) => p.uid), ['u1']);
      await vm.applyFilters(const BuddyFilters(fitnessLevel: FitnessLevel.advanced));
      expect(vm.filters.query, 'Student 1');
      expect(vm.filters.fitnessLevel, FitnessLevel.advanced);
      expect(vm.profiles, isEmpty, reason: 'no advanced student in the fake list');
      await vm.clearFilters();
      expect(vm.filters.fitnessLevel, isNull);
      expect(vm.filters.query, 'Student 1');
    });

    test('loadMore appends the next page, skips duplicates and stops at the end', () async {
      make(pageSize: 2, students: 5);
      await vm.start();
      expect(vm.profiles.length, 2);
      expect(vm.hasMore, isTrue);
      await vm.loadMore();
      expect(vm.profiles.map((p) => p.uid), ['u0', 'u1', 'u2', 'u3']);
      await vm.loadMore();
      expect(vm.profiles.length, 5);
      expect(vm.hasMore, isFalse);
      final callsBefore = repo.callsTo('search').length;
      await vm.loadMore();
      expect(repo.callsTo('search').length, callsBefore, reason: 'no request without a cursor');
    });

    test('a failed loadMore keeps the list and can be retried', () async {
      make(pageSize: 2, students: 4);
      await vm.start();
      repo.failNext('search', FakeBuddiesRepository.error('unavailable'));
      await vm.loadMore();
      expect(vm.profiles.length, 2);
      expect(vm.loadMoreError, isNotNull);
      expect(vm.status, FinderStatus.ready);
      await vm.loadMore();
      expect(vm.profiles.length, 4);
      expect(vm.loadMoreError, isNull);
    });

    test('concurrent loadMore calls load one page only', () async {
      make(pageSize: 2, students: 6);
      await vm.start();
      repo.calls.clear();
      repo.gate = Completer<void>();
      final a = vm.loadMore();
      final b = vm.loadMore();
      repo.gate!.complete();
      await Future.wait([a, b]);
      expect(repo.callsTo('search').length, 1);
      expect(vm.profiles.length, 4);
    });

    test('a slow older search never overwrites a newer one', () async {
      make(students: 3);
      await vm.start();
      final slow = Completer<void>();
      repo.gate = slow;
      final first = vm.applyFilters(const BuddyFilters(fitnessLevel: FitnessLevel.advanced));
      await flush();
      repo.gate = null;
      await vm.applyFilters(BuddyFilters.empty);
      expect(vm.profiles.length, 3);
      slow.complete();
      await first;
      expect(vm.profiles.length, 3, reason: 'stale response ignored');
    });

    group('actions', () {
      test('sendRequest -> REQUEST_SENT with the request id, success message', () async {
        make();
        await vm.start();
        final p = vm.profileById('u0')!;
        final r = await vm.sendRequest(p, message: 'hi');
        expect(r.ok, isTrue);
        expect(r.message, contains('Student 0'));
        expect(vm.profileById('u0')!.relation, BuddyRelation.requestSent);
        expect(vm.profileById('u0')!.requestId, 'me_u0');
        expect(repo.callsTo('sendRequest').single.args['message'], 'hi');
        expect(vm.isBusy('u0'), isFalse);
      });

      test('cancelRequest -> NONE using the deterministic id', () async {
        make();
        await vm.start();
        await vm.sendRequest(vm.profileById('u0')!);
        final r = await vm.cancelRequest(vm.profileById('u0')!);
        expect(r.ok, isTrue);
        expect(vm.profileById('u0')!.relation, BuddyRelation.none);
        expect(repo.callsTo('cancel').single.args['requestId'], 'me_u0');
      });

      test('accept -> BUDDY, reject -> NONE', () async {
        make();
        repo.setStudents([student('a', 'Ann', relation: BuddyRelation.requestReceived), student('b', 'Bea', relation: BuddyRelation.requestReceived)]);
        repo.receiveRequest('a');
        repo.receiveRequest('b');
        await vm.start();
        final ok = await vm.respond(vm.profileById('a')!, accept: true);
        expect(ok.message, 'You and Ann are now buddies.');
        expect(vm.profileById('a')!.relation, BuddyRelation.buddy);
        final no = await vm.respond(vm.profileById('b')!, accept: false);
        expect(no.message, 'Request from Bea rejected.');
        expect(vm.profileById('b')!.relation, BuddyRelation.none);
        expect(repo.callsTo('respond').map((c) => c.args['requestId']), ['a_me', 'b_me']);
        expect(repo.callsTo('respond').map((c) => c.args['accept']), [true, false]);
      });

      test('removeBuddy -> NONE', () async {
        make();
        repo.setStudents([student('a', 'Ann', relation: BuddyRelation.buddy)]);
        await vm.start();
        final r = await vm.removeBuddy(vm.profileById('a')!);
        expect(r.ok, isTrue);
        expect(vm.profileById('a')!.relation, BuddyRelation.none);
      });

      test('report sends the reason and details', () async {
        make();
        await vm.start();
        final r = await vm.report(vm.profileById('u1')!, ReportReason.harassment, details: 'rude');
        expect(r.ok, isTrue);
        final call = repo.callsTo('report').single;
        expect(call.args['reason'], 'HARASSMENT');
        expect(call.args['details'], 'rude');
      });

      test('failures return the friendly message and leave the relation alone', () async {
        make();
        await vm.start();
        repo.failNext('sendRequest', serverError('resource-exhausted', 'TOO_MANY_PENDING_REQUESTS'));
        final r = await vm.sendRequest(vm.profileById('u0')!);
        expect(r.ok, isFalse);
        expect(r.message, contains('too many pending requests'));
        expect(r.needsRefresh, isFalse);
        expect(vm.profileById('u0')!.relation, BuddyRelation.none);
        expect(vm.isBusy('u0'), isFalse);
      });

      test('a stale-state failure triggers a refresh of the list', () async {
        make();
        await vm.start();
        repo.calls.clear();
        repo.failNext('sendRequest', serverError('already-exists', 'REQUEST_PENDING'));
        final r = await vm.sendRequest(vm.profileById('u0')!);
        expect(r.ok, isFalse);
        expect(r.needsRefresh, isTrue);
        await flush();
        expect(repo.callsTo('search').length, 1, reason: 'list reloaded silently');
      });

      test('a second action on the same student while busy is refused', () async {
        make();
        await vm.start();
        repo.gate = Completer<void>();
        final first = vm.sendRequest(vm.profileById('u0')!);
        await flush();
        expect(vm.isBusy('u0'), isTrue);
        final second = await vm.sendRequest(vm.profileById('u0')!);
        expect(second.ok, isFalse);
        repo.gate!.complete();
        expect((await first).ok, isTrue);
        expect(repo.callsTo('sendRequest').length, 1);
      });

      test('cancel without a known request is a clean failure', () async {
        make();
        await vm.start();
        final r = await vm.cancelRequest(vm.profileById('u0')!); // relation NONE
        expect(r.ok, isFalse);
        expect(repo.callsTo('cancel'), isEmpty);
      });
    });

    test('dispose stops notifications and pending timers', () async {
      make();
      await vm.start();
      final before = repo.callsTo('search').length;
      vm.setQuery('zzz');
      vm.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(repo.callsTo('search').length, before, reason: 'the pending debounce was cancelled');
      // the group tearDown disposes `vm`, so hand it a fresh, undisposed one
      vm = BuddyFinderViewModel(repository: repo, uid: 'me');
    });
  });

  group('BuddyRequestsViewModel', () {
    late FakeBuddiesRepository repo;
    late BuddyRequestsViewModel vm;

    setUp(() {
      repo = FakeBuddiesRepository(myUid: 'me', students: [
        student('a', 'Ann'),
        student('b', 'Bea'),
        student('c', 'Cy'),
      ]);
      vm = BuddyRequestsViewModel(repository: repo, uid: 'me');
    });

    tearDown(() => vm.dispose());

    test('lists are null until the first snapshot, then live', () async {
      vm.start();
      await flush();
      expect(vm.incoming, isEmpty);
      expect(vm.outgoing, isEmpty);
      repo.receiveRequest('a', message: 'run?');
      await repo.sendRequest('c');
      await flush();
      expect(vm.incoming!.single.otherName, 'Ann');
      expect(vm.incoming!.single.message, 'run?');
      expect(vm.outgoing!.single.otherName, 'Cy');
    });

    test('accept hides the request and reports success', () async {
      repo.receiveRequest('a');
      vm.start();
      await flush();
      final r = await vm.accept(vm.incoming!.single);
      expect(r.ok, isTrue);
      expect(r.message, 'You and Ann are now buddies.');
      await flush();
      expect(vm.incoming, isEmpty);
      expect(repo.callsTo('respond').single.args, {'requestId': 'a_me', 'accept': true});
    });

    test('reject calls respond(accept:false)', () async {
      repo.receiveRequest('b');
      vm.start();
      await flush();
      final r = await vm.reject(vm.incoming!.single);
      expect(r.message, 'Request from Bea rejected.');
      expect(repo.callsTo('respond').single.args['accept'], false);
    });

    test('cancel removes an outgoing request', () async {
      await repo.sendRequest('c');
      vm.start();
      await flush();
      final r = await vm.cancel(vm.outgoing!.single);
      expect(r.ok, isTrue);
      expect(r.message, 'Request to Cy cancelled.');
      await flush();
      expect(vm.outgoing, isEmpty);
    });

    test('a failed action keeps the request and returns the friendly error', () async {
      repo.receiveRequest('a');
      vm.start();
      await flush();
      repo.failNext('respond', serverError('failed-precondition', 'REQUEST_NOT_PENDING'));
      final r = await vm.accept(vm.incoming!.single);
      expect(r.ok, isFalse);
      expect(r.message, 'This request was already answered.');
      expect(r.needsRefresh, isTrue);
      expect(vm.incoming!.length, 1);
      expect(vm.isBusy('a_me'), isFalse);
    });

    test('stream errors surface per list and retry resubscribes', () async {
      vm.start();
      await flush();
      repo.failIncoming(FakeBuddiesRepository.error('unavailable'));
      await flush();
      expect(vm.incomingError, isNotNull);
      expect(vm.incomingError!.isRetryable, isTrue);
      expect(vm.outgoingError, isNull);
      vm.retry();
      await flush();
      expect(vm.incomingError, isNull);
      expect(vm.incoming, isEmpty);
    });
  });

  group('BuddyRequestsCount', () {
    test('follows the number of incoming requests live', () async {
      final repo = FakeBuddiesRepository(myUid: 'me', students: [student('a', 'A'), student('b', 'B')]);
      final c = BuddyRequestsCount(repository: repo, uid: 'me')..start();
      await flush();
      expect(c.count, 0);
      repo.receiveRequest('a');
      repo.receiveRequest('b');
      await flush();
      expect(c.count, 2);
      await repo.respond('a_me', accept: false);
      await flush();
      expect(c.count, 1);
      c.dispose();
    });

    test('an error hides the badge (count 0, failed true)', () async {
      final repo = FakeBuddiesRepository(myUid: 'me');
      final c = BuddyRequestsCount(repository: repo, uid: 'me')..start();
      await flush();
      repo.failIncoming(FakeBuddiesRepository.error('unavailable'));
      await flush();
      expect(c.failed, isTrue);
      expect(c.count, 0);
      c.dispose();
    });
  });

  group('MyBuddiesViewModel', () {
    late FakeBuddiesRepository repo;
    late MyBuddiesViewModel vm;

    setUp(() {
      repo = FakeBuddiesRepository(myUid: 'me', students: [student('a', 'Ann')]);
      vm = MyBuddiesViewModel(
        repository: repo,
        uid: 'me',
        loadHostels: () async => const HostelDirectory(hostels: hostelSeed, isFallback: true),
      );
    });

    tearDown(() => vm.dispose());

    test('null until loaded, then the live list with hostel names', () async {
      expect(vm.buddies, isNull);
      vm.start();
      await flush();
      expect(vm.buddies, isEmpty);
      repo.addBuddy(const BuddySummary(uid: 'a', displayName: 'Ann', hostelId: 'agira'));
      await flush();
      expect(vm.buddies!.single.displayName, 'Ann');
      expect(vm.hostelName('agira'), 'Agira Hall');
    });

    test('remove calls removeBuddy and drops the buddy', () async {
      repo.addBuddy(const BuddySummary(uid: 'a', displayName: 'Ann'));
      vm.start();
      await flush();
      final r = await vm.remove(vm.buddies!.single);
      expect(r.ok, isTrue);
      expect(r.message, 'Ann was removed from your buddies.');
      expect(vm.buddies, isEmpty);
      expect(repo.callsTo('removeBuddy').single.args['buddyUid'], 'a');
    });

    test('remove failure keeps the buddy', () async {
      repo.addBuddy(const BuddySummary(uid: 'a', displayName: 'Ann'));
      vm.start();
      await flush();
      repo.failNext('removeBuddy', FakeBuddiesRepository.error('unavailable'));
      final r = await vm.remove(vm.buddies!.single);
      expect(r.ok, isFalse);
      expect(vm.buddies!.length, 1);
    });

    test('a stream error shows an error; retry reloads', () async {
      vm.start();
      await flush();
      repo.failBuddies(FakeBuddiesRepository.error('permission-denied'));
      await flush();
      expect(vm.error, isNotNull);
      vm.retry();
      await flush();
      expect(vm.error, isNull);
      expect(vm.buddies, isEmpty);
    });

    test('report uses reportProfile data', () async {
      repo.addBuddy(const BuddySummary(uid: 'a', displayName: 'Ann'));
      vm.start();
      await flush();
      final r = await vm.report(vm.buddies!.single, ReportReason.spam);
      expect(r.ok, isTrue);
      expect(repo.callsTo('report').single.args['reason'], 'SPAM');
    });
  });

  group('buddyErrorMessage', () {
    test('known reasons are translated, unknown use the AppException message', () {
      expect(
        buddyErrorMessage(serverError('already-exists', 'ALREADY_BUDDIES')),
        'You are already buddies.',
      );
      expect(
        buddyErrorMessage(serverError('resource-exhausted', 'REQUEST_COOLDOWN')),
        contains('a little later'),
      );
      expect(
        buddyErrorMessage(AppException.fromCallable(code: 'unavailable')),
        'Network problem. Check your connection and try again.',
      );
    });

    test('only stale-state reasons ask for a refresh', () {
      expect(buddyFailure(serverError('not-found', 'REQUEST_NOT_FOUND')).needsRefresh, isTrue);
      expect(buddyFailure(serverError('invalid-argument', 'CANNOT_REQUEST_SELF')).needsRefresh, isFalse);
      expect(buddyFailure(AppException.fromCallable(code: 'unavailable')).needsRefresh, isFalse);
    });
  });
}
