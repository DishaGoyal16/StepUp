import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/challenges/challenge_models.dart';
import '../../data/challenges/challenge_repository.dart';
import 'action_result.dart';

/// The discovery segments of the Challenges tab.
enum ChallengeSegment {
  individual('Individual'),
  buddy('Buddy'),
  interHostel('Inter-Hostel'),
  campus('Campus'),
  mine('My challenges');

  const ChallengeSegment(this.label);
  final String label;

  /// The open-challenge query type of a listable segment, or `null` for the
  /// segments built from my own participations.
  ChallengeType? get queryType => switch (this) {
        ChallengeSegment.individual => ChallengeType.individual,
        ChallengeSegment.interHostel => ChallengeType.interHostel,
        ChallengeSegment.campus => ChallengeType.campus,
        ChallengeSegment.buddy || ChallengeSegment.mine => null,
      };
}

/// A challenge together with my participation in it (if any).
class ChallengeEntry {
  const ChallengeEntry(this.challenge, this.mine);

  final Challenge challenge;
  final ChallengeParticipation? mine;
}

/// State of the Challenges tab: the five segments, my participations (live)
/// and the buddy invitations.
class ChallengesViewModel extends ChangeNotifier {
  ChallengesViewModel({
    required ChallengeRepository repository,
    required this.uid,
    this.myHostelId,
    ChallengeSegment initial = ChallengeSegment.individual,
  })  : _repo = repository,
        _segment = initial;

  final ChallengeRepository _repo;
  final String uid;
  final String? myHostelId;

  ChallengeSegment _segment;
  final Map<ChallengeType, Loadable<List<Challenge>>> _open = {};
  Map<String, ChallengeParticipation> _mine = {};
  bool _mineLoaded = false;
  String? _mineError;
  String? _challengesError;
  final Map<String, Challenge> _byId = {};
  final Map<String, ParticipantStatus> _seenStatus = {};
  final Set<String> _busy = {};
  StreamSubscription<List<ChallengeParticipation>>? _sub;
  bool _disposed = false;

  ChallengeSegment get segment => _segment;

  void start() {
    _subscribeMine();
    final type = _segment.queryType;
    if (type != null) unawaited(_loadOpen(type));
  }

  void _subscribeMine() {
    _sub?.cancel();
    _mineError = null;
    _sub = _repo.watchMyParticipations(uid).listen(
      (list) {
        _mine = {for (final p in list) p.challengeId: p};
        _mineLoaded = true;
        _mineError = null;
        _notify();
        unawaited(_syncChallenges());
      },
      onError: (Object e) {
        _mineLoaded = true;
        _mineError = errorMessage(e);
        _notify();
      },
    );
  }

  void selectSegment(ChallengeSegment s) {
    if (s == _segment) return;
    _segment = s;
    final type = s.queryType;
    if (type != null && _open[type] == null) unawaited(_loadOpen(type));
    _notify();
  }

  Future<void> _loadOpen(ChallengeType type) async {
    final previous = _open[type];
    if (previous == null || !previous.hasData) {
      _open[type] = const Loadable.loading();
      _notify();
    }
    try {
      final list = await _repo.fetchOpenChallenges(type);
      for (final c in list) {
        _byId[c.id] = c;
      }
      _open[type] = Loadable.data(list);
    } catch (e) {
      final message = errorMessage(e);
      if (previous != null && previous.hasData) {
        _open[type] = previous; // keep the stale list; refresh() reports the error
        _refreshError = message;
      } else {
        _open[type] = Loadable.failed(message);
      }
    }
    _notify();
  }

  String? _refreshError;

  /// Pull-to-refresh / retry for the current segment.
  Future<ActionResult> refresh() async {
    _refreshError = null;
    if (_mineError != null) _subscribeMine();
    final type = _segment.queryType;
    await Future.wait([
      if (type != null) _loadOpen(type),
      _syncChallenges(force: true),
    ]);
    final error = _refreshError ?? _challengesError;
    return error == null ? const ActionResult.ok() : ActionResult.failed(error);
  }

  /// Fetches the challenge documents of my participations (needed because
  /// BUDDY challenges can only be read by id).
  Future<void> _syncChallenges({bool force = false}) async {
    final toFetch = [
      for (final e in _mine.entries)
        if (force || !_byId.containsKey(e.key) || _seenStatus[e.key] != e.value.status) e.key,
    ];
    for (final e in _mine.entries) {
      _seenStatus[e.key] = e.value.status;
    }
    if (toFetch.isEmpty) return;
    try {
      final list = await _repo.fetchChallenges(toFetch);
      for (final c in list) {
        _byId[c.id] = c;
      }
      _challengesError = null;
    } catch (e) {
      _challengesError = errorMessage(e);
    }
    _notify();
  }

  // ---- derived lists -------------------------------------------------------------

  Loadable<List<Challenge>> open(ChallengeType type) => _open[type] ?? const Loadable.loading();

