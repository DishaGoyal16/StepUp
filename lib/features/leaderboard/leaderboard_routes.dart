import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import 'leaderboard_screen.dart';

/// Routes of the leaderboard feature. Mounted inside the bottom-navigation shell.
/// Replace the placeholders; keep the `AppRoutes` paths. Owned by the leaderboard engineer.
final List<RouteBase> leaderboardRoutes = [
  GoRoute(
    path: AppRoutes.leaderboard,
    builder: (context, state) => const LeaderboardScreen(),
  ),
];
