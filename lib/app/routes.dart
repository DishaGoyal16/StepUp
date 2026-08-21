import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/onboarding/onboarding_screen.dart';
import '../features/home/home_screen.dart';
import '../features/activity/activity_screen.dart';
import '../features/activity/activity_detail_screen.dart';
import '../features/activity/verified_session_screen.dart';
import '../features/challenges/challenges_screen.dart';
import '../features/bets/bets_screen.dart';
import '../features/bets/create_bet_screen.dart';
import '../features/bets/bet_detail_screen.dart';
import '../features/sport_buddy/sport_buddy_screen.dart';
import '../features/sport_buddy/buddy_match_screen.dart';
import '../features/sessions/sessions_screen.dart';
import '../features/sessions/create_session_screen.dart';
import '../features/leaderboard/leaderboard_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/wallet/wallet_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/privacy_screen.dart';
import '../features/settings/demo_mode_screen.dart';
import '../widgets/main_scaffold.dart';

const String _onboardingCompleteKey = 'onboarding_complete';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      final prefs = await SharedPreferences.getInstance();
      final onboardingDone = prefs.getBool(_onboardingCompleteKey) ?? false;
      if (!onboardingDone && state.matchedLocation == '/') {
        return '/onboarding';
      }
      if (onboardingDone && state.matchedLocation == '/onboarding') {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (_, __) => '/home',
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) => _buildPage(
          state,
          const OnboardingScreen(),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) =>
                _buildPage(state, const HomeScreen()),
          ),
          GoRoute(
            path: '/activity',
            pageBuilder: (context, state) =>
                _buildPage(state, const ActivityScreen()),
            routes: [
              GoRoute(
                path: 'detail',
                pageBuilder: (context, state) =>
                    _buildPage(state, const ActivityDetailScreen()),
              ),
              GoRoute(
                path: 'session',
                pageBuilder: (context, state) =>
                    _buildPage(state, const VerifiedSessionScreen()),
              ),
            ],
          ),
          GoRoute(
            path: '/challenges',
            pageBuilder: (context, state) =>
                _buildPage(state, const ChallengesScreen()),
            routes: [
              GoRoute(
                path: 'bets',
                pageBuilder: (context, state) =>
                    _buildPage(state, const BetsScreen()),
              ),
              GoRoute(
                path: 'bets/create',
                pageBuilder: (context, state) =>
                    _buildPage(state, const CreateBetScreen()),
              ),
              GoRoute(
                path: 'bets/:id',
                pageBuilder: (context, state) => _buildPage(
                  state,
                  BetDetailScreen(betId: state.pathParameters['id']!),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/sport-buddy',
            pageBuilder: (context, state) =>
                _buildPage(state, const SportBuddyScreen()),
            routes: [
              GoRoute(
                path: 'matches',
                pageBuilder: (context, state) =>
                    _buildPage(state, const BuddyMatchScreen()),
              ),
              GoRoute(
                path: 'sessions',
                pageBuilder: (context, state) =>
                    _buildPage(state, const SessionsScreen()),
              ),
              GoRoute(
                path: 'sessions/create',
                pageBuilder: (context, state) =>
                    _buildPage(state, const CreateSessionScreen()),
              ),
            ],
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) =>
                _buildPage(state, const ProfileScreen()),
            routes: [
              GoRoute(
                path: 'wallet',
                pageBuilder: (context, state) =>
                    _buildPage(state, const WalletScreen()),
              ),
              GoRoute(
                path: 'leaderboard',
                pageBuilder: (context, state) =>
                    _buildPage(state, const LeaderboardScreen()),
              ),
              GoRoute(
                path: 'settings',
                pageBuilder: (context, state) =>
                    _buildPage(state, const SettingsScreen()),
              ),
              GoRoute(
                path: 'privacy',
                pageBuilder: (context, state) =>
                    _buildPage(state, const PrivacyScreen()),
              ),
              GoRoute(
                path: 'demo',
                pageBuilder: (context, state) =>
                    _buildPage(state, const DemoModeScreen()),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Route not found: ${state.error}'),
      ),
    ),
  );
});

CustomTransitionPage<void> _buildPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurveTween(curve: Curves.easeInOut).animate(animation),
        child: child,
      );
    },
    transitionDuration: const Duration(milliseconds: 220),
  );
}
