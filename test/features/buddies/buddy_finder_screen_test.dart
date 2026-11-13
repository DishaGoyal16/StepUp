import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/features/buddies/buddy_profile_sheet.dart';

import '../../support/harness.dart';
import 'buddies_test_support.dart';

Finder inSheet(Finder f) => find.descendant(of: find.byType(BuddyProfileSheet), matching: f);

void main() {
  group('student cards', () {
    testWidgets('show public data only: hostel and weekly steps only when shared, never e-mail',
        (tester) async {
      useTallView(tester);
      final s = buddiesSetup([
        studentJson('u1', name: 'Riya Singh', bio: 'Loves 5 am runs'),
        studentJson('u2', name: 'Karan Mehta', hostelId: null, weeklySteps: null, bio: ''),
      ]);
      await openBuddies(tester, s.h);

      expect(find.text('Riya Singh'), findsOneWidget);
      expect(find.text('Karan Mehta'), findsOneWidget);
      expect(find.text('Agira Hall'), findsOneWidget, reason: 'only Riya shares her hostel');
      expect(find.text('12,345 verified steps this week'), findsOneWidget,
          reason: 'only Riya shares her steps');
      expect(find.text('Loves 5 am runs'), findsOneWidget);
      expect(find.text('Intermediate'), findsNWidgets(2));
      expect(find.text('Running'), findsNWidgets(2), reason: 'sport chips');
      expect(find.text('Running · Morning'), findsNWidgets(2), reason: 'preferred activity');
      expect(find.textContaining('@'), findsNothing, reason: 'never an e-mail');
      expect(find.textContaining('thapar.edu'), findsNothing);
      expect(find.textContaining('ocation'), findsNothing);
    });

    testWidgets('actions follow the relation of every student', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([
        studentJson('none', name: 'Nina None'),
        studentJson('sent', name: 'Sam Sent', relation: 'REQUEST_SENT'),
        studentJson('recv', name: 'Ria Received', relation: 'REQUEST_RECEIVED'),
        studentJson('bud', name: 'Bo Buddy', relation: 'BUDDY'),
      ]);
      await openBuddies(tester, s.h);

      expect(find.text('Send Buddy Request'), findsOneWidget);
      expect(find.text('Cancel request'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget, reason: 'badge of the sent request');
      expect(find.text('Wants to connect'), findsOneWidget);
      expect(find.text('Buddy'), findsOneWidget, reason: 'badge of the existing buddy');
    });

    testWidgets('fit a narrow 360 px phone without overflow (long names, all relations)',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 5000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const longName = 'Bartholomew Maximilian Venkataraghavan Subramaniam';
      final s = buddiesSetup([
        studentJson('a', name: longName, sports: ['Cricket', 'Football', 'Basketball', 'Badminton', 'Volleyball', 'Tennis']),
        studentJson('b', name: longName, relation: 'REQUEST_RECEIVED'),
        studentJson('c', name: longName, relation: 'REQUEST_SENT'),
        studentJson('d', name: longName, relation: 'BUDDY'),
      ]);
      await openBuddies(tester, s.h);
      expect(find.text(longName), findsNWidgets(4));
      expect(find.text('+2'), findsOneWidget, reason: 'sports beyond four are summarised');
    });

    testWidgets('empty list shows a friendly empty state', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([]);
      await openBuddies(tester, s.h);
      expect(find.text('No students found'), findsOneWidget);
      expect(find.textContaining('discoverable yet'), findsOneWidget);
    });
  });

  group('send / cancel / respond', () {
    testWidgets('Send Buddy Request asks for an optional message, calls the callable, shows Pending',
        (tester) async {
      useTallView(tester);
      final s = buddiesSetup([studentJson('u1', name: 'Riya Singh')]);
      await openBuddies(tester, s.h);

      await tester.tap(find.text('Send Buddy Request'));
      await settle(tester);
      expect(find.text('Send request to Riya Singh'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('requestMessageField')), 'Let us run together');
      await tester.tap(find.text('Send request'));
      await settle(tester);

      final call = s.h.functions.callsTo('sendBuddyRequest').single;
      expect(call.params, {'toUid': 'u1', 'message': 'Let us run together'});
      expect(find.text('Buddy request sent to Riya Singh.'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Cancel request'), findsOneWidget);
      expect(find.text('Send Buddy Request'), findsNothing);
    });

    testWidgets('the message is optional and cancelling the dialog sends nothing', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([studentJson('u1', name: 'Riya Singh')]);
      await openBuddies(tester, s.h);

      await tester.tap(find.text('Send Buddy Request'));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(s.h.functions.callsTo('sendBuddyRequest'), isEmpty);

      await tester.tap(find.text('Send Buddy Request'));
      await settle(tester);
      await tester.tap(find.text('Send request'));
      await settle(tester);
      expect(s.h.functions.callsTo('sendBuddyRequest').single.params, {'toUid': 'u1'});
    });

    testWidgets('a server rejection shows the friendly reason and keeps the button', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([studentJson('u1', name: 'Riya Singh')]);
      await openBuddies(tester, s.h);
      s.h.functions.failNext(
        'sendBuddyRequest',
        AppException.fromCallable(
          code: 'resource-exhausted',
          message: 'try again later',
          details: {'reason': 'REQUEST_COOLDOWN'},
        ),
      );
      await tester.tap(find.text('Send Buddy Request'));
      await settle(tester);
      await tester.tap(find.text('Send request'));
      await settle(tester);
      expect(find.text('You can send this student another request a little later.'), findsOneWidget);
      expect(find.text('Send Buddy Request'), findsOneWidget);
      expect(find.text('Pending'), findsNothing);
    });

    testWidgets('offline failure shows the network message', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([studentJson('u1', name: 'Riya Singh')]);
      await openBuddies(tester, s.h);
      s.h.functions.failNext('sendBuddyRequest', AppException.fromCallable(code: 'unavailable'));
      await tester.tap(find.text('Send Buddy Request'));
      await settle(tester);
      await tester.tap(find.text('Send request'));
      await settle(tester);
      expect(find.text('Network problem. Check your connection and try again.'), findsOneWidget);
    });

    testWidgets('Cancel request calls cancelBuddyRequest with {me}_{them}', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([studentJson('u1', name: 'Riya Singh', relation: 'REQUEST_SENT')]);
      await openBuddies(tester, s.h);
      await tester.tap(find.text('Cancel request'));
      await settle(tester);
      expect(s.h.functions.callsTo('cancelBuddyRequest').single.params,
          {'requestId': '${s.uid}_u1'});
      expect(find.text('Request to Riya Singh cancelled.'), findsOneWidget);
      expect(find.text('Send Buddy Request'), findsOneWidget);
    });

    testWidgets('Accept and Reject call respondBuddyRequest', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([
        studentJson('a', name: 'Ann', relation: 'REQUEST_RECEIVED'),
        studentJson('b', name: 'Bea', relation: 'REQUEST_RECEIVED'),
      ]);
      await openBuddies(tester, s.h);
      await tester.tap(find.text('Accept').first);
      await settle(tester);
      expect(s.h.functions.callsTo('respondBuddyRequest').single.params,
          {'requestId': 'a_${s.uid}', 'accept': true});
      expect(find.text('You and Ann are now buddies.'), findsOneWidget);
      expect(find.text('Buddy'), findsOneWidget);

      await tester.tap(find.text('Reject'));
      await settle(tester);
      final second = s.h.functions.callsTo('respondBuddyRequest').toList()[1];
      expect(second.params, {'requestId': 'b_${s.uid}', 'accept': false});
      expect(find.text('Send Buddy Request'), findsOneWidget, reason: 'Bea is a stranger again');
    });
  });

  group('search, filters and paging', () {
    testWidgets('typing is debounced and calls searchBuddies with the query', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([
        studentJson('u1', name: 'Riya Singh'),
        studentJson('u2', name: 'Karan Mehta'),
      ]);
      await openBuddies(tester, s.h);
      final before = s.h.functions.callsTo('searchBuddies').length;

      await tester.enterText(find.byKey(const Key('buddySearchField')), 'riy');
      await tester.pump(const Duration(milliseconds: 150));
      expect(s.h.functions.callsTo('searchBuddies').length, before, reason: 'still debouncing');
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);

      final calls = s.h.functions.callsTo('searchBuddies').toList();
      expect(calls.length, before + 1);
      expect(calls.last.params['query'], 'riy');
      expect(find.text('Riya Singh'), findsOneWidget);
      expect(find.text('Karan Mehta'), findsNothing);
    });

    testWidgets('no match -> empty state with a clear-filters action', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([studentJson('u1', name: 'Riya Singh')]);
      await openBuddies(tester, s.h);
      await tester.enterText(find.byKey(const Key('buddySearchField')), 'zzz');
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
      expect(find.text('No students found'), findsOneWidget);
      expect(find.text('Try a different name or remove some filters.'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await settle(tester);
      expect(find.text('Riya Singh'), findsOneWidget);
      expect(s.h.functions.callsTo('searchBuddies').last.params.containsKey('query'), isFalse);
    });

    testWidgets('filter sheet: level + sport + hostel are sent to searchBuddies', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([
        studentJson('u1', name: 'Riya Singh', fitnessLevel: 'BEGINNER', sports: ['Cricket']),
        studentJson('u2', name: 'Karan Mehta', fitnessLevel: 'ADVANCED', sports: ['Gym']),
      ]);
      await openBuddies(tester, s.h);

      await tester.tap(find.byKey(const Key('openFilters')));
      await settle(tester);
      expect(find.text('Filters'), findsOneWidget);
      for (final label in [
        'Fitness level',
        'Sports',
        'Hostel',
        'Preferred activity time',
        'Fitness goals',
        'Available on',
        'Buddy type',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.widgetWithText(ChoiceChip, 'Beginner'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, 'Cricket'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, 'Mon'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Group'));
      await tester.pump();
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await settle(tester);
      await tester.tap(find.text('Agira Hall').last);
      await settle(tester);
      await tester.tap(find.text('Apply 5 filters'));
      await settle(tester);

      final params = s.h.functions.callsTo('searchBuddies').last.params;
      expect(params['fitnessLevel'], 'BEGINNER');
      expect(params['sports'], ['Cricket']);
      expect(params['hostelId'], 'agira');
      expect(params['availability'], ['MON']);
      expect(params['buddyType'], 'GROUP');
      expect(find.text('Riya Singh'), findsOneWidget, reason: 'beginner + cricket + agira');
      expect(find.text('Karan Mehta'), findsNothing);
      expect(find.widgetWithText(InputChip, 'Beginner'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Agira Hall'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Mon'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Group'), findsOneWidget);
    });

    testWidgets('active filters show as chips and can be removed or cleared', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([
        studentJson('u1', name: 'Riya Singh', fitnessLevel: 'BEGINNER'),
        studentJson('u2', name: 'Karan Mehta', fitnessLevel: 'ADVANCED'),
      ]);
      await openBuddies(tester, s.h);
      await tester.tap(find.byKey(const Key('openFilters')));
      await settle(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Beginner'));
      await tester.pump();
      await tester.tap(find.text('Apply 1 filter'));
      await settle(tester);
      expect(find.text('Riya Singh'), findsOneWidget);
      expect(find.text('Karan Mehta'), findsNothing);
      expect(find.widgetWithText(InputChip, 'Beginner'), findsOneWidget);

      // remove the chip
      await tester.tap(find.descendant(
        of: find.widgetWithText(InputChip, 'Beginner'),
        matching: find.byType(Icon),
      ));
      await settle(tester);
      expect(find.text('Karan Mehta'), findsOneWidget);
      expect(s.h.functions.callsTo('searchBuddies').last.params.containsKey('fitnessLevel'), isFalse);
    });

    testWidgets('"Load more" fetches the next page with the cursor', (tester) async {
      useTallView(tester, height: 30000);
      final s = buddiesSetup([
        for (var i = 0; i < 25; i++) studentJson('u$i', name: 'Student ${i.toString().padLeft(2, '0')}'),
      ]);
      await openBuddies(tester, s.h);
      expect(find.text('Student 19'), findsOneWidget);
      expect(find.text('Student 20'), findsNothing);
      expect(find.text('Load more'), findsOneWidget);

      await tester.tap(find.text('Load more'));
      await settle(tester);
      final calls = s.h.functions.callsTo('searchBuddies').toList();
      expect(calls.last.params['cursor'], '20');
      expect(find.text('Student 24'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      expect(find.text('That is everyone for now.'), findsOneWidget);
    });

    testWidgets('scrolling to the end loads the next page automatically', (tester) async {
      final s = buddiesSetup([
        for (var i = 0; i < 25; i++) studentJson('u$i', name: 'Student ${i.toString().padLeft(2, '0')}'),
      ]);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openBuddies(tester, s.h);
      expect(s.h.functions.callsTo('searchBuddies').length, 1);

      await tester.dragUntilVisible(
        find.text('Student 19'),
        find.byType(Scrollable).last,
        const Offset(0, -300),
      );
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -2000));
      await settle(tester);
      expect(s.h.functions.callsTo('searchBuddies').length, 2);
      expect(s.h.functions.callsTo('searchBuddies').last.params['cursor'], '20');
    });
  });

  group('offline / errors', () {
    testWidgets('first load failure shows the message and Try again recovers', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([studentJson('u1', name: 'Riya Singh')]);
      s.h.functions.failNext('searchBuddies', AppException.fromCallable(code: 'unavailable'));
      await openBuddies(tester, s.h);
      expect(find.text('Network problem. Check your connection and try again.'), findsOneWidget);
      expect(find.text('Riya Singh'), findsNothing);

      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Riya Singh'), findsOneWidget);
    });

    testWidgets('a failing "Load more" keeps the list and offers a retry', (tester) async {
      useTallView(tester, height: 30000);
      final s = buddiesSetup([
        for (var i = 0; i < 22; i++) studentJson('u$i', name: 'Student ${i.toString().padLeft(2, '0')}'),
      ]);
      await openBuddies(tester, s.h);
      s.h.functions.failNext('searchBuddies', AppException.fromCallable(code: 'unavailable'));
      await tester.tap(find.text('Load more'));
      await settle(tester);
      expect(find.text('Student 05'), findsOneWidget, reason: 'list kept');
      expect(find.text('Network problem. Check your connection and try again.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Student 21'), findsOneWidget);
    });
  });

  group('profile sheet', () {
    testWidgets('View profile shows the full public profile and the same actions', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([
        studentJson(
          'u1',
          name: 'Riya Singh',
          bio: 'Early riser who loves cricket nets',
          sports: ['Cricket', 'Yoga'],
          goals: ['Stay active', 'Compete'],
          availability: ['SAT', 'MON'],
          buddyType: 'GROUP',
        ),
      ]);
      await openBuddies(tester, s.h);
      await tester.tap(find.text('View profile'));
      await settle(tester);

      expect(find.byType(BuddyProfileSheet), findsOneWidget);
      expect(inSheet(find.text('Riya Singh')), findsOneWidget);
      expect(inSheet(find.text('Agira Hall')), findsOneWidget);
      expect(inSheet(find.text('About')), findsOneWidget);
      expect(inSheet(find.text('Early riser who loves cricket nets')), findsOneWidget);
      expect(inSheet(find.text('Cricket')), findsOneWidget);
      expect(inSheet(find.text('Yoga')), findsOneWidget);
      expect(inSheet(find.text('Fitness goals')), findsOneWidget);
      expect(inSheet(find.text('Compete')), findsOneWidget);
      expect(inSheet(find.text('Available on')), findsOneWidget);
      expect(inSheet(find.text('Mon')), findsOneWidget);
      expect(inSheet(find.text('Sat')), findsOneWidget);
      expect(inSheet(find.text('Group')), findsOneWidget);
      expect(inSheet(find.text('12,345 verified steps this week')), findsOneWidget);
      expect(inSheet(find.textContaining('@')), findsNothing);

      // send from the sheet: snackbar inside the sheet and the sheet updates live
      await tester.tap(inSheet(find.text('Send Buddy Request')));
      await settle(tester);
      await tester.tap(find.text('Send request'));
      await settle(tester);
      expect(s.h.functions.callsTo('sendBuddyRequest').single.params['toUid'], 'u1');
      expect(find.text('Buddy request sent to Riya Singh.'), findsOneWidget);
      expect(inSheet(find.text('Cancel request')), findsOneWidget);
    });

    testWidgets('a buddy\'s sheet has Remove (with confirmation) and the shortcuts', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([studentJson('u1', name: 'Riya Singh', relation: 'BUDDY')]);
      await openBuddies(tester, s.h);
      await tester.tap(find.text('View profile'));
      await settle(tester);
      expect(inSheet(find.text('Buddy')), findsOneWidget);
      expect(inSheet(find.text('Challenge')), findsOneWidget);
      expect(inSheet(find.text('Step bet')), findsOneWidget);

      await tester.tap(inSheet(find.text('Remove buddy')));
      await settle(tester);
      expect(find.text('Remove buddy?'), findsOneWidget);
      await tester.tap(find.text('Keep buddy'));
      await settle(tester);
      expect(s.h.functions.callsTo('removeBuddy'), isEmpty, reason: 'declined');

      await tester.tap(inSheet(find.text('Remove buddy')));
      await settle(tester);
      await tester.tap(find.text('Remove'));
      await settle(tester);
      expect(s.h.functions.callsTo('removeBuddy').single.params, {'buddyUid': 'u1'});
      expect(find.text('Riya Singh was removed from your buddies.'), findsOneWidget);
      expect(inSheet(find.text('Send Buddy Request')), findsOneWidget);
    });

    testWidgets('Report profile: reason picker then reportProfile', (tester) async {
      useTallView(tester);
      final s = buddiesSetup([studentJson('u1', name: 'Riya Singh')]);
      await openBuddies(tester, s.h);
      await tester.tap(find.text('View profile'));
      await settle(tester);
      await tester.tap(inSheet(find.text('Report profile')));
      await settle(tester);

      expect(find.text('Report Riya Singh'), findsOneWidget);
      final send = find.widgetWithText(FilledButton, 'Send report');
      expect(tester.widget<FilledButton>(send).onPressed, isNull, reason: 'a reason is required');
      await tester.tap(find.byKey(const Key('reason_FAKE_PROFILE')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('reportDetailsField')), 'Not a real student');
      await tester.tap(send);
      await settle(tester);

      expect(s.h.functions.callsTo('reportProfile').single.params, {
        'targetUid': 'u1',
        'reason': 'FAKE_PROFILE',
        'details': 'Not a real student',
      });
      expect(find.text('Thanks, your report was sent to the StepUp team.'), findsOneWidget);
    });
  });
}
