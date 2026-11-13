/// The signed-in Firebase user as the app sees it (no Firebase types).
class AuthUser {
  const AuthUser({
    required this.uid,
    required this.email,
    required this.emailVerified,
    this.displayName,
    this.photoUrl,
  });

  final String uid;
  final String email;
  final bool emailVerified;
  final String? displayName;
  final String? photoUrl;
}

/// Whether the `users/{uid}` profile exists yet.
enum ProfileStatus {
  /// Not known yet (loading).
  unknown,

  /// Verified user without a profile - needs onboarding.
  missing,

  /// Profile present.
  exists,

  /// Loading the profile failed (retry available on the splash screen).
  error,
}

/// Input of the router redirect guard: everything needed to decide which part
/// of the app the user may see.
class AuthState {
  const AuthState({
    this.initializing = false,
    this.user,
    this.profileStatus = ProfileStatus.unknown,
    this.isAdmin = false,
  });

  /// Auth state not resolved yet (app start).
  const AuthState.initializing() : this(initializing: true);

  const AuthState.signedOut() : this();

  final bool initializing;
  final AuthUser? user;
  final ProfileStatus profileStatus;
  final bool isAdmin;

  bool get isSignedIn => user != null;
  bool get isVerified => user?.emailVerified ?? false;
  bool get isReady => isVerified && profileStatus == ProfileStatus.exists;
}
