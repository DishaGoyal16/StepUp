import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/data/buddies/buddy_directory.dart';
import 'package:stepup/data/buddies/buddy_models.dart';
import 'package:stepup/data/buddies/fake_buddies_repository.dart';

import '../../support/harness.dart';
import 'buddies_test_support.dart';

BuddyRequest incoming(String from, String name, String me, {String message = ''}) => BuddyRequest(
      id: '${from}_$me',
      fromUid: from,
      toUid: me,
      incoming: true,
      otherName: name,
      message: message,
      createdAt: DateTime.utc(2026, 11, 13, 4, 30), // 2 h before the harness clock (06:00 UTC)
    );

BuddyRequest outgoing(String to, String name, String me) => BuddyRequest(
      id: '${me}_$to',
      fromUid: me,
      toUid: to,
      incoming: false,
      otherName: name,
      createdAt: DateTime.utc(2026, 11, 13, 5, 59, 30),
    );

void main() {
  group('Requests button badge (BuddyRequestsCount)', () {
    testWidgets('shows the live number of pending incoming requests', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([]);
      final fakes = fakeBuddiesBackendFor(s.h.deps);
      fakes.requests.setIncoming([incoming('a', 'Ann', s.uid), incoming('b', 'Bea', s.uid)]);
      await openBuddies(tester, s.h);

      expect(find.text('Requests'), findsOneWidget);
      expect(find.widgetWithText(Badge, 'Requests'), findsOneWidget);
      expect(find.descendant(of: find.byType(Badge), matching: find.text('2')), findsOneWidget);

      fakes.requests.setIncoming([incoming('a', 'Ann', s.uid)]);
      await settle(tester);
      expect(find.descendant(of: find.byType(Badge), matching: find.text('1')), findsOneWidget);

      fakes.requests.setIncoming([]);
      await settle(tester);
      expect(tester.widget<Badge>(find.widgetWithText(Badge, 'Requests')).isLabelVisible, isFalse);
    });

    testWidgets('tapping Requests opens /buddies/requests', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([]);
      await openBuddies(tester, s.h);
      await tester.tap(find.text('Requests'));
      await settle(tester);
      expect(currentLocation(tester), '/buddies/requests');
      expect(find.text('Buddy requests'), findsOneWidget);
      expect(find.text('Incoming'), findsOneWidget);
      expect(find.text('Outgoing'), findsOneWidget);
    });
  });

  group('Requests screen', () {
    testWidgets('empty states for both tabs', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([]);
      await s.h.pumpApp(tester, initialLocation: '/buddies/requests');
      await settle(tester);
      expect(find.text('No incoming requests'), findsOneWidget);
      await tester.tap(find.text('Outgoing'));
      await settle(tester);
      expect(find.text('No outgoing requests'), findsOneWidget);
    });

    testWidgets('incoming: shows message and time, Accept calls respondBuddyRequest', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([]);
      final fakes = fakeBuddiesBackendFor(s.h.deps);
      fakes.requests.setIncoming([
        incoming('a', 'Ann', s.uid, message: 'Run with me?'),
        incoming('b', 'Bea', s.uid),
      ]);
      s.h.functions.on('respondBuddyRequest', (p) => {'ok': true});
      await s.h.pumpApp(tester, initialLocation: '/buddies/requests');
      await settle(tester);

      expect(find.text('Incoming (2)'), findsOneWidget);
      expect(find.text('Ann'), findsOneWidget);
      expect(find.text('"Run with me?"'), findsOneWidget);
      expect(find.text('Wants to be your buddy · 1 h ago'), findsNWidgets(2));

      await tester.tap(find.text('Accept').first);
      await settle(tester);
      expect(s.h.functions.callsTo('respondBuddyRequest').single.params,
          {'requestId': 'a_${s.uid}', 'accept': true});
      expect(find.text('You and Ann are now buddies.'), findsOneWidget);
      expect(find.text('Ann'), findsNothing, reason: 'answered request disappears');
      expect(find.text('Incoming (1)'), findsOneWidget);
    });

    testWidgets('incoming: Reject calls respondBuddyRequest(accept:false)', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([]);
      fakeBuddiesBackendFor(s.h.deps).requests.setIncoming([incoming('b', 'Bea', s.uid)]);
      await s.h.pumpApp(tester, initialLocation: '/buddies/requests');
      await settle(tester);
      await tester.tap(find.text('Reject'));
      await settle(tester);
      expect(s.h.functions.callsTo('respondBuddyRequest').single.params,
          {'requestId': 'b_${s.uid}', 'accept': false});
      expect(find.text('Request from Bea rejected.'), findsOneWidget);
      expect(find.text('No incoming requests'), findsOneWidget);
    });

    testWidgets('a rejected action (request already answered) shows the reason and keeps the card',
        (tester) async {
      useTallView(tester);
      final s = buddiesSetup([]);
      fakeBuddiesBackendFor(s.h.deps).requests.setIncoming([incoming('a', 'Ann', s.uid)]);
      await s.h.pumpApp(tester, initialLocation: '/buddies/requests');
      await settle(tester);
      s.h.functions.failNext(
        'respondBuddyRequest',
        AppException.fromCallable(
          code: 'failed-precondition',
          message: 'request not pending',
          details: {'reason': 'REQUEST_NOT_PENDING'},
        ),
      );
      await tester.tap(find.text('Accept'));
      await settle(tester);
      expect(find.text('This request was already answered.'), findsOneWidget);
      expect(find.text('Ann'), findsOneWidget);
    });

    testWidgets('outgoing: Cancel request calls cancelBuddyRequest', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([]);
      fakeBuddiesBackendFor(s.h.deps).requests.setOutgoing([outgoing('c', 'Cy', s.uid)]);
      s.h.functions.on('cancelBuddyRequest', (p) => {'ok': true});
      await s.h.pumpApp(tester, initialLocation: '/buddies/requests');
      await settle(tester);
      await tester.tap(find.text('Outgoing (1)'));
      await settle(tester);
      expect(find.text('Cy'), findsOneWidget);
      expect(find.text('Waiting for a reply · just now'), findsOneWidget);

      await tester.tap(find.text('Cancel request'));
      await settle(tester);
      expect(s.h.functions.callsTo('cancelBuddyRequest').single.params,
          {'requestId': '${s.uid}_c'});
      expect(find.text('Request to Cy cancelled.'), findsOneWidget);
      expect(find.text('No outgoing requests'), findsOneWidget);
    });

    testWidgets('lists update live when the server data changes', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([]);
      final fakes = fakeBuddiesBackendFor(s.h.deps);
      await s.h.pumpApp(tester, initialLocation: '/buddies/requests');
      await settle(tester);
      expect(find.text('No incoming requests'), findsOneWidget);
      fakes.requests.setIncoming([incoming('a', 'Ann', s.uid)]);
      await settle(tester);
      expect(find.text('Ann'), findsOneWidget);
      fakes.requests.setIncoming([]);
      await settle(tester);
      expect(find.text('Ann'), findsNothing);
    });

    testWidgets('a stream error shows the message and Try again resubscribes', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([]);
      final fakes = fakeBuddiesBackendFor(s.h.deps);
      await s.h.pumpApp(tester, initialLocation: '/buddies/requests');
      await settle(tester);
      fakes.requests.failIncoming(AppException.fromCallable(code: 'unavailable'));
      await settle(tester);
      expect(find.text('Network problem. Check your connection and try again.'), findsOneWidget);
      fakes.requests.setIncoming([incoming('a', 'Ann', s.uid)]);
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Ann'), findsOneWidget);
    });
  });

  group('My buddies tab', () {
    const bo = BuddySummary(uid: 'bo', displayName: 'Bo Buddy', hostelId: 'agira');
    const cy = BuddySummary(uid: 'cy', displayName: 'Cy Friend');

    Future<void> openMine(WidgetTester tester, ({Harness h, BuddyBackendStub backend, String uid}) s) async {
      await openBuddies(tester, s.h);
      await tester.tap(find.text('My buddies'));
      await settle(tester);
    }

    testWidgets('empty state offers to find buddies', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([studentJson('u1', name: 'Riya Singh')]);
      await openMine(tester, s);
      expect(find.text('No buddies yet'), findsOneWidget);
      await tester.tap(find.text('Find buddies').last);
      await settle(tester);
      expect(find.text('Riya Singh'), findsOneWidget);
    });

    testWidgets('lists the active buddies from the directory, live', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([]);
      final dir = fakeBuddiesBackendFor(s.h.deps).directory;
      dir.setBuddies([bo]);
      await openMine(tester, s);
      expect(find.text('Bo Buddy'), findsOneWidget);
      expect(find.text('Agira Hall'), findsOneWidget);
      dir.setBuddies([bo, cy]);
      await settle(tester);
      expect(find.text('Cy Friend'), findsOneWidget);
      expect(find.text('Challenge'), findsNWidgets(2));
      expect(find.text('Step bet'), findsNWidgets(2));
    });

    testWidgets('Challenge navigates to the buddy-challenge form with ?buddy=', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([]);
      fakeBuddiesBackendFor(s.h.deps).directory.setBuddies([bo]);
      await openMine(tester, s);
      await tester.tap(find.text('Challenge'));
      await settle(tester);
      expect(currentLocation(tester), '/challenges/new-buddy?buddy=bo');
    });

    testWidgets('Step bet navigates to /bets/new?buddy=', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([]);
      fakeBuddiesBackendFor(s.h.deps).directory.setBuddies([bo]);
      await openMine(tester, s);
      await tester.tap(find.text('Step bet'));
      await settle(tester);
      expect(currentLocation(tester), '/bets/new?buddy=bo');
    });

    testWidgets('Remove asks for confirmation, then calls removeBuddy', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([]);
      final dir = fakeBuddiesBackendFor(s.h.deps).directory;
      dir.setBuddies([bo, cy]);
      await openMine(tester, s);

      await tester.tap(find.byTooltip('More options').first);
      await settle(tester);
      await tester.tap(find.text('Remove buddy'));
      await settle(tester);
      expect(find.text('Remove buddy?'), findsOneWidget);
      await tester.tap(find.text('Keep buddy'));
      await settle(tester);
      expect(s.h.functions.callsTo('removeBuddy'), isEmpty);

      await tester.tap(find.byTooltip('More options').first);
      await settle(tester);
      await tester.tap(find.text('Remove buddy'));
      await settle(tester);
      await tester.tap(find.text('Remove'));
      await settle(tester);
      expect(s.h.functions.callsTo('removeBuddy').single.params, {'buddyUid': 'bo'});
      expect(find.text('Bo Buddy was removed from your buddies.'), findsOneWidget);
      expect(find.text('Bo Buddy'), findsNothing);
      expect(find.text('Cy Friend'), findsOneWidget);
    });

    testWidgets('Remove failure keeps the buddy and shows the message', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([]);
      fakeBuddiesBackendFor(s.h.deps).directory.setBuddies([bo]);
      await openMine(tester, s);
      s.h.functions.failNext('removeBuddy', AppException.fromCallable(code: 'unavailable'));
      await tester.tap(find.byTooltip('More options').first);
      await settle(tester);
      await tester.tap(find.text('Remove buddy'));
      await settle(tester);
      await tester.tap(find.text('Remove'));
      await settle(tester);
      expect(find.text('Network problem. Check your connection and try again.'), findsOneWidget);
      expect(find.text('Bo Buddy'), findsOneWidget);
    });

    testWidgets('Report profile from the menu sends reportProfile', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([]);
      fakeBuddiesBackendFor(s.h.deps).directory.setBuddies([bo]);
      await openMine(tester, s);
      await tester.tap(find.byTooltip('More options').first);
      await settle(tester);
      await tester.tap(find.text('Report profile'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('reason_HARASSMENT')));
      await tester.pump();
      await tester.tap(find.text('Send report'));
      await settle(tester);
      expect(s.h.functions.callsTo('reportProfile').single.params,
          {'targetUid': 'bo', 'reason': 'HARASSMENT'});
      expect(find.text('Thanks, your report was sent to the StepUp team.'), findsOneWidget);
    });
  });

  group('narrow 360 px phone', () {
    const longName = 'Bartholomew Maximilian Venkataraghavan Subramaniam';

    void narrow(WidgetTester tester) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 3000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('requests screen and my buddies list do not overflow', (tester) async {
      narrow(tester);
      final s = buddiesSetup([]);
      final fakes = fakeBuddiesBackendFor(s.h.deps);
      fakes.requests.setIncoming([incoming('a', longName, s.uid, message: 'x' * 118)]);
      fakes.requests.setOutgoing([outgoing('c', longName, s.uid)]);
      fakes.directory.setBuddies([const BuddySummary(uid: 'bo', displayName: longName, hostelId: 'vasudha-e')]);
      await s.h.pumpApp(tester, initialLocation: '/buddies/requests');
      await settle(tester);
      expect(find.text(longName), findsOneWidget);
      await tester.tap(find.textContaining('Outgoing'));
      await settle(tester);
      expect(find.text(longName), findsOneWidget);
    });

    testWidgets('my buddies tile with a long name does not overflow', (tester) async {
      narrow(tester);
      final s = buddiesSetup([]);
      fakeBuddiesBackendFor(s.h.deps).directory.setBuddies(
          [const BuddySummary(uid: 'bo', displayName: longName, hostelId: 'vasudha-e')]);
      await openBuddies(tester, s.h);
      await tester.tap(find.text('My buddies'));
      await settle(tester);
      expect(find.text(longName), findsOneWidget);
      expect(find.text('Vasudha Hall - Block E'), findsOneWidget);
    });
  });

  group('Home "buddies available" figure', () {
    testWidgets('is registered and returns the number of active buddies', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([]);
      fakeBuddiesBackendFor(s.h.deps).directory.setBuddies([
        const BuddySummary(uid: 'a', displayName: 'A'),
        const BuddySummary(uid: 'b', displayName: 'B'),
      ]);
      await s.h.pumpApp(tester, initialLocation: '/buddies');
      await settle(tester);
      final activity = await s.h.deps.campusActivity.load(s.uid);
      expect(activity.buddiesAvailable, 2);
    });

    testWidgets('is 0 with no buddies', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([]);
      await s.h.pumpApp(tester, initialLocation: '/buddies');
      await settle(tester);
      expect((await s.h.deps.campusActivity.load(s.uid)).buddiesAvailable, 0);
    });
  });
}

