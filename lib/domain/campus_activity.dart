/// Data for the "Campus activity" block on Home. Any value may be null when
/// the feature that owns it has nothing to show (or is not available yet).
class CampusActivity {
  const CampusActivity({
    this.activeChallenges,
    this.upcomingHostelCompetitions,
    this.buddiesAvailable,
    this.myLeaderboardRank,
  });

  static const CampusActivity empty = CampusActivity();

  final int? activeChallenges;
  final int? upcomingHostelCompetitions;
  final int? buddiesAvailable;
  final int? myLeaderboardRank;
}

enum CampusSlot { activeChallenges, upcomingHostelCompetitions, buddiesAvailable, myLeaderboardRank }

/// Source of [CampusActivity] for the signed-in user.
abstract class CampusActivitySource {
  Future<CampusActivity> load(String uid);
}

/// Default source: nothing is available, Home shows friendly empty states.
class EmptyCampusActivitySource implements CampusActivitySource {
  const EmptyCampusActivitySource();

  @override
  Future<CampusActivity> load(String uid) async => CampusActivity.empty;
}

/// Lets each feature engineer plug in its own number without editing shared
/// code. Call from the feature's `<f>Providers(deps)`:
///
/// ```dart
/// deps.campusActivity.register(CampusSlot.activeChallenges, (uid) => repo.countActive());
/// ```
///
/// A loader that throws or returns null leaves that slot empty.
class CampusActivityRegistry implements CampusActivitySource {
  final Map<CampusSlot, Future<int?> Function(String uid)> _loaders = {};

  void register(CampusSlot slot, Future<int?> Function(String uid) loader) {
    _loaders[slot] = loader;
  }

  @override
  Future<CampusActivity> load(String uid) async {
    Future<int?> run(CampusSlot slot) async {
      final loader = _loaders[slot];
      if (loader == null) return null;
      try {
        return await loader(uid);
      } catch (_) {
        return null;
      }
    }

    final r = await Future.wait([
      run(CampusSlot.activeChallenges),
      run(CampusSlot.upcomingHostelCompetitions),
      run(CampusSlot.buddiesAvailable),
      run(CampusSlot.myLeaderboardRank),
    ]);
    return CampusActivity(
      activeChallenges: r[0],
      upcomingHostelCompetitions: r[1],
      buddiesAvailable: r[2],
      myLeaderboardRank: r[3],
    );
  }
}
