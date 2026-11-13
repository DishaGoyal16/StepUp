import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import 'buddies_screen.dart';
import 'buddy_requests_screen.dart';

/// Routes of the buddies feature. Mounted inside the bottom-navigation shell:
/// `/buddies` (finder + my buddies) and its sub-route `/buddies/requests`.
final List<RouteBase> buddiesRoutes = [
  GoRoute(
    path: AppRoutes.buddies,
    builder: (context, state) => const BuddiesScreen(),
    routes: [
      GoRoute(
        path: 'requests',
        builder: (context, state) => const BuddyRequestsScreen(),
      ),
    ],
  ),
];
