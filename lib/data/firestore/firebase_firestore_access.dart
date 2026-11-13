import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/daily_step_summary.dart';
import '../../domain/hostel.dart';
import '../../domain/user_profile.dart';
import 'firestore_access.dart';

/// Converts Firestore-specific values (Timestamp) into plain Dart values so
/// the domain layer stays free of Firebase types.
Object? convertFirestoreValue(Object? v) {
  if (v is Timestamp) return v.toDate().toUtc();
  if (v is Map) {
    return {for (final e in v.entries) e.key.toString(): convertFirestoreValue(e.value)};
  }
  if (v is List) return [for (final e in v) convertFirestoreValue(e)];
  return v;
}

Map<String, dynamic> _data(DocumentSnapshot<Map<String, dynamic>> s) =>
    (convertFirestoreValue(s.data() ?? const {}) as Map).cast<String, dynamic>();

class FirebaseFirestoreAccess implements FirestoreAccess {
  FirebaseFirestoreAccess(this._db);

  final FirebaseFirestore _db;

  @override
  Stream<UserProfile?> watchUserProfile(String uid) =>
      _db.collection('users').doc(uid).snapshots().map(
            (s) => s.exists ? UserProfile.fromMap(uid, _data(s)) : null,
          );

  @override
  Stream<List<DailyStepSummary>> watchDailySummaries(String uid, {int limit = 30}) => _db
      .collection('dailyStepSummaries')
      .where('uid', isEqualTo: uid)
      .orderBy('dayKey', descending: true)
      .limit(limit)
      .snapshots()
      .map((q) => [for (final d in q.docs) DailyStepSummary.fromMap(_data(d))]);

  @override
  Future<List<Hostel>> fetchActiveHostels() async {
    final q = await _db.collection('hostels').where('active', isEqualTo: true).get();
    final list = [for (final d in q.docs) Hostel.fromMap(d.id, _data(d))]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  @override
  Stream<int> watchUnreadNotificationCount(String uid) => _db
      .collection('notifications')
      .where('uid', isEqualTo: uid)
      .where('read', isEqualTo: false)
      .snapshots()
      .map((q) => q.size);
}
