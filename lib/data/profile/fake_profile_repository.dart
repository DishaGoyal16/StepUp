import '../../core/errors/app_exception.dart';
import '../../domain/profile_draft.dart';
import '../../domain/user_profile.dart';
import '../auth/auth_repository.dart';
import '../firestore/fake_firestore_access.dart';
import 'profile_repository.dart';

/// In-memory [ProfileRepository]. `createProfile` builds the profile for the
/// currently signed-in fake user, like the real callable would.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({required AuthRepository auth, UserProfile? initial})
      : _auth = auth,
        _profile = ReplayValue(initial);

  final AuthRepository _auth;
  final ReplayValue<UserProfile?> _profile;

  int createCalls = 0;
  ProfileDraft? lastDraft;
  String? lastPhotoUrl;

  /// Error thrown once by the next [createProfile].
  Object? failNextCreateWith;

  void setProfile(UserProfile? p) => _profile.value = p;

  @override
  Stream<UserProfile?> watchProfile(String uid) => _profile.stream;

  @override
  Future<void> createProfile(ProfileDraft draft, {String? photoUrl}) async {
    createCalls++;
    lastDraft = draft;
    lastPhotoUrl = photoUrl;
    final err = failNextCreateWith;
    if (err != null) {
      failNextCreateWith = null;
      throw err;
    }
    final user = _auth.currentUser;
    if (user == null) {
      throw const AppException(code: 'unauthenticated', message: 'Please sign in again.');
    }
    _profile.value = UserProfile(
      uid: user.uid,
      displayName: draft.displayName.trim(),
      email: user.email,
      hostelId: draft.hostelId ?? '',
      block: draft.block.isEmpty ? null : draft.block,
      fitnessLevel: draft.fitnessLevel,
      sportsInterests: draft.sportsInterests,
      preferredActivity: draft.preferredActivity,
      preferredTime: draft.preferredTime,
      buddyType: draft.buddyType,
      bio: draft.bio,
      photoUrl: photoUrl,
    );
  }

  @override
  Future<void> updateProfile(Map<String, dynamic> fields) async {}
}
