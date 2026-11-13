import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/router/app_routes.dart';
import 'package:stepup/core/router/redirect.dart';
import 'package:stepup/domain/auth_state.dart';

AuthUser user({bool verified = true}) =>
    AuthUser(uid: 'u1', email: 'a@thapar.edu', emailVerified: verified);

String? _pathOf(String? location) => location == null ? null : Uri.parse(location).path;

void main() {
  const appPaths = [
    AppRoutes.home,
    AppRoutes.stepHistory,
    AppRoutes.buddies,
    AppRoutes.buddyRequests,
    AppRoutes.challenges,
    '/challenges/c1',
    AppRoutes.leaderboard,
    AppRoutes.bets,
    '/bets/b1',
    AppRoutes.profile,
    AppRoutes.notifications,
  ];

  group('initializing', () {
    const s = AuthState.initializing();
    test('everything goes to splash', () {
      for (final p in [AppRoutes.login, AppRoutes.home, AppRoutes.onboarding, ...appPaths]) {
        expect(_pathOf(redirectFor(s, p)), AppRoutes.splash, reason: p);
      }
    });
    test('an app location is remembered in ?from=', () {
      expect(redirectFor(s, '/challenges/c1'), '/splash?from=%2Fchallenges%2Fc1');
      expect(redirectFor(s, AppRoutes.login), AppRoutes.splash, reason: 'auth paths are not remembered');
    });
    test('splash stays', () => expect(redirectFor(s, AppRoutes.splash), isNull));
  });

  group('signed out', () {
    const s = AuthState.signedOut();
    test('login/register/forgot are allowed', () {
      for (final p in [AppRoutes.login, AppRoutes.register, AppRoutes.forgotPassword]) {
        expect(redirectFor(s, p), isNull, reason: p);
      }
    });
    test('everything else goes to /login', () {
      for (final p in [
        AppRoutes.splash,
        AppRoutes.verifyEmail,
        AppRoutes.onboarding,
        AppRoutes.admin,
        ...appPaths,
      ]) {
        expect(redirectFor(s, p), AppRoutes.login, reason: p);
      }
    });
  });

  group('signed in but e-mail unverified', () {
    final s = AuthState(user: user(verified: false));
    test('only /verify-email is allowed', () => expect(redirectFor(s, AppRoutes.verifyEmail), isNull));
    test('everything else goes to /verify-email', () {
      for (final p in [
        AppRoutes.login,
        AppRoutes.register,
        AppRoutes.splash,
        AppRoutes.onboarding,
        AppRoutes.admin,
        ...appPaths,
      ]) {
        expect(redirectFor(s, p), AppRoutes.verifyEmail, reason: p);
      }
    });
    test('profile status is irrelevant while unverified', () {
      final t = AuthState(user: user(verified: false), profileStatus: ProfileStatus.exists);
      expect(redirectFor(t, AppRoutes.home), AppRoutes.verifyEmail);
    });
  });

  group('verified, profile loading or failed', () {
    for (final status in [ProfileStatus.unknown, ProfileStatus.error]) {
      final s = AuthState(user: user(), profileStatus: status);
      test('$status: splash allowed', () => expect(redirectFor(s, AppRoutes.splash), isNull));
      test('$status: everything else goes to splash', () {
        for (final p in [AppRoutes.login, AppRoutes.onboarding, AppRoutes.verifyEmail, ...appPaths]) {
          expect(_pathOf(redirectFor(s, p)), AppRoutes.splash, reason: p);
        }
      });
    }
  });

  group('verified, no profile', () {
    final s = AuthState(user: user(), profileStatus: ProfileStatus.missing);
    test('onboarding allowed', () => expect(redirectFor(s, AppRoutes.onboarding), isNull));
    test('everything else goes to /onboarding', () {
      for (final p in [AppRoutes.login, AppRoutes.splash, AppRoutes.verifyEmail, AppRoutes.admin, ...appPaths]) {
        expect(redirectFor(s, p), AppRoutes.onboarding, reason: p);
      }
    });
  });

  group('verified with profile', () {
    final s = AuthState(user: user(), profileStatus: ProfileStatus.exists);
    test('app routes are allowed', () {
      for (final p in appPaths) {
        expect(redirectFor(s, p), isNull, reason: p);
      }
    });
    test('splash restores the remembered location', () {
      expect(redirectFor(s, '/splash?from=%2Fchallenges%2Fc1'), '/challenges/c1');
      expect(redirectFor(s, '/splash?from=%2Fbets%2Fnew'), '/bets/new');
      expect(redirectFor(s, AppRoutes.splash), AppRoutes.home);
    });
    test('a remembered location is still subject to the guard', () {
      expect(redirectFor(s, '/splash?from=%2Fadmin'), AppRoutes.home);
      final admin = AuthState(user: user(), profileStatus: ProfileStatus.exists, isAdmin: true);
      expect(redirectFor(admin, '/splash?from=%2Fadmin'), '/admin');
    });
    test('a malicious/odd ?from= falls back to /home', () {
      expect(redirectFor(s, '/splash?from=https%3A%2F%2Fevil.com'), AppRoutes.home);
      expect(redirectFor(s, '/splash?from=%2Flogin'), AppRoutes.home);
      expect(redirectFor(s, '/splash?from='), AppRoutes.home);
    });
    test('auth/bootstrap routes bounce to /home', () {
      for (final p in AppRoutes.preAppPaths) {
        expect(redirectFor(s, p), AppRoutes.home, reason: p);
      }
    });
    test('admin routes need the admin role', () {
      for (final p in [
        AppRoutes.admin,
        AppRoutes.adminStudents,
        AppRoutes.adminHostels,
        AppRoutes.adminChallenges,
        AppRoutes.adminReports,
        AppRoutes.adminRisk,
        AppRoutes.adminSettings,
      ]) {
        expect(redirectFor(s, p), AppRoutes.home, reason: p);
        final admin = AuthState(user: user(), profileStatus: ProfileStatus.exists, isAdmin: true);
        expect(redirectFor(admin, p), isNull, reason: p);
      }
    });
    test('"/administrator" is not treated as an admin route', () {
      expect(redirectFor(s, '/administrator'), isNull);
    });
    test('query strings are ignored when matching', () {
      expect(redirectFor(s, '${AppRoutes.login}?x=1'), AppRoutes.home);
    });
  });

  test('AuthState helpers', () {
    expect(const AuthState.signedOut().isSignedIn, isFalse);
    expect(AuthState(user: user(verified: false)).isVerified, isFalse);
    expect(AuthState(user: user(), profileStatus: ProfileStatus.exists).isReady, isTrue);
    expect(AuthState(user: user()).isReady, isFalse);
  });

  test('route constants cover every feature', () {
    expect(AppRoutes.challengeDetail('x'), '/challenges/x');
    expect(AppRoutes.betDetail('y'), '/bets/y');
    expect(AppRoutes.betsCreate, '/bets/new');
    expect(AppRoutes.buddyRequests, '/buddies/requests');
    expect(AppRoutes.stepHistory, '/home/history');
  });
}
