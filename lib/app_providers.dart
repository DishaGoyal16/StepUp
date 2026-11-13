import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'app_dependencies.dart';
import 'core/config/app_config.dart';
import 'data/auth/auth_repository.dart';
import 'data/firestore/firestore_access.dart';
import 'data/functions/callables.dart';
import 'data/functions/functions_client.dart';
import 'data/profile/profile_repository.dart';
import 'data/steps/step_sync_service.dart';
import 'data/steps/step_tracking_controller.dart';
import 'features/admin/admin_providers.dart';
import 'features/auth/session_controller.dart';
import 'features/bets/bets_providers.dart';
import 'features/buddies/buddies_providers.dart';
import 'features/challenges/challenges_providers.dart';
import 'features/leaderboard/leaderboard_providers.dart';
import 'features/notifications/notifications_providers.dart';
import 'features/profile/profile_providers.dart';

/// Composes every provider of the app: shared singletons first, then the
/// per-feature lists. Feature engineers only edit their own
/// `lib/features/<f>/<f>_providers.dart`, never this file.
///
/// Anything in [AppDependencies] can be read with `context.read<T>()` for the
/// types exposed here (or `context.read<AppDependencies>()`).
List<SingleChildWidget> appProviders(AppDependencies deps) => [
      Provider<AppDependencies>.value(value: deps),
      Provider<AppConfig>.value(value: deps.config),
      Provider<AuthRepository>.value(value: deps.auth),
      Provider<ProfileRepository>.value(value: deps.profiles),
      Provider<FunctionsClient>.value(value: deps.functions),
      Provider<Callables>.value(value: deps.callables),
      Provider<FirestoreAccess>.value(value: deps.firestore),
      ChangeNotifierProvider<SessionController>.value(value: deps.session),
      ChangeNotifierProvider<StepTrackingController>.value(value: deps.stepTracking),
      ChangeNotifierProvider<StepSyncService>.value(value: deps.stepSync),
      // --- feature extension points ---
      ...buddiesProviders(deps),
      ...challengesProviders(deps),
      ...betsProviders(deps),
      ...leaderboardProviders(deps),
      ...profileProviders(deps),
      ...notificationsProviders(deps),
      ...adminProviders(deps),
    ];
