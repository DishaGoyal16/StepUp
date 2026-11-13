import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_dependencies.dart';
import '../../features/admin/admin_routes.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/session_controller.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/auth/verify_email_screen.dart';
import '../../features/bets/bets_routes.dart';
import '../../features/buddies/buddies_routes.dart';
import '../../features/challenges/challenges_routes.dart';
import '../../features/home/home_routes.dart';
import '../../features/leaderboard/leaderboard_routes.dart';
import '../../features/notifications/notifications_routes.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/profile/profile_routes.dart';
import 'app_routes.dart';
import 'app_shell.dart';
import 'redirect.dart';

/// Builds the app router.
///
/// * Guard: [redirectFor] on [SessionController.state], re-evaluated whenever
///   the session changes.
/// * Shell (bottom navigation): Home, Buddies, Challenges, Leaderboard,
///   Profile - each a `StatefulShellBranch` filled from `<f>Routes`.
/// * Full-screen routes above the shell: bets, notifications, admin.
GoRouter buildRouter(
  AppDependencies deps, {
  String? initialLocation,
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  final session = deps.session;
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: initialLocation ?? AppRoutes.splash,
    refreshListenable: session,
    redirect: (context, state) => redirectFor(session.state, state.uri.toString()),
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (c, s) => const SplashScreen()),
      GoRoute(path: AppRoutes.login, builder: (c, s) => const LoginScreen()),
      GoRoute(path: AppRoutes.register, builder: (c, s) => const RegisterScreen()),
      GoRoute(path: AppRoutes.forgotPassword, builder: (c, s) => const ForgotPasswordScreen()),
      GoRoute(path: AppRoutes.verifyEmail, builder: (c, s) => const VerifyEmailScreen()),
      GoRoute(path: AppRoutes.onboarding, builder: (c, s) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: homeRoutes),
          StatefulShellBranch(routes: buddiesRoutes),
          StatefulShellBranch(routes: challengesRoutes),
          StatefulShellBranch(routes: leaderboardRoutes),
          StatefulShellBranch(routes: profileRoutes),
        ],
      ),
      ...betsRoutes,
      ...notificationsRoutes,
      ...adminRoutes,
    ],
  );
}
