import '../../core/errors/app_exception.dart';
import '../firestore/fake_firestore_access.dart' show ReplayValue;
import 'challenge_models.dart';
import 'challenge_reader.dart';

/// In-memory [ChallengeReader]: used when Firebase is not available
/// (`AppDependencies.rawFirestore == null`, i.e. tests / fake mode) and as the
/// test double. It starts empty - it never invents challenges.
class FakeChallengeReader implements ChallengeReader {
  FakeChallengeReader({
    List<Challenge> challenges = const [],
    List<ChallengeParticipation> participations = const [],
    Map<String, ChallengeResult> results = const {},
  })  : _challenges = {for (final c in challenges) c.id: c},
        _participations = ReplayValue(List.of(participations)),
        _results = Map.of(results);

  final Map<String, Challenge> _challenges;
  final ReplayValue<List<ChallengeParticipation>> _participations;
  final Map<String, ChallengeResult> _results;

  /// When true every read throws an offline [AppException].
  bool offline = false;

  /// Number of calls of [fetchOpenChallenges] (to assert caching).
  int openFetchCount = 0;

  AppException get _offlineError => AppException.fromCallable(code: 'unavailable');

  void putChallenge(Challenge c) => _challenges[c.id] = c;
  void removeChallenge(String id) => _challenges.remove(id);
  void putResult(ChallengeResult r) => _results[r.challengeId] = r;

  /// Replaces or inserts one participation and notifies listeners.
  void putParticipation(ChallengeParticipation p) {
    final list = [
      for (final x in _participations.value)
        if (!(x.challengeId == p.challengeId && x.uid == p.uid)) x,
      p,
    ];
    _participations.value = list;
  }

  void setParticipations(List<ChallengeParticipation> list) => _participations.value = List.of(list);

  @override
  Future<List<Challenge>> fetchOpenChallenges(ChallengeType type) async {
    openFetchCount++;
    if (offline) throw _offlineError;
    return [
      for (final c in _challenges.values)
        if (c.type == type && c.status.isOpen) c,
    ];
  }

  @override
  Future<List<ChallengeParticipation>> fetchMyParticipations(String uid) async {
    if (offline) throw _offlineError;
    return [
      for (final p in _participations.value)
        if (p.uid == uid) p,
    ];
  }

  @override
  Stream<List<ChallengeParticipation>> watchMyParticipations(String uid) => _participations.stream
      .map((l) => [
            for (final p in l)
              if (p.uid == uid) p,
          ])
      .map((l) {
    if (offline) throw _offlineError;
    return l;
  });

  @override
  Stream<ChallengeParticipation?> watchParticipation(String challengeId, String uid) =>
      _participations.stream.map((l) {
        if (offline) throw _offlineError;
        for (final p in l) {
          if (p.challengeId == challengeId && p.uid == uid) return p;
        }
        return null;
      });

  @override
  Future<Challenge?> fetchChallenge(String id) async {
    if (offline) throw _offlineError;
    return _challenges[id];
  }

  @override
  Future<List<Challenge>> fetchChallenges(Iterable<String> ids) async {
    if (offline) throw _offlineError;
    return [
      for (final id in ids.toSet())
        ?_challenges[id],
    ];
  }

  @override
  Future<ChallengeResult?> fetchResult(String challengeId) async {
    if (offline) throw _offlineError;
    return _results[challengeId];
  }
}
