import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import 'challenge_detail_screen.dart';
import 'challenges_screen.dart';
import 'create_buddy_challenge_screen.dart';

/// Extra paths owned by the challenges feature (not in the shared `AppRoutes`).
abstract final class ChallengesRoutes {
  /// "Challenge a buddy" form. Accepts `?buddy=<uid>` to preselect a buddy
  /// (the buddies feature links here from a buddy's profile).
  static const String newBuddy = '/challenges/new-buddy';

  static String newBuddyFor(String buddyUid) =>
      '$newBuddy?buddy=${Uri.encodeQueryComponent(buddyUid)}';
}

/// Routes of the challenges feature. Mounted inside the bottom-navigation shell.
/// `new-buddy` is declared BEFORE `:id` so that it is not read as a challenge id.
final List<RouteBase> challengesRoutes = [
  GoRoute(
    path: AppRoutes.challenges,
    builder: (context, state) => const ChallengesScreen(),
    routes: [
      GoRoute(
        path: 'new-buddy',
        builder: (context, state) =>
            CreateBuddyChallengeScreen(initialBuddyUid: state.uri.queryParameters['buddy']),
      ),
      GoRoute(
        path: ':id',
        builder: (context, state) =>
            ChallengeDetailScreen(challengeId: state.pathParameters['id'] ?? ''),
      ),
    ],
  ),
];
