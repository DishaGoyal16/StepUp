import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import 'notifications_screen.dart';

/// Routes of the notifications feature. Full-screen routes above the shell.
/// Replace the placeholders; keep the `AppRoutes` paths. Owned by the notifications engineer.
final List<RouteBase> notificationsRoutes = [
  GoRoute(
    path: AppRoutes.notifications,
    builder: (context, state) => const NotificationsScreen(),
  ),
];
