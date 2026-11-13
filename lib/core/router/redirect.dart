import '../../domain/auth_state.dart';
import 'app_routes.dart';

/// Pure router guard. Returns the path to redirect to, or `null` to allow
/// [location].
///
/// | state                         | allowed                         |
/// |-------------------------------|---------------------------------|
/// | auth not resolved yet         | /splash                         |
/// | signed out                    | /login /register /forgot-password |
/// | signed in, e-mail unverified  | /verify-email only              |
/// | verified, profile loading/err | /splash                         |
/// | verified, no profile          | /onboarding only                |
/// | verified + profile            | the app (not auth/bootstrap paths; /admin needs role admin) |
///
/// While the session is still loading, an app location is remembered as
/// `/splash?from=<location>` and restored once the user is ready.
String? redirectFor(AuthState s, String location) {
  final uri = Uri.tryParse(location);
  final path = uri?.path ?? location;

  String toSplash() {
    if (path == AppRoutes.splash || AppRoutes.preAppPaths.contains(path)) {
      return AppRoutes.splash;
    }
    return Uri(path: AppRoutes.splash, queryParameters: {'from': location}).toString();
  }

  if (s.initializing) {
    return path == AppRoutes.splash ? null : toSplash();
  }
  final user = s.user;
  if (user == null) {
    return AppRoutes.publicAuthPaths.contains(path) ? null : AppRoutes.login;
  }
  if (!user.emailVerified) {
    return path == AppRoutes.verifyEmail ? null : AppRoutes.verifyEmail;
  }
  switch (s.profileStatus) {
    case ProfileStatus.unknown:
    case ProfileStatus.error:
      return path == AppRoutes.splash ? null : toSplash();
    case ProfileStatus.missing:
      return path == AppRoutes.onboarding ? null : AppRoutes.onboarding;
    case ProfileStatus.exists:
      if (path == AppRoutes.splash) {
        final from = uri?.queryParameters['from'];
        final fromPath = from == null ? null : Uri.tryParse(from)?.path;
        if (from != null &&
            fromPath != null &&
            from.startsWith('/') &&
            !AppRoutes.preAppPaths.contains(fromPath)) {
          return redirectFor(s, from) ?? from;
        }
        return AppRoutes.home;
      }
      if (AppRoutes.preAppPaths.contains(path)) return AppRoutes.home;
      if ((path == AppRoutes.admin || path.startsWith('${AppRoutes.admin}/')) && !s.isAdmin) {
        return AppRoutes.home;
      }
      return null;
  }
}
