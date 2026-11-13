import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import 'history_screen.dart';
import 'home_screen.dart';

/// Routes of shell tab 1 (Home) and its sub-screens.
final List<RouteBase> homeRoutes = [
  GoRoute(
    path: AppRoutes.home,
    builder: (context, state) => const HomeScreen(),
    routes: [
      GoRoute(
        path: 'history',
        builder: (context, state) => const HistoryScreen(),
      ),
    ],
  ),
];
