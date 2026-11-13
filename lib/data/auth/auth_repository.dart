import '../../domain/auth_state.dart';

/// Authentication boundary. All failures are thrown as `AppException` with a
/// friendly message. Implementations: `FirebaseAuthRepository`,
/// `FakeAuthRepository` (tests / `AppDependencies.fake()`).
abstract class AuthRepository {
  /// Emits the current user (or null) immediately on listen, then on every
  /// change including e-mail verification after [reloadUser].
  Stream<AuthUser?> get userChanges;

  AuthUser? get currentUser;

  /// Creates an e-mail/password account (domain checked client-side first)
  /// and stores [displayName]. Does not send the verification e-mail.
  Future<AuthUser> register({
    required String email,
    required String password,
    required String displayName,
  });

  Future<AuthUser> signIn({required String email, required String password});

  /// Sends (or re-sends) the verification e-mail to the current user.
  Future<void> sendVerificationEmail();

  /// Reloads the user from the server and refreshes the ID token so that the
  /// `email_verified` claim is picked up. Returns the refreshed user.
  Future<AuthUser?> reloadUser();

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();

  /// Google sign-in. Non-`@thapar.edu` accounts are signed out immediately and
  /// rejected. Only call when `AppConfig.googleSignInEnabled`.
  Future<AuthUser> signInWithGoogle();
}
