import '../../domain/daily_step_summary.dart';
import '../../domain/hostel.dart';
import '../../domain/user_profile.dart';

/// Typed, read-only access to the Firestore documents the foundation needs.
/// Clients NEVER write to Firestore (see DATABASE_SCHEMA.md); all mutations
/// are callables.
///
/// Feature engineers add their own small reader interfaces under
/// `lib/data/<feature>/`; they can build Firebase implementations from
/// `AppDependencies.rawFirestore` (null in fake mode).
abstract class FirestoreAccess {
  /// Own `users/{uid}` document; `null` while the profile does not exist.
  Stream<UserProfile?> watchUserProfile(String uid);

  /// Own `dailyStepSummaries` (where uid == [uid] order by dayKey desc).
  Stream<List<DailyStepSummary>> watchDailySummaries(String uid, {int limit = 30});

  /// Active hostels from the `hostels` collection (sorted by `sortOrder`).
  Future<List<Hostel>> fetchActiveHostels();

  /// Number of own unread `notifications`.
  Stream<int> watchUnreadNotificationCount(String uid);
}
