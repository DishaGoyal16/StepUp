import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../domain/auth_state.dart';
import '../../domain/thapar_email.dart';
import 'auth_errors.dart';
import 'auth_repository.dart';

/// Firebase Auth implementation of [AuthRepository].
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({required AppConfig config, FirebaseAuth? auth, GoogleSignIn? google})
      : _config = config,
        _auth = auth ?? FirebaseAuth.instance,
        _google = google;

  final AppConfig _config;
  final FirebaseAuth _auth;
  GoogleSignIn? _google;
  bool _googleReady = false;

  static AuthUser? _map(User? u) => u == null
      ? null
      : AuthUser(
          uid: u.uid,
          email: (u.email ?? '').toLowerCase(),
          emailVerified: u.emailVerified,
          displayName: u.displayName,
          photoUrl: u.photoURL,
        );

  @override
  Stream<AuthUser?> get userChanges => _auth.userChanges().map(_map);

  @override
  AuthUser? get currentUser => _map(_auth.currentUser);

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on FirebaseAuthException catch (e) {
      throw mapAuthError(e.code, message: e.message);
    }
  }

  @override
  Future<AuthUser> register({
    required String email,
    required String password,
    required String displayName,
  }) {
    final normalized = ThaparEmail.normalize(email);
    if (!ThaparEmail.isValid(normalized)) {
      throw mapAuthError('wrong-domain');
    }
    return _guard(() async {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: normalized,
        password: password,
      );
      final user = cred.user!;
      await user.updateDisplayName(displayName.trim());
      return _map(_auth.currentUser ?? user)!;
    });
  }

  @override
  Future<AuthUser> signIn({required String email, required String password}) {
    final normalized = ThaparEmail.normalize(email);
    if (!ThaparEmail.isValid(normalized)) {
      throw mapAuthError('wrong-domain');
    }
    return _guard(() async {
      final cred = await _auth.signInWithEmailAndPassword(
        email: normalized,
        password: password,
      );
      return _map(cred.user)!;
    });
  }

  @override
  Future<void> sendVerificationEmail() => _guard(() async {
        final user = _auth.currentUser;
        if (user == null) throw mapAuthError('no-user');
        await user.sendEmailVerification();
      });

  @override
  Future<AuthUser?> reloadUser() => _guard(() async {
        final user = _auth.currentUser;
        if (user == null) return null;
        await user.reload();
        // Force a token refresh so `email_verified` is true in callables.
        await _auth.currentUser?.getIdToken(true);
        return _map(_auth.currentUser);
      });

  @override
  Future<void> sendPasswordReset(String email) {
    final normalized = ThaparEmail.normalize(email);
    if (!ThaparEmail.isValid(normalized)) {
      throw mapAuthError('wrong-domain');
    }
    return _guard(() => _auth.sendPasswordResetEmail(email: normalized));
  }

  @override
  Future<void> signOut() async {
    try {
      if (_googleReady) await _google?.signOut();
    } catch (_) {
      // Google sign-out failure must never block signing out of Firebase.
    }
    await _auth.signOut();
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    if (!_config.googleSignInEnabled) {
      throw mapAuthError('operation-not-allowed');
    }
    final google = _google ??= GoogleSignIn.instance;
    try {
      if (!_googleReady) {
        await google.initialize(
          serverClientId:
              _config.googleServerClientId.isEmpty ? null : _config.googleServerClientId,
        );
        _googleReady = true;
      }
      final account = await google.authenticate();
      if (!ThaparEmail.isValid(account.email)) {
        await google.signOut();
        throw mapAuthError('wrong-domain');
      }
      final idToken = account.authentication.idToken;
      if (idToken == null) throw mapAuthError('invalid-credential');
      final cred = await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      if (!ThaparEmail.isValid(cred.user?.email)) {
        await signOut();
        throw mapAuthError('wrong-domain');
      }
      return _map(cred.user)!;
    } on GoogleSignInException catch (e) {
      throw e.code == GoogleSignInExceptionCode.canceled
          ? mapAuthError('cancelled')
          : mapAuthError('unknown');
    } on FirebaseAuthException catch (e) {
      throw mapAuthError(e.code, message: e.message);
    } on AppException {
      rethrow;
    }
  }
}
