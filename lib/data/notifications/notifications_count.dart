import '../firestore/firestore_access.dart';

/// Source of the unread-notification badge on Home. The notifications
/// engineer may replace the implementation; the default reads the own unread
/// `notifications` documents.
abstract class NotificationsCount {
  Stream<int> watchUnread(String uid);
}

/// Always zero (fakes / backend unavailable).
class ZeroNotificationsCount implements NotificationsCount {
  const ZeroNotificationsCount();

  @override
  Stream<int> watchUnread(String uid) => Stream.value(0);
}

class FirestoreNotificationsCount implements NotificationsCount {
  FirestoreNotificationsCount(this._firestore);

  final FirestoreAccess _firestore;

  @override
  Stream<int> watchUnread(String uid) => _firestore.watchUnreadNotificationCount(uid);
}
