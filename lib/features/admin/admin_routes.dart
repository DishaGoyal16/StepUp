import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import 'admin_screen.dart';
import 'challenges_screen.dart';
import 'hostels_screen.dart';
import 'reports_screen.dart';
import 'risk_screen.dart';
import 'settings_screen.dart';
import 'students_screen.dart';

/// Routes of the admin feature (full-screen, above the shell). The router
/// guard only admits `users.role == 'admin'`; the backend re-checks every call.
/// Children are relative to `/admin`.
final List<RouteBase> adminRoutes = [
  GoRoute(
    path: AppRoutes.admin,
    builder: (context, state) => const AdminScreen(),
    routes: [
      GoRoute(path: 'students', builder: (context, state) => const StudentsScreen()),
      GoRoute(path: 'hostels', builder: (context, state) => const HostelsScreen()),
      GoRoute(
        path: 'challenges',
        builder: (context, state) => const AdminChallengesScreen(),
        routes: [
          GoRoute(path: 'new', builder: (context, state) => const CreateChallengeScreen()),
        ],
      ),
      GoRoute(path: 'reports', builder: (context, state) => const ReportsScreen()),
      GoRoute(path: 'risk', builder: (context, state) => const RiskScreen()),
      GoRoute(path: 'settings', builder: (context, state) => const SettingsScreen()),
      GoRoute(path: 'badges', builder: (context, state) => const BadgesScreen()),
    ],
  ),
];