  /// Loading / error of the segments built from my participations.
  Loadable<void> get mineState {
    if (!_mineLoaded) return const Loadable.loading();
    final e = _mineError;
    if (e != null) return Loadable.failed(e);
    return const Loadable.data(null);
  }

  /// True while participation documents exist whose challenge is not loaded yet.
  bool get loadingChallenges =>
      _mineLoaded && _mine.keys.any((id) => !_byId.containsKey(id)) && _challengesError == null;

  String? get challengesError => _challengesError;

  ChallengeParticipation? participationOf(String challengeId) => _mine[challengeId];

  /// Individual catalogue, easiest first.
  List<Challenge> get individualCatalogue {
    final list = [...open(ChallengeType.individual).data ?? const <Challenge>[]];
    list.sort((a, b) {
      final k = a.difficultyKey.compareTo(b.difficultyKey);
      return k != 0 ? k : a.title.compareTo(b.title);
    });
    return list;
  }

  /// Hostel competitions / campus challenges: running ones first, then by start.
  List<Challenge> competitions(ChallengeType type) {
    final list = [...open(type).data ?? const <Challenge>[]];
    int order(Challenge c) => c.status == ChallengeStatus.active ? 0 : 1;
    list.sort((a, b) {
      final o = order(a).compareTo(order(b));
      if (o != 0) return o;
      final sa = a.startAt?.millisecondsSinceEpoch ?? 0;
      final sb = b.startAt?.millisecondsSinceEpoch ?? 0;
      final s = sa.compareTo(sb);
      return s != 0 ? s : a.title.compareTo(b.title);
    });
    return list;
  }

  List<ChallengeEntry> _entries(bool Function(Challenge c, ChallengeParticipation p) test) {
    final out = <ChallengeEntry>[];
    for (final p in _mine.values) {
      final c = _byId[p.challengeId];
      if (c != null && test(c, p)) out.add(ChallengeEntry(c, p));
    }
    out.sort((a, b) => a.challenge.title.toLowerCase().compareTo(b.challenge.title.toLowerCase()));
    return out;
  }

  /// Buddy invitations waiting for MY answer.
  List<ChallengeEntry> get invitations => _entries((c, p) =>
      c.type == ChallengeType.buddy &&
      c.status == ChallengeStatus.pending &&
      p.status == ParticipantStatus.invited);

  /// Buddy challenges I sent that the buddy has not answered yet.
  List<ChallengeEntry> get sentInvitations => _entries((c, p) =>
      c.type == ChallengeType.buddy && c.status == ChallengeStatus.pending && p.isJoined);

  /// Accepted buddy challenges that are upcoming or running.
  List<ChallengeEntry> get activeBuddyChallenges => _entries((c, p) =>
      c.type == ChallengeType.buddy && c.status.isOpen && p.hasProgress);

  /// Completed (or cancelled / declined) buddy challenges.
  List<ChallengeEntry> get buddyHistory => _entries((c, p) =>
      c.type == ChallengeType.buddy &&
      (c.status == ChallengeStatus.completed || c.status == ChallengeStatus.cancelled));

  /// Everything I joined (or completed), running ones first.
  List<ChallengeEntry> get myChallenges {
    final list = _entries((c, p) =>
        p.hasProgress &&
        c.status != ChallengeStatus.cancelled &&
        c.status != ChallengeStatus.pending);
    int order(ChallengeStatus s) => switch (s) {
          ChallengeStatus.active => 0,
          ChallengeStatus.upcoming => 1,
          _ => 2,
        };
    list.sort((a, b) {
      final o = order(a.challenge.status).compareTo(order(b.challenge.status));
      return o != 0 ? o : a.challenge.title.toLowerCase().compareTo(b.challenge.title.toLowerCase());
    });
    return list;
  }

  /// My participation if I am joined / completed, for progress bars on cards.
  ChallengeParticipation? progressOf(String challengeId) {
    final p = _mine[challengeId];
    return p != null && p.hasProgress ? p : null;
  }

  bool isBusy(String challengeId) => _busy.contains(challengeId);

  /// Accept / decline a buddy invitation (`respondChallengeInvite`). Duplicate
  /// taps while a request is running are ignored.
  Future<ActionResult> respondToInvite(String challengeId, {required bool accept}) async {
    if (!_busy.add(challengeId)) return const ActionResult.ok();
    _notify();
    try {
      await _repo.respondToInvite(challengeId, accept: accept);
      _seenStatus.remove(challengeId);
      _byId.remove(challengeId); // refetch: status becomes UPCOMING / CANCELLED
      await _syncChallenges(force: true);
      return ActionResult.ok(accept
          ? 'Challenge accepted. It starts at the next midnight (IST).'
          : 'Invitation declined.');
    } catch (e) {
      return ActionResult.fromError(e);
    } finally {
      _busy.remove(challengeId);
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
