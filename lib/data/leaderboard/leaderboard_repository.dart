import '../../core/errors/app_exception.dart';
import '../functions/functions_client.dart';
import 'leaderboard_models.dart';

/// Source of leaderboards. The only implementation that reaches a backend is
/// [CallableLeaderboardRepository]; every failure surfaces as [AppException].
abstract class LeaderboardRepository {
  static const int defaultLimit = 50;

  /// Loads the board for [query] (the server ranks; nothing is computed here).
  Future<LeaderboardResult> load(LeaderboardQuery query, {int limit = defaultLimit});

  /// The caller's WEEKLY campus rank, or `null` when unranked or on any error.
  Future<int?> myWeeklyCampusRank();
}

/// `getLeaderboard` callable implementation.
class CallableLeaderboardRepository implements LeaderboardRepository {
  CallableLeaderboardRepository(this._functions);

  final FunctionsClient _functions;

  @override
  Future<LeaderboardResult> load(LeaderboardQuery query, {int limit = LeaderboardRepository.defaultLimit}) async {
    final Map<String, dynamic> raw;
    try {
      raw = await _functions.call('getLeaderboard', query.toParams(limit: limit));
    } on AppException {
      rethrow;
    } catch (_) {
      throw AppException.fromCallable(code: 'unavailable');
    }
    try {
      return LeaderboardResult.fromMap(raw, query: query);
    } catch (_) {
      // A malformed response is a server problem, not a crash.
      throw AppException.fromCallable(code: 'internal');
    }
  }

  @override
  Future<int?> myWeeklyCampusRank() async {
    try {
      final r = await load(
        const LeaderboardQuery(scope: LeaderboardScope.campus, period: LeaderboardPeriod.weekly),
        limit: 10,
      );
      return r.me?.rank;
    } catch (_) {
      return null;
    }
  }
}
