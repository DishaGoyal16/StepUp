import 'dart:async';

import '../../domain/auth_state.dart';
import '../../domain/thapar_email.dart';
import 'auth_errors.dart';
import 'auth_repository.dart';

/// In-memory [AuthRepository] for tests and `AppDependencies.fake()`.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AuthUser? initialUser}) : _current = initialUser;

  final Map<String, _Account> _accounts = {};
  final StreamController<AuthUser?> _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _current;
  int _nextUid = 1;

  /// How many verification e-mails were "sent".
  int verificationEmailsSent = 0;
  final List<String> passwordResetsSentTo = [];

  /// When set, the next call to any method throws this error code once.
  String? failNextWithCode;

  /// When true [reloadUser] reports the user as verified (simulates clicking
  /// the link in the e-mail).
  void simulateEmailVerified() {
    final u = _current;
    if (u == null) return;
    _accounts[u.email]?.verified = true;
  }

  void _maybeFail() {
    final c = failNextWithCode;
    if (c != null) {
      failNextWithCode = null;
      throw mapAuthError(c);
    }
  }

  void _emit(AuthUser? user) {
    _current = user;
    _controller.add(user);
  }

  @override
  Stream<AuthUser?> get userChanges => Stream.multi((c) {
        c.add(_current);
        final sub = _controller.stream.listen(c.add);
        c.onCancel = sub.cancel;
      }, isBroadcast: true);

  @override
  AuthUser? get currentUser => _current;

  @override
  Future<AuthUser> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _maybeFail();
    final e = ThaparEmail.normalize(email);
    if (!ThaparEmail.isValid(e)) throw mapAuthError('wrong-domain');
    if (_accounts.containsKey(e)) throw mapAuthError('email-already-in-use');
    if (password.length < 6) throw mapAuthError('weak-password');
    final account = _Account('fake-uid-${_nextUid++}', password, displayName);
    _accounts[e] = account;
    final user = AuthUser(uid: account.uid, email: e, emailVerified: false, displayName: displayName);
    _emit(user);
    return user;
  }

  @override
  Future<AuthUser> signIn({required String email, required String password}) async {
    _maybeFail();
    final e = ThaparEmail.normalize(email);
    final account = _accounts[e];
    if (account == null || account.password != password) {
      throw mapAuthError('invalid-credential');
    }
    final user = AuthUser(
      uid: account.uid,
      email: e,
      emailVerified: account.verified,
      displayName: account.displayName,
    );
    _emit(user);
    return user;
  }

  @override
  Future<void> sendVerificationEmail() async {
    _maybeFail();
    if (_current == null) throw mapAuthError('no-user');
    verificationEmailsSent++;
  }

  @override
  Future<AuthUser?> reloadUser() async {
    _maybeFail();
    final u = _current;
    if (u == null) return null;
    final account = _accounts[u.email];
    final verified = account?.verified ?? u.emailVerified;
    final refreshed = AuthUser(
      uid: u.uid,
      email: u.email,
      emailVerified: verified,
      displayName: u.displayName,
    );
    _emit(refreshed);
    return refreshed;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    _maybeFail();
    final e = ThaparEmail.normalize(email);
    if (!ThaparEmail.isValid(e)) throw mapAuthError('wrong-domain');
    passwordResetsSentTo.add(e);
  }

  @override
  Future<void> signOut() async {
    _emit(null);
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    _maybeFail();
    throw mapAuthError('operation-not-allowed');
  }

  /// Registers a ready account (and optionally signs in) for tests.
  AuthUser seedAccount({
    required String email,
    String password = 'Password1',
    String displayName = 'Test Student',
    bool verified = true,
    bool signIn = true,
  }) {
    final e = ThaparEmail.normalize(email);
    final account = _Account('fake-uid-${_nextUid++}', password, displayName)..verified = verified;
    _accounts[e] = account;
    final user = AuthUser(uid: account.uid, email: e, emailVerified: verified, displayName: displayName);
    if (signIn) _emit(user);
    return user;
  }

  void dispose() => _controller.close();
}

class _Account {
  _Account(this.uid, this.password, this.displayName);

  final String uid;
  final String password;
  final String displayName;
  bool verified = false;
}
