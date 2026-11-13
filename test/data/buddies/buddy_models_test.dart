import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/data/buddies/buddy_models.dart';
import 'package:stepup/data/buddies/buddy_requests_source.dart';
import 'package:stepup/domain/profile_enums.dart';

class _FakeTimestamp {
  _FakeTimestamp(this._d);
  final DateTime _d;
  DateTime toDate() => _d;
}

void main() {
  group('BuddyProfile.tryFromMap', () {
    test('maps every public field and the relation', () {
      final p = BuddyProfile.tryFromMap({
        'uid': 'u1',
        'displayName': '  Riya Singh ',
        'photoUrl': 'https://x/y.png',
        'hostelId': 'agira',
        'fitnessLevel': 'ADVANCED',
        'sportsInterests': ['Running', 'Gym', 7, ''],
        'preferredActivity': 'Running',
        'preferredTime': 'EVENING',
        'goals': ['Compete'],
        'availability': ['MON', 'SAT'],
        'buddyType': 'GROUP',
        'bio': 'Early riser',
        'weeklyVerifiedSteps': 45210.0,
        'relation': 'REQUEST_RECEIVED',
        'discoverable': true,
        'showOnLeaderboards': true,
      })!;
      expect(p.uid, 'u1');
      expect(p.displayName, 'Riya Singh');
      expect(p.photoUrl, 'https://x/y.png');
      expect(p.hostelId, 'agira');
      expect(p.fitnessLevel, FitnessLevel.advanced);
      expect(p.sportsInterests, ['Running', 'Gym']);
      expect(p.preferredActivity, 'Running');
      expect(p.preferredTime, PreferredTime.evening);
      expect(p.goals, ['Compete']);
      expect(p.availability, ['MON', 'SAT']);
      expect(p.buddyType, BuddyType.group);
      expect(p.bio, 'Early riser');
      expect(p.weeklyVerifiedSteps, 45210);
      expect(p.relation, BuddyRelation.requestReceived);
    });

    test('hostel and weekly steps stay null when not shared', () {
      final p = BuddyProfile.tryFromMap({'uid': 'u1', 'displayName': 'A'})!;
      expect(p.hostelId, isNull);
      expect(p.weeklyVerifiedSteps, isNull);
      expect(p.relation, BuddyRelation.none);
      expect(p.bio, '');
      expect(p.sportsInterests, isEmpty);
    });

    test('never exposes e-mail or location even if a payload contained them', () {
      final p = BuddyProfile.tryFromMap({
        'uid': 'u1',
        'displayName': 'A',
        'email': 'a@thapar.edu',
        'location': {'lat': 1.0, 'lng': 2.0},
        'latitude': 30.35,
      })!;
      final text = '${p.displayName} ${p.bio} ${p.sportsInterests} ${p.goals} '
          '${p.preferredActivity} ${p.hostelId} ${p.requestId}';
      expect(text.contains('thapar.edu'), isFalse);
      expect(text.contains('30.35'), isFalse);
    });

    test('missing uid -> null; missing name -> "Student"; unknown relation -> NONE', () {
      expect(BuddyProfile.tryFromMap({'displayName': 'A'}), isNull);
      expect(BuddyProfile.tryFromMap({'uid': ''}), isNull);
      final p = BuddyProfile.tryFromMap({'uid': 'u', 'relation': 'WHATEVER'})!;
      expect(p.displayName, 'Student');
      expect(p.relation, BuddyRelation.none);
    });

    test('pendingRequestId uses the deterministic {from}_{to} id', () {
      final sent = BuddyProfile.tryFromMap({'uid': 'bob', 'relation': 'REQUEST_SENT'})!;
      final received = BuddyProfile.tryFromMap({'uid': 'bob', 'relation': 'REQUEST_RECEIVED'})!;
      final none = BuddyProfile.tryFromMap({'uid': 'bob'})!;
      expect(sent.pendingRequestId('me'), 'me_bob');
      expect(received.pendingRequestId('me'), 'bob_me');
      expect(none.pendingRequestId('me'), isNull);
      final explicit = sent.withRelation(BuddyRelation.requestSent, requestId: 'custom');
      expect(explicit.pendingRequestId('me'), 'custom');
    });

    test('withRelation keeps every other field', () {
      final p = BuddyProfile.tryFromMap({
        'uid': 'u',
        'displayName': 'A',
        'hostelId': 'agira',
        'weeklyVerifiedSteps': 10,
        'sportsInterests': ['Yoga'],
      })!;
      final b = p.withRelation(BuddyRelation.buddy);
      expect(b.relation, BuddyRelation.buddy);
      expect(b.hostelId, 'agira');
      expect(b.weeklyVerifiedSteps, 10);
      expect(b.sportsInterests, ['Yoga']);
    });
  });

  group('BuddyRequest.tryFromMap', () {
    final created = DateTime.utc(2026, 11, 13, 4);

    test('incoming: uses fromName / fromPhotoUrl of the document', () {
      final r = BuddyRequest.tryFromMap(
        'bob_me',
        {
          'fromUid': 'bob',
          'toUid': 'me',
          'status': 'PENDING',
          'message': ' hi ',
          'fromName': 'Bob',
          'fromPhotoUrl': 'https://p',
          'createdAt': _FakeTimestamp(created),
        },
        myUid: 'me',
      )!;
      expect(r.incoming, isTrue);
      expect(r.otherUid, 'bob');
      expect(r.otherName, 'Bob');
      expect(r.otherPhotoUrl, 'https://p');
      expect(r.message, 'hi');
      expect(r.createdAt, created);
    });

    test('outgoing: uses the supplied recipient name', () {
      final r = BuddyRequest.tryFromMap(
        'me_cara',
        {'fromUid': 'me', 'toUid': 'cara', 'fromName': 'Me', 'createdAt': created},
        myUid: 'me',
        otherName: 'Cara',
      )!;
      expect(r.incoming, isFalse);
      expect(r.otherUid, 'cara');
      expect(r.otherName, 'Cara');
      expect(r.createdAt, created);
    });

    test('foreign or malformed documents are skipped', () {
      expect(BuddyRequest.tryFromMap('x', {'fromUid': 'a', 'toUid': 'b'}, myUid: 'me'), isNull);
      expect(BuddyRequest.tryFromMap('x', {'toUid': 'me'}, myUid: 'me'), isNull);
    });

    test('pending server timestamp (null) does not crash', () {
      final r = BuddyRequest.tryFromMap(
        'me_cara',
        {'fromUid': 'me', 'toUid': 'cara', 'createdAt': null},
        myUid: 'me',
      )!;
      expect(r.createdAt, isNull);
      expect(r.otherName, 'Student');
    });
  });

  test('sortRequestsNewestFirst: newest first, unresolved timestamp first', () {
    BuddyRequest mk(String id, DateTime? at) => BuddyRequest(
          id: id,
          fromUid: 'a',
          toUid: 'me',
          incoming: true,
          otherName: id,
          createdAt: at,
        );
    final sorted = sortRequestsNewestFirst([
      mk('old', DateTime.utc(2026, 1, 1)),
      mk('pending', null),
      mk('new', DateTime.utc(2026, 6, 1)),
    ]);
    expect(sorted.map((r) => r.id), ['pending', 'new', 'old']);
  });

  group('BuddyFilters', () {
    test('empty filters send nothing but the paging params', () {
      expect(BuddyFilters.empty.toParams(limit: 20), {'limit': 20});
      expect(BuddyFilters.empty.hasAny, isFalse);
      expect(BuddyFilters.empty.activeCount, 0);
    });

    test('toParams carries every filter with wire values, sorted and trimmed', () {
      const f = BuddyFilters(
        query: '  riya ',
        fitnessLevel: FitnessLevel.beginner,
        sports: {'Gym', 'Cricket'},
        hostelId: 'agira',
        preferredTime: PreferredTime.morning,
        goals: {'Stay active'},
        availability: {'SAT', 'MON'},
        buddyType: BuddyType.individual,
      );
      expect(f.toParams(limit: 10, cursor: 'abc'), {
        'fitnessLevel': 'BEGINNER',
        'sports': ['Cricket', 'Gym'],
        'hostelId': 'agira',
        'preferredTime': 'MORNING',
        'goals': ['Stay active'],
        'availability': ['MON', 'SAT'],
        'buddyType': 'INDIVIDUAL',
        'query': 'riya',
        'limit': 10,
        'cursor': 'abc',
      });
      expect(f.activeCount, 7);
      expect(f.hasAny, isTrue);
    });

    test('the query is capped at the backend limit', () {
      final f = BuddyFilters(query: 'x' * 100);
      expect((f.toParams()['query'] as String).length, BuddyFilters.maxQueryLength);
    });

    test('copyWith can set and clear nullable filters', () {
      var f = const BuddyFilters().copyWith(fitnessLevel: FitnessLevel.advanced, hostelId: 'agira');
      expect(f.fitnessLevel, FitnessLevel.advanced);
      f = f.copyWith(fitnessLevel: null);
      expect(f.fitnessLevel, isNull);
      expect(f.hostelId, 'agira', reason: 'untouched');
      expect(f.withoutQuery.hostelId, 'agira');
    });
  });

  test('BuddySearchPage.hasMore follows nextCursor', () {
    expect(const BuddySearchPage(profiles: []).hasMore, isFalse);
    expect(const BuddySearchPage(profiles: [], nextCursor: '').hasMore, isFalse);
    expect(const BuddySearchPage(profiles: [], nextCursor: 'c').hasMore, isTrue);
  });
}
