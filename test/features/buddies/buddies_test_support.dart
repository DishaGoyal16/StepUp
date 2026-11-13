import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:stepup/data/functions/fake_functions_client.dart';

import '../../support/harness.dart';

/// A `searchBuddies` result row (public profile + uid + relation).
Map<String, dynamic> studentJson(
  String uid, {
  String? name,
  String relation = 'NONE',
  String? hostelId = 'agira',
  int? weeklySteps = 12345,
  List<String> sports = const ['Running', 'Gym'],
  String fitnessLevel = 'INTERMEDIATE',
  String bio = 'Early morning runner',
  String? preferredActivity = 'Running',
  String? preferredTime = 'MORNING',
  List<String> goals = const ['Stay active'],
  List<String> availability = const ['MON', 'WED'],
  String buddyType = 'BOTH',
}) =>
    {
      'uid': uid,
      'displayName': name ?? 'Student $uid',
      'photoUrl': null,
      'hostelId': ?hostelId,
      'fitnessLevel': fitnessLevel,
      'sportsInterests': sports,
      'preferredActivity': ?preferredActivity,
      'preferredTime': ?preferredTime,
      'goals': goals,
      'availability': availability,
      'buddyType': buddyType,
      'bio': bio,
      'weeklyVerifiedSteps': ?weeklySteps,
      'relation': relation,
      'discoverable': true,
      'showOnLeaderboards': true,
    };

/// Installs callable handlers on a [FakeFunctionsClient] that behave like the
/// backend for the buddy callables, over a mutable list of students.
class BuddyBackendStub {
  BuddyBackendStub(this.fn, this.students, {required this.myUid});

  final FakeFunctionsClient fn;
  final List<Map<String, dynamic>> students;
  final String myUid;

  Map<String, dynamic>? byUid(Object? uid) {
    for (final s in students) {
      if (s['uid'] == uid) return s;
    }
    return null;
  }

  void install() {
    fn.on('searchBuddies', (p) {
      final filtered = students.where((s) {
        final q = (p['query'] as String?)?.toLowerCase();
        if (q != null && !(s['displayName'] as String).toLowerCase().contains(q)) return false;
        final level = p['fitnessLevel'];
        if (level != null && s['fitnessLevel'] != level) return false;
        final sports = p['sports'] as List?;
        if (sports != null && !sports.any((x) => (s['sportsInterests'] as List).contains(x))) {
          return false;
        }
        final hostel = p['hostelId'];
        if (hostel != null && s['hostelId'] != hostel) return false;
        return true;
      }).toList();
      final limit = (p['limit'] as int?) ?? 20;
      final start = int.tryParse((p['cursor'] as String?) ?? '') ?? 0;
      final end = (start + limit).clamp(0, filtered.length);
      final page = filtered.sublist(start.clamp(0, filtered.length), end);
      return {
        'profiles': [for (final s in page) Map<String, dynamic>.from(s)],
        'nextCursor': end < filtered.length ? '$end' : null,
      };
    });
    fn.on('sendBuddyRequest', (p) {
      byUid(p['toUid'])?['relation'] = 'REQUEST_SENT';
      return {'ok': true, 'requestId': '${myUid}_${p['toUid']}'};
    });
    fn.on('cancelBuddyRequest', (p) {
      final other = (p['requestId'] as String).replaceFirst('${myUid}_', '');
      byUid(other)?['relation'] = 'NONE';
      return {'ok': true};
    });
    fn.on('respondBuddyRequest', (p) {
      final other = (p['requestId'] as String).replaceFirst('_$myUid', '');
      byUid(other)?['relation'] = p['accept'] == true ? 'BUDDY' : 'NONE';
      return {'ok': true};
    });
    fn.on('removeBuddy', (p) {
      byUid(p['buddyUid'])?['relation'] = 'NONE';
      return {'ok': true};
    });
    fn.on('reportProfile', (_) => {'ok': true});
  }
}

/// Harness signed in with a profile; returns the stub too.
({Harness h, BuddyBackendStub backend, String uid}) buddiesSetup(
  List<Map<String, dynamic>> students,
) {
  final h = Harness.create(signedIn: true, withProfile: true);
  final uid = h.user!.uid;
  final backend = BuddyBackendStub(h.functions, students, myUid: uid)..install();
  return (h: h, backend: backend, uid: uid);
}

Future<void> settle(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> openBuddies(WidgetTester tester, Harness h) async {
  await h.pumpApp(tester, initialLocation: '/buddies');
  await settle(tester);
}

/// The router's current location (path + query).
String currentLocation(WidgetTester tester) {
  final ctx = tester.element(find.byType(Scaffold).first);
  final config = GoRouter.of(ctx).routerDelegate.currentConfiguration;
  final last = config.last;
  // A pushed route (context.push) is an imperative match with its own list.
  if (last is ImperativeRouteMatch) return last.matches.uri.toString();
  return config.uri.toString();
}
