import '../functions/functions_client.dart';
import 'extras_models.dart';

/// Reads the user's position on the campus WEEKLY board through the
/// `getLeaderboard` callable (`me.rank`). Reading only: the leaderboard
/// engineer owns the board itself.
class CampusRankReader {
  CampusRankReader(this._functions);

  final FunctionsClient _functions;

  /// `null` when the user is not on the board yet (no verified steps this
  /// week, or hidden via privacy). Throws `AppException` when the call fails.
  Future<CampusRank?> fetchWeekly() async {
    final r = await _functions.call('getLeaderboard', {
      'scope': 'CAMPUS',
      'period': 'WEEKLY',
      'limit': 1,
    });
    final me = r['me'];
    if (me is! Map) return null;
    final rank = (me['rank'] as num?)?.toInt();
    if (rank == null || rank <= 0) return null;
    return CampusRank(rank: rank, value: (me['value'] as num?)?.toInt() ?? 0);
  }
}
