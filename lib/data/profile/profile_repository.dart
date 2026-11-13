import '../../domain/profile_draft.dart';
import '../../domain/user_profile.dart';
import '../firestore/firestore_access.dart';
import '../functions/callables.dart';

/// Own profile: a live stream of `users/{uid}` and callable-based mutations.
abstract class ProfileRepository {
  /// Emits `null` while the profile does not exist (onboarding needed).
  Stream<UserProfile?> watchProfile(String uid);

  /// Calls `createProfile` (idempotent on the server).
  Future<void> createProfile(ProfileDraft draft, {String? photoUrl});

  /// Calls `updateProfile` with the changed editable fields only.
  Future<void> updateProfile(Map<String, dynamic> fields);
}

class CallableProfileRepository implements ProfileRepository {
  CallableProfileRepository({required FirestoreAccess firestore, required Callables callables})
      : _firestore = firestore,
        _callables = callables;

  final FirestoreAccess _firestore;
  final Callables _callables;

  @override
  Stream<UserProfile?> watchProfile(String uid) => _firestore.watchUserProfile(uid);

  @override
  Future<void> createProfile(ProfileDraft draft, {String? photoUrl}) =>
      _callables.createProfile(draft, photoUrl: photoUrl);

  @override
  Future<void> updateProfile(Map<String, dynamic> fields) => _callables.updateProfile(fields);
}
