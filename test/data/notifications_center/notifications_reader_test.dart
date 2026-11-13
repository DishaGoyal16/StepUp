import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/data/notifications_center/app_notification.dart';
import 'package:stepup/data/notifications_center/notifications_reader.dart';

AppNotification n(String id, int minutesAgo, {bool read = false}) => AppNotification(
      id: id,
      type: 'SYSTEM',
      title: id,
      body: '',
      read: read,
      createdAt: DateTime.utc(2026, 11, 13, 6).subtract(Duration(minutes: minutesAgo)),
    );

void main() {
  group('AppNotification.fromMap', () {
    test('parses fields, stringifies data and reads createdAt', () {
      final a = AppNotification.fromMap('u_k', {
        'type': 'CHALLENGE_NEW',
        'title': 'New challenge',
        'body': 'Join now',
        'data': {'challengeId': 'abc', 'n': 5, 'skip': null},
        'read': true,
        'createdAt': DateTime.utc(2026, 11, 13),
      });
      expect(a.id, 'u_k');
      expect(a.type, 'CHALLENGE_NEW');
      expect(a.data, {'challengeId': 'abc', 'n': '5'});
      expect(a.read, isTrue);
      expect(a.createdAt, DateTime.utc(2026, 11, 13));
    });

    test('tolerates a missing/odd document', () {
      final a = AppNotification.fromMap('x', {'data': 'oops', 'createdAt': 'soon'});
      expect(a.type, 'SYSTEM');
      expect(a.title, '');
      expect(a.data, isEmpty);
      expect(a.read, isFalse);
      expect(a.createdAt, isNull);
    });

    test('copyWith only changes read', () {
      final a = n('a', 1).copyWith(read: true);
      expect(a.read, isTrue);
      expect(a.title, 'a');
    });
  });

  group('FakeNotificationsReader', () {
    test('newest first, limited, and live', () async {
      final r = FakeNotificationsReader([n('old', 60), n('new', 1), n('mid', 30)]);
      final seen = <List<String>>[];
      final sub = r.watchLatest('u', limit: 2).listen((l) => seen.add([for (final x in l) x.id]));
      await Future<void>.delayed(Duration.zero);
      expect(seen.single, ['new', 'mid']);
      r.setNotifications([n('newest', 0), n('new', 1), n('mid', 30)]);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, ['newest', 'new']);
      expect(r.requestedLimits, [2]);
      await sub.cancel();
    });

    test('failWith makes the stream error', () {
      final r = FakeNotificationsReader()..failWith = StateError('denied');
      expect(r.watchLatest('u', limit: 5), emitsError(isA<StateError>()));
    });
  });
}
