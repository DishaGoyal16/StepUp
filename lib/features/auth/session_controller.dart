import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/auth/auth_repository.dart';
import '../../data/profile/profile_repository.dart';
import '../../domain/auth_state.dart';
import '../../domain/user_profile.dart';

/// Combines Firebase Auth state with the `users/{uid}` profile into the
/// [AuthState] consumed by the router guard. Also exposes the live
/// [profile] (own `users/{uid}` document) to the whole app.
class SessionController extends ChangeNotifier {
  SessionController({required AuthRepository auth, required ProfileRepository profiles})
      : _auth = auth,
        _profiles = profiles;

  final AuthRepository _auth;
  final ProfileRepository _profiles;

  StreamSubscription<AuthUser?>? _authSub;
  StreamSubscription<UserProfile?>? _profileSub;

  AuthState _state = const AuthState.initializing();
  UserProfile? _profile;
  String? _profileUid;
  bool _started = false;

  /// uid for which a "refresh the ID token, then retry" was already attempted after a profile-read error.
  String? _tokenRetryDoneFor;

  AuthState get state => _state;
  UserProfile? get profile => _profile;
  AuthUser? get user => _state.user;

  /// Begin listening (idempotent).
  void start() {
    if (_started) return;
    _started = true;
    _authSub = _auth.userChanges.listen(_onUser);
  }

  void _set(AuthState s) {
    _state = s;
    notifyListeners();
  }

  void _onUser(AuthUser? user) {
    if (user == null) {
      _profileSub?.cancel();
      _profileSub = null;
      _profileUid = null;
      _profile = null;
      _set(const AuthState.signedOut());
      return;
    }
    if (!user.emailVerified) {
      _profileSub?.cancel();
      _profileSub = null;
      _profileUid = null;
      _profile = null;
      _set(AuthState(user: user));
      return;
    }
    // Verified: (re)subscribe to the profile when the user changed or the
    // subscription is not running (e.g. just became verified).
    if (_profileSub == null || _profileUid != user.uid) {
      _subscribeProfile(user);
    } else {
      _set(AuthState(
        user: user,
        profileStatus: _state.profileStatus,
        isAdmin: _state.isAdmin,
      ));
    }
  }

  void _subscribeProfile(AuthUser user) {
    _profileSub?.cancel();
    _profileUid = user.uid;
    _profile = null;
    _set(AuthState(user: user, profileStatus: ProfileStatus.unknown));
    _profileSub = _profiles.watchProfile(user.uid).listen(
      (p) {
        _tokenRetryDoneFor = null;
        _profile = p;
        _set(AuthState(
          user: _auth.currentUser ?? user,
          profileStatus: p == null ? ProfileStatus.missing : ProfileStatus.exists,
          isAdmin: p?.isAdmin ?? false,
        ));
      },
      onError: (Object _) => _onProfileError(user),
    );
  }

  /// A profile read can be denied right after e-mail verification: `user.reload()` reports `emailVerified` (so the
  /// session subscribes) while the cached ID token still says `email_verified=false`, and the Firestore rules
  /// (`eligible()`) reject that token. Found on a real phone: the student saw "We could not load your profile" right
  /// after verifying. So on the first error refresh the token and retry once before showing the error screen.
  Future<void> _onProfileError(AuthUser user) async {
    if (_tokenRetryDoneFor != user.uid) {
      _tokenRetryDoneFor = user.uid;
      try {
        await _auth.reloadUser();
      } catch (_) {
        // fall through: the retry below (or the error screen) handles it
      }
      if (_profileUid == user.uid && _auth.currentUser?.uid == user.uid) {
        _subscribeProfile(_auth.currentUser ?? user);
        return;
      }
    }
    _profile = null;
    _set(AuthState(user: _auth.currentUser ?? user, profileStatus: ProfileStatus.error));
  }

  /// Re-subscribes after a profile load error.
  void retryProfile() {
    final u = _state.user;
    if (u == null || !u.emailVerified) return;
    _tokenRetryDoneFor = null; // a manual retry gets the token refresh again
    _subscribeProfile(u);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }
}
