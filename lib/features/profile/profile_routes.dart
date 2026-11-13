import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import 'edit_profile_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

/// Paths of the profile sub-screens (the shared `AppRoutes` only defines the
/// tab root). Sub-routes are declared relative to `/profile` below.
abstract final class ProfileRoutes {
  static const String edit = '/profile/edit';
  static const String settings = '/profile/settings';

  /// Owned by the bets feature (points ledger); only linked from here.
  static const String pointsLedger = '/bets/ledger';
}

/// Routes of the profile feature. Mounted inside the bottom-navigation shell.
final List<RouteBase> profileRoutes = [
  GoRoute(
    path: AppRoutes.profile,
    builder: (context, state) => const ProfileScreen(),
    routes: [
      GoRoute(
        path: 'edit',
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  ),
];
