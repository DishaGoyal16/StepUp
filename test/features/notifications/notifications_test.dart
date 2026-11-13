import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/data/functions/callables.dart';
import 'package:stepup/data/functions/fake_functions_client.dart';
import 'package:stepup/data/notifications_center/app_notification.dart';
import 'package:stepup/data/notifications_center/notifications_reader.dart';
import 'package:stepup/features/notifications/notification_routing.dart';
import 'package:stepup/features/notifications/notifications_view_model.dart';

import '../profile/profile_test_support.dart';

final DateTime _now = DateTime.utc(2026, 11, 13, 6);

AppNotification notif(
  String id, {
  String type = 'SYSTEM',
  int minutesAgo = 1,
  bool read = false,
  Map<String, String> data = const {},
  String? title,
}) =>
    AppNotification(
      id: id,
      type: type,
      title: title ?? 'Title $id',
      body: 'Body $id',
      data: data,
      read: read,
      createdAt: _now.subtract(Duration(minutes: minutesAgo)),
    );

void main() {
  group('notificationRoute', () {
    test('maps every type to its destination', () {
      String? r(String type, [Map<String, String> data = const {}]) =>
          notificationRoute(notif('a', type: type, data: data));
      expect(r('BUDDY_REQUEST'), '/buddies/requests');
      expect(r('BUDDY_ACCEPTED'), '/buddies');
      expect(r('CHALLENGE_NEW', {'challengeId': 'c1'}), '/challenges/c1');
      expect(r('CHALLENGE_REMINDER', {'challengeId': 'c2'}), '/challenges/c2');
      expect(r('CHALLENGE_DONE', {'challengeId': 'c3'}), '/challenges/c3');
      expect(r('BET_INVITE', {'betId': 'b1'}), '/bets/b1');
      expect(r('BET_RESULT', {'betId': 'b2'}), '/bets/b2');
      expect(r('LEADERBOARD'), '/leaderboard');
      expect(r('HOSTEL_RESULT'), '/leaderboard');
    });

    test('falls back to the list when the id is missing; informational types open nothing', () {
      expect(notificationRoute(notif('a', type: 'CHALLENGE_NEW')), '/challenges');
      expect(notificationRoute(notif('a', type: 'BET_RESULT', data: {'betId': ' '})), '/bets');
      expect(notificationRoute(notif('a', type: 'SYSTEM')), isNull);
      expect(notificationRoute(notif('a', type: 'SYSTEM', data: {'badgeId': 'FIRST_1K'})), '/profile');
      expect(notificationRoute(notif('a', type: 'SOMETHING_NEW')), isNull);
    });
  });

  test('formatNotificationTime', () {
    String f(Duration ago) => formatNotificationTime(_now.subtract(ago), _now);
    expect(f(const Duration(seconds: 20)), 'just now');
    expect(f(const Duration(minutes: 5)), '5 min ago');
    expect(f(const Duration(hours: 3)), '3 h ago');
    expect(f(const Duration(hours: 30)), 'Yesterday');
    expect(f(const Duration(days: 5)), '8 Nov');
    expect(formatNotificationTime(null, _now), '');
  });

  group('NotificationsViewModel', () {
    late FakeNotificationsReader reader;
    late FakeFunctionsClient fn;
    late NotificationsViewModel vm;

    NotificationsViewModel make({int pageSize = 20}) {
      vm = NotificationsViewModel(
        uid: 'u1',
        reader: reader,
        callables: Callables(fn),
        pageSize: pageSize,
      )..start();
      return vm;
    }

    setUp(() {
      fn = FakeFunctionsClient()..on('markNotificationsRead', (_) => {'ok': true});
    });

    tearDown(() => vm.dispose());

    test('loads newest first and counts unread', () async {
      reader = FakeNotificationsReader([notif('a', minutesAgo: 30), notif('b', minutesAgo: 1, read: true)]);
      make();
      expect(vm.loading, isTrue);
      await pumpEventQueue();
      expect(vm.loading, isFalse);
      expect(vm.items.map((n) => n.id).toList(), ['b', 'a']);
      expect(vm.unreadCount, 1);
      expect(vm.hasMore, isFalse);
    });

    test('markRead is optimistic and calls markNotificationsRead with the id', () async {
      reader = FakeNotificationsReader([notif('a'), notif('b', minutesAgo: 2)]);
      make();
      await pumpEventQueue();
      final f = vm.markRead('a');
      expect(vm.unreadCount, 1, reason: 'optimistic before the server answers');
      await f;
      expect(fn.callsTo('markNotificationsRead').single.params, {
        'ids': ['a'],
      });
      expect(vm.unreadCount, 1);
      // already read -> no second call
      await vm.markRead('a');
      expect(fn.callsTo('markNotificationsRead'), hasLength(1));
    });

    test('markRead failure reverts and reports the AppException message', () async {
      reader = FakeNotificationsReader([notif('a')]);
      make();
      await pumpEventQueue();
      fn.failNext('markNotificationsRead', AppException.fromCallable(code: 'unavailable'));
      await vm.markRead('a');
      expect(vm.unreadCount, 1, reason: 'rolled back');
      expect(vm.takeActionError(), contains('Network problem'));
      expect(vm.takeActionError(), isNull, reason: 'one-shot');
    });

    test('markAllRead sends no ids (= all) and marks everything read', () async {
      reader = FakeNotificationsReader([notif('a'), notif('b', minutesAgo: 2), notif('c', read: true, minutesAgo: 3)]);
      make();
      await pumpEventQueue();
      await vm.markAllRead();
      expect(fn.callsTo('markNotificationsRead').single.params, isEmpty);
      expect(vm.unreadCount, 0);
    });

    test('markAllRead failure restores unread state', () async {
      reader = FakeNotificationsReader([notif('a'), notif('b', minutesAgo: 2)]);
      make();
      await pumpEventQueue();
      fn.failNext('markNotificationsRead', AppException.fromCallable(code: 'permission-denied'));
      await vm.markAllRead();
      expect(vm.unreadCount, 2);
      expect(vm.takeActionError(), isNotNull);
      expect(vm.marking, isFalse);
    });

    test('loadMore grows the window by one page and stops at the end', () async {
      reader = FakeNotificationsReader([for (var i = 0; i < 5; i++) notif('n$i', minutesAgo: i + 1)]);
      make(pageSize: 2);
      await pumpEventQueue();
      expect(vm.items, hasLength(2));
      expect(vm.hasMore, isTrue);
      vm.loadMore();
      await pumpEventQueue();
      expect(vm.items, hasLength(4));
      vm.loadMore();
      await pumpEventQueue();
      expect(vm.items, hasLength(5));
      expect(vm.hasMore, isFalse);
      expect(reader.requestedLimits, [2, 4, 6]);
    });

    test('a failing stream shows failed; retry recovers', () async {
      reader = FakeNotificationsReader([notif('a')])..failWith = StateError('denied');
      make();
      await pumpEventQueue();
      expect(vm.failed, isTrue);
      expect(vm.loading, isFalse);
      reader.failWith = null;
      vm.retry();
      await pumpEventQueue();
      expect(vm.failed, isFalse);
      expect(vm.items, hasLength(1));
    });
  });

  group('NotificationsScreen', () {
    testWidgets('unread items are highlighted; read ones are not', (tester) async {
      final env = ProfileEnv(
        notifications: FakeNotificationsReader([
          notif('a', title: 'Buddy request from Riya', type: 'BUDDY_REQUEST'),
          notif('b', title: 'Old news', read: true, minutesAgo: 90),
        ]),
      );
      await env.pump(tester, initial: '/notifications');
      expect(find.text('Buddy request from Riya'), findsOneWidget);
      expect(find.text('Old news'), findsOneWidget);
      expect(find.byKey(const ValueKey('unread-dot')), findsOneWidget);
      expect(find.text('Mark all read'), findsOneWidget);
    });

    testWidgets('cannot be swiped away or deleted', (tester) async {
      final env = ProfileEnv(notifications: FakeNotificationsReader([notif('a'), notif('b', minutesAgo: 5)]));
      await env.pump(tester, initial: '/notifications');
      expect(find.byType(Dismissible), findsNothing);
      expect(find.byIcon(Icons.delete), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('tapping a challenge notification marks it read and opens the challenge', (tester) async {
      final env = ProfileEnv(
        notifications: FakeNotificationsReader([
          notif('a', title: 'New challenge', type: 'CHALLENGE_NEW', data: {'challengeId': 'ch42'}),
        ]),
      );
      env.functions.on('markNotificationsRead', (_) => {'ok': true});
      await env.pump(tester, initial: '/notifications');
      await tester.tap(find.text('New challenge'));
      await settle(tester);
      expect(find.text('STUB /challenges/ch42'), findsOneWidget);
      expect(env.functions.callsTo('markNotificationsRead').single.params, {
        'ids': ['a'],
      });
    });

    testWidgets('buddy request, bet and leaderboard notifications navigate correctly', (tester) async {
      final cases = <(String, String, Map<String, String>, String)>[
        ('BUDDY_REQUEST', 'Req', {}, 'STUB /buddies/requests'),
        ('BUDDY_ACCEPTED', 'Acc', {}, 'STUB /buddies'),
        ('BET_INVITE', 'Bet', {'betId': 'bb1'}, 'STUB /bets/bb1'),
        ('LEADERBOARD', 'Lead', {}, 'STUB /leaderboard'),
        ('HOSTEL_RESULT', 'Host', {}, 'STUB /leaderboard'),
      ];
      for (final c in cases) {
        final env = ProfileEnv(
          notifications: FakeNotificationsReader([notif('a', type: c.$1, title: c.$2, data: c.$3)]),
        );
        env.functions.on('markNotificationsRead', (_) => {'ok': true});
        await env.pump(tester, initial: '/notifications');
        await tester.tap(find.text(c.$2));
        await settle(tester);
        expect(find.text(c.$4), findsOneWidget, reason: c.$1);
      }
    });

    testWidgets('an informational SYSTEM notification is marked read but goes nowhere', (tester) async {
      final env = ProfileEnv(notifications: FakeNotificationsReader([notif('a', title: 'Heads up')]));
      env.functions.on('markNotificationsRead', (_) => {'ok': true});
      await env.pump(tester, initial: '/notifications');
      await tester.tap(find.text('Heads up'));
      await settle(tester);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.byKey(const ValueKey('unread-dot')), findsNothing);
      expect(env.functions.callsTo('markNotificationsRead'), hasLength(1));
    });

    testWidgets('Mark all read clears the highlight and disables the button', (tester) async {
      final env = ProfileEnv(notifications: FakeNotificationsReader([notif('a'), notif('b', minutesAgo: 4)]));
      env.functions.on('markNotificationsRead', (_) => {'ok': true});
      await env.pump(tester, initial: '/notifications');
      expect(find.byKey(const ValueKey('unread-dot')), findsNWidgets(2));
      await tester.tap(find.text('Mark all read'));
      await settle(tester);
      expect(find.byKey(const ValueKey('unread-dot')), findsNothing);
      expect(env.functions.callsTo('markNotificationsRead').single.params, isEmpty);
      final btn = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Mark all read'));
      expect(btn.onPressed, isNull);
    });

    testWidgets('a failed mark-read shows an error snackbar and keeps the item unread', (tester) async {
      final env = ProfileEnv(notifications: FakeNotificationsReader([notif('a', title: 'Heads up')]));
      env.functions.failNext('markNotificationsRead', AppException.fromCallable(code: 'unavailable'));
      await env.pump(tester, initial: '/notifications');
      await tester.tap(find.text('Heads up'));
      await settle(tester);
      expect(find.textContaining('Network problem'), findsOneWidget);
      expect(find.byKey(const ValueKey('unread-dot')), findsOneWidget);
    });

    testWidgets('empty state', (tester) async {
      final env = ProfileEnv();
      await env.pump(tester, initial: '/notifications');
      expect(find.text('No notifications yet'), findsOneWidget);
      final btn = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Mark all read'));
      expect(btn.onPressed, isNull);
    });

    testWidgets('error state with retry', (tester) async {
      final reader = FakeNotificationsReader([notif('a', title: 'Back again')])..failWith = StateError('x');
      final env = ProfileEnv(notifications: reader);
      await env.pump(tester, initial: '/notifications');
      expect(find.text('Could not load your notifications.'), findsOneWidget);
      reader.failWith = null;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Back again'), findsOneWidget);
    });

    testWidgets('paginates with "Load older"', (tester) async {
      final reader = FakeNotificationsReader([
        for (var i = 0; i < 25; i++) notif('n$i', title: 'Item $i', minutesAgo: i + 1, read: true),
      ]);
      final env = ProfileEnv(notifications: reader);
      await env.pump(tester, initial: '/notifications');
      expect(find.text('Item 0'), findsOneWidget);
      expect(find.text('Item 24'), findsNothing, reason: 'first page is 20');
      await tapVisible(tester, find.text('Load older'));
      expect(find.text('Item 24'), findsOneWidget);
      expect(find.text('Load older'), findsNothing);
    });
  });
}
