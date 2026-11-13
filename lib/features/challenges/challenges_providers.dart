import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../app_dependencies.dart';
import '../../data/buddies/buddy_directory.dart';
import '../../data/challenges/challenge_reader.dart';
import '../../data/challenges/challenge_repository.dart';
import '../../data/challenges/fake_challenge_reader.dart';
import '../../data/challenges/firestore_challenge_reader.dart';
import '../../domain/campus_activity.dart';

/// Builds the challenges repository from the shared dependencies:
/// Firestore reads when `deps.rawFirestore` exists, an (empty) in-memory
/// reader otherwise; all writes go through `deps.functions`.
ChallengeRepository buildChallengeRepository(
  AppDependencies deps, {
  ChallengeReader? reader,
  BuddyDirectory? buddies,
}) {
  final db = deps.rawFirestore;
  return ChallengeRepository(
    reader: reader ?? (db != null ? FirestoreChallengeReader(db) : FakeChallengeReader()),
    functions: deps.functions,
    buddies: buddies ?? (db != null ? FirestoreBuddyDirectory(db) : FakeBuddyDirectory()),
  );
}

/// Registers the two numbers the challenges feature contributes to Home's
/// "Campus activity" block. A loader that throws leaves its slot empty.
void registerChallengeCampusActivity(AppDependencies deps, ChallengeRepository repo) {
  deps.campusActivity.register(
    CampusSlot.activeChallenges,
    (uid) => repo.countMyActiveChallenges(uid),
  );
  deps.campusActivity.register(CampusSlot.upcomingHostelCompetitions, (uid) async {
    var hostelId = deps.session.profile?.hostelId;
    if (hostelId == null || hostelId.isEmpty) {
      final profile = await deps.firestore
          .watchUserProfile(uid)
          .first
          .timeout(const Duration(seconds: 5));
      hostelId = profile?.hostelId;
    }
    if (hostelId == null || hostelId.isEmpty) return null;
    return repo.countUpcomingHostelCompetitions(hostelId);
  });
}

/// Providers owned by the challenges feature. Composed by `lib/app_providers.dart`.
///
/// [reader] / [buddies] are optional overrides (tests).
List<SingleChildWidget> challengesProviders(
  AppDependencies deps, {
  ChallengeReader? reader,
  BuddyDirectory? buddies,
}) {
  final repo = buildChallengeRepository(deps, reader: reader, buddies: buddies);
  registerChallengeCampusActivity(deps, repo);
  return [Provider<ChallengeRepository>.value(value: repo)];
}
