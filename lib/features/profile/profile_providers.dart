import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../app_dependencies.dart';
import '../../data/buddies/buddy_directory.dart';
import '../../data/profile_extras/campus_rank_reader.dart';
import '../../data/profile_extras/profile_extras_reader.dart';

/// The read-only data sources of the profile tab, bundled so that tests can
/// replace them in one place.
class ProfileDataSources {
  const ProfileDataSources({required this.extras, required this.buddies, required this.rank});

  /// Badges, achievements, completed challenges and ledger preview.
  final ProfileExtrasReader extras;

  /// Accepted buddies (shared directory).
  final BuddyDirectory buddies;

  /// Campus weekly rank (`getLeaderboard` callable).
  final CampusRankReader rank;
}

/// Providers owned by the profile feature. Reads use `deps.rawFirestore`; in
/// fake mode (`null`) in-memory readers are used.
List<SingleChildWidget> profileProviders(AppDependencies deps) {
  final raw = deps.rawFirestore;
  return [
    Provider<ProfileDataSources>.value(
      value: ProfileDataSources(
        extras: raw == null ? FakeProfileExtrasReader() : FirestoreProfileExtrasReader(raw),
        buddies: raw == null ? FakeBuddyDirectory() : FirestoreBuddyDirectory(raw),
        rank: CampusRankReader(deps.functions),
      ),
    ),
  ];
}
