import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../firestore/firebase_firestore_access.dart' show convertFirestoreValue;
import 'app_notification.dart';

/// Read-only access to the signed-in user's `notifications` (newest first).
///
/// Pagination is "grow the window": the screen asks for a bigger [limit] and
/// the same live query is re-created, so new notifications and read-state
/// changes stay live without cursors.
///
/// Mutations never happen here: marking read goes through the
/// `markNotificationsRead` callable; the client never deletes notifications.
abstract class NotificationsReader {
  Stream<List<AppNotification>> watchLatest(String uid, {required int limit});
}

/// `notifications` where `uid == me` order by `createdAt` desc, limited.
/// Needs the composite index (uid ASC, createdAt DESC) that is already in
/// `firestore.indexes.json`.
class FirestoreNotificationsReader implements NotificationsReader {
  FirestoreNotificationsReader(this._db);

  final FirebaseFirestore _db;

  @override
  Stream<List<AppNotification>> watchLatest(String uid, {required int limit}) {
    return _db
        .collection('notifications')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (q) => [
            for (final d in q.docs)
              AppNotification.fromMap(
                d.id,
                (convertFirestoreValue(d.data()) as Map).cast<String, dynamic>(),
              ),
          ],
        );
  }
}

/// In-memory reader for tests and fake-mode wiring.
class FakeNotificationsReader implements NotificationsReader {
  FakeNotificationsReader([List<AppNotification> initial = const []]) : _items = List.of(initial);

  List<AppNotification> _items;
  final StreamController<void> _changed = StreamController<void>.broadcast();

  /// When set, every new subscription fails with this error (simulates a
  /// permission / network failure).
  Object? failWith;

  /// Limits requested so far (to assert pagination).
  final List<int> requestedLimits = [];

  void setNotifications(List<AppNotification> items) {
    _items = List.of(items);
    _changed.add(null);
  }

  List<AppNotification> _snapshot(int limit) {
    final sorted = List.of(_items)
      ..sort((a, b) {
        final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });
    return sorted.take(limit).toList(growable: false);
  }

  @override
  Stream<List<AppNotification>> watchLatest(String uid, {required int limit}) {
    requestedLimits.add(limit);
    final error = failWith;
    if (error != null) return Stream<List<AppNotification>>.error(error);
    return Stream<List<AppNotification>>.multi((c) {
      c.add(_snapshot(limit));
      final sub = _changed.stream.listen((_) => c.add(_snapshot(limit)));
      c.onCancel = sub.cancel;
    }, isBroadcast: true);
  }
}
