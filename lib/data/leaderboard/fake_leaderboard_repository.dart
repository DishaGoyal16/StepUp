import 'leaderboard_models.dart';
import 'leaderboard_repository.dart';

/// Scriptable in-memory [LeaderboardRepository] for tests (never shipped
/// data). Provide a [handler] to fully control responses (e.g. with
/// `Completer`s to test out-of-order replies).
class FakeLeaderboardRepository implements LeaderboardRepository {
  FakeLeaderboardRepository({this.handler, this.weeklyRank});

  Future<LeaderboardResult> Function(LeaderboardQuery query, int limit)? handler;
  int? weeklyRank;

  /// Every `load` made, in order.
  final List<LeaderboardQuery> calls = [];

  @override
  Future<LeaderboardResult> load(LeaderboardQuery query, {int limit = LeaderboardRepository.defaultLimit}) {
    calls.add(query);
    final h = handler;
    if (h == null) {
      return Future.value(LeaderboardResult(query: query, entries: const []));
    }
    return h(query, limit);
  }

  @override
  Future<int?> myWeeklyCampusRank() async => weeklyRank;
}
