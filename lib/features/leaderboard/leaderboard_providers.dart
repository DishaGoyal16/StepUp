import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../app_dependencies.dart';
import '../../data/leaderboard/leaderboard_repository.dart';
import '../../domain/campus_activity.dart';

/// Providers owned by the leaderboard feature. Composed by
/// `lib/app_providers.dart`.
///
/// Also feeds Home's "Campus activity" block with the user's WEEKLY campus
/// rank (`null` on any error or when unranked).
List<SingleChildWidget> leaderboardProviders(AppDependencies deps) {
  final repository = CallableLeaderboardRepository(deps.functions);
  deps.campusActivity.register(
    CampusSlot.myLeaderboardRank,
    (_) => repository.myWeeklyCampusRank(),
  );
  return [
    Provider<LeaderboardRepository>.value(value: repository),
  ];
}
