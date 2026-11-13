import '../../core/errors/app_exception.dart';
import '../buddies/buddy_directory.dart';
import '../functions/functions_client.dart';
import 'challenge_models.dart';
import 'challenge_reader.dart';

/// The challenges feature's single data entry point.
///
/// * reads go through a [ChallengeReader] (Firestore or the in-memory fake);
/// * EVERY write goes through a callable (`joinChallenge`, `leaveChallenge`,
///   `createBuddyChallenge`, `respondChallengeInvite`) - the client never
///   writes progress, winners or rewards;
/// * the leaderboard comes from the `getChallengeLeaderboard` callable.
///
/// Every failure is an `AppException`.
class ChallengeRepository {
  ChallengeRepository({
    required ChallengeReader reader,
    required FunctionsClient functions,
    required BuddyDirectory buddies,
  })  : _reader = reader,
        _functions = functions,
        _buddies = buddies;

  final ChallengeReader _reader;
  final FunctionsClient _functions;
  final BuddyDirectory _buddies;

  // ---- reads ----------------------------------------------------------------

  Future<List<Challenge>> fetchOpenChallenges(ChallengeType type) =>
      _reader.fetchOpenChallenges(type);

  Stream<List<ChallengeParticipation>> watchMyParticipations(String uid) =>
      _reader.watchMyParticipations(uid);

  Stream<ChallengeParticipation?> watchParticipation(String challengeId, String uid) =>
      _reader.watchParticipation(challengeId, uid);

  Future<Challenge?> fetchChallenge(String id) => _reader.fetchChallenge(id);

  Future<List<Challenge>> fetchChallenges(Iterable<String> ids) => _reader.fetchChallenges(ids);

  Future<ChallengeResult?> fetchResult(String challengeId) => _reader.fetchResult(challengeId);

  /// Accepted buddies (shared directory) for the "challenge a buddy" flow.
  Stream<List<BuddySummary>> watchBuddies(String uid) => _buddies.watchBuddies(uid);

  // ---- callables ------------------------------------------------------------

  Future<void> join(String challengeId) async {
    await _functions.call('joinChallenge', {'challengeId': challengeId});
  }

  Future<void> leave(String challengeId) async {
    await _functions.call('leaveChallenge', {'challengeId': challengeId});
  }

  /// Creates a PENDING buddy challenge and returns its id. It starts at the
  /// next IST midnight after the buddy accepts.
  Future<String> createBuddyChallenge({
    required String buddyUid,
    required int durationDays,
    required int targetSteps,
    String? title,
  }) async {
    final trimmed = title?.trim();
    final r = await _functions.call('createBuddyChallenge', {
      'buddyUid': buddyUid,
      if (trimmed != null && trimmed.isNotEmpty) 'title': trimmed,
      'durationDays': durationDays,
      'targetSteps': targetSteps,
    });
    final id = r['challengeId'];
    if (id is! String || id.isEmpty) {
      throw AppException.fromCallable(code: 'internal');
    }
    return id;
  }

  Future<void> respondToInvite(String challengeId, {required bool accept}) async {
    await _functions.call('respondChallengeInvite', {
      'challengeId': challengeId,
      'accept': accept,
    });
  }

  Future<ChallengeLeaderboard> leaderboard(String challengeId, {int? limit}) async {
    final r = await _functions.call('getChallengeLeaderboard', {
      'challengeId': challengeId,
      'limit': ?limit,
    });
    return ChallengeLeaderboard.fromMap(r);
  }

  // ---- numbers for Home's "Campus activity" ---------------------------------------

  /// Number of ACTIVE challenges I currently participate in (JOINED).
  Future<int> countMyActiveChallenges(String uid) async {
    final mine = await _reader.fetchMyParticipations(uid);
    final ids = [
      for (final p in mine)
        if (p.isJoined) p.challengeId,
    ];
    if (ids.isEmpty) return 0;
    final challenges = await _reader.fetchChallenges(ids);
    return challenges.where((c) => c.status == ChallengeStatus.active).length;
  }

  /// Number of UPCOMING INTER_HOSTEL challenges that [hostelId] is part of.
  Future<int> countUpcomingHostelCompetitions(String hostelId) async {
    final list = await _reader.fetchOpenChallenges(ChallengeType.interHostel);
    return list
        .where((c) => c.status == ChallengeStatus.upcoming && c.hostelIds.contains(hostelId))
        .length;
  }
}
