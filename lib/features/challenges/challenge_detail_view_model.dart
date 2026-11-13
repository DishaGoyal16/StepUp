import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/clock.dart';
import '../../data/challenges/challenge_models.dart';
import '../../data/challenges/challenge_repository.dart';
import '../../domain/daily_step_summary.dart';
import '../../domain/day_key.dart';
import '../../domain/hostel.dart';
import 'action_result.dart';
import 'challenge_logic.dart';

/// One day of MY verified steps inside a buddy challenge window.
class DailyRow {
  const DailyRow({required this.dayKey, required this.label, required this.verified});

  final String dayKey;
  final String label;
  final int verified;
}

/// A hostel taking part in an INTER_HOSTEL challenge.
class CompetingHostel {
  const CompetingHostel({required this.id, required this.name, required this.isMine});

  final String id;
  final String name;
  final bool isMine;
}

/// State of one challenge's detail screen.
///
/// * the challenge document is fetched by id (pull-to-refresh re-fetches);
/// * MY progress is a live stream of `challengeParticipants/{id}_{uid}`;
/// * the leaderboard / hostel ranking comes from `getChallengeLeaderboard`;
/// * the final result comes from `challengeResults/{id}` (server written).
/// Nothing is computed on the client: percentages are only formatting.
class ChallengeDetailViewModel extends ChangeNotifier {
  ChallengeDetailViewModel({
    required ChallengeRepository repository,
    required this.challengeId,
    required this.uid,
    required Clock clock,
    this.myHostelId,
    Future<HostelDirectory> Function()? loadHostels,
    Stream<List<DailyStepSummary>> Function(String uid)? watchDailySummaries,
  })  : _repo = repository,
        _clock = clock,
        _loadHostels = loadHostels,
        _watchDaily = watchDailySummaries;

  final ChallengeRepository _repo;
  final String challengeId;
  final String uid;
  final String? myHostelId;
  final Clock _clock;
  final Future<HostelDirectory> Function()? _loadHostels;
  final Stream<List<DailyStepSummary>> Function(String uid)? _watchDaily;

  Loadable<Challenge> _challenge = const Loadable.loading();
  ChallengeParticipation? _mine;
  Loadable<ChallengeLeaderboard> _leaderboard = const Loadable.loading();
  ChallengeResult? _result;
  String? _resultError;
  HostelDirectory? _hostels;
  List<DailyStepSummary> _daily = const [];
  bool _busy = false;
  bool _lbInFlight = false;
  bool _disposed = false;
  bool _loadedOnce = false;
  StreamSubscription<ChallengeParticipation?>? _mineSub;
  StreamSubscription<List<DailyStepSummary>>? _dailySub;

  Loadable<Challenge> get challenge => _challenge;
  Challenge? get challengeOrNull => _challenge.data;
  ChallengeParticipation? get mine => _mine;
  Loadable<ChallengeLeaderboard> get leaderboard => _leaderboard;
  ChallengeResult? get result => _result;
  String? get resultError => _resultError;
  bool get busy => _busy;
  DateTime get now => _clock.now();

  void start() {
    _mineSub = _repo.watchParticipation(challengeId, uid).listen(
      (p) {
        final before = _mine?.progress;
        _mine = p;
        _notify();
        // Live progress: when my number moved, refresh the ranking quietly.
        if (_loadedOnce && p != null && before != null && before != p.progress) {
          unawaited(_loadLeaderboard(quiet: true));
        }
      },
      onError: (Object _) {
        // The progress card simply stays empty; the screen shows the rest.
      },
    );
    unawaited(_load());
  }

  Future<void> _load() async {
    final previous = _challenge;
    if (!previous.hasData) {
      _challenge = const Loadable.loading();
      _notify();
    }
    Challenge? c;
    try {
      c = await _repo.fetchChallenge(challengeId);
    } catch (e) {
      if (previous.hasData) {
        _refreshError = errorMessage(e);
        return;
      }
      _challenge = Loadable.failed(errorMessage(e));
      _notify();
      return;
    }
    if (c == null) {
      _challenge = const Loadable.failed('This challenge is not available.');
      _notify();
      return;
    }
    _challenge = Loadable.data(c);
    _loadedOnce = true;
    _notify();
    _ensureDailySubscription(c);
    await Future.wait([
      _loadHostelDirectory(),
      if (c.status != ChallengeStatus.pending && c.status != ChallengeStatus.cancelled)
        _loadLeaderboard(),
      if (c.status == ChallengeStatus.completed) _loadResult(),
    ]);
  }

  String? _refreshError;

  /// Pull-to-refresh / retry.
  Future<ActionResult> refresh() async {
    _refreshError = null;
    await _load();
    return _refreshError == null ? const ActionResult.ok() : ActionResult.failed(_refreshError!);
  }

  Future<void> _loadHostelDirectory() async {
    if (_hostels != null || _loadHostels == null) return;
    try {
      _hostels = await _loadHostels();
      _notify();
    } catch (_) {
      // Hostel names fall back to their ids.
    }
  }

  Future<void> _loadLeaderboard({bool quiet = false}) async {
    if (_lbInFlight) return;
    _lbInFlight = true;
    if (!quiet && !_leaderboard.hasData) {
      _leaderboard = const Loadable.loading();
      _notify();
    }
    try {
      final lb = await _repo.leaderboard(challengeId);
      _leaderboard = Loadable.data(lb);
    } catch (e) {
      if (!(quiet && _leaderboard.hasData)) _leaderboard = Loadable.failed(errorMessage(e));
    } finally {
      _lbInFlight = false;
    }
    _notify();
  }

  /// Retry button of the leaderboard section.
  Future<void> reloadLeaderboard() => _loadLeaderboard();

  Future<void> _loadResult() async {
    try {
      _result = await _repo.fetchResult(challengeId);
      _resultError = null;
    } catch (e) {
      _resultError = errorMessage(e);
    }
    _notify();
  }

  void _ensureDailySubscription(Challenge c) {
    if (_dailySub != null || c.type != ChallengeType.buddy || _watchDaily == null) return;
    _dailySub = _watchDaily(uid).listen(
      (list) {
        _daily = list;
        _notify();
      },
      onError: (Object _) {},
    );
  }

  // ---- derived values -----------------------------------------------------------

  JoinDecision? get joinDecision {
    final c = _challenge.data;
    if (c == null) return null;
    return decideJoin(challenge: c, mine: _mine, myHostelId: myHostelId, now: now);
  }

  bool get canLeaveChallenge {
    final c = _challenge.data;
    return c != null && canLeave(c, _mine);
  }

  /// A buddy invitation waiting for my answer.
  bool get hasInviteForMe {
    final c = _challenge.data;
    return c != null &&
        c.type == ChallengeType.buddy &&
        c.status == ChallengeStatus.pending &&
        _mine?.status == ParticipantStatus.invited;
  }

  /// I created this buddy challenge and the buddy has not answered yet.
  bool get waitingForBuddy {
    final c = _challenge.data;
    return c != null &&
        c.type == ChallengeType.buddy &&
        c.status == ChallengeStatus.pending &&
        c.createdBy == uid;
  }

  bool get showLeaderboard {
    final c = _challenge.data;
    return c != null &&
        c.status != ChallengeStatus.pending &&
        c.status != ChallengeStatus.cancelled;
  }

  /// My progress as shown in the progress card (joined or completed only).
  int? get myProgress => (_mine != null && _mine!.hasProgress) ? _mine!.progress : null;

  int? get myPercent {
    final c = _challenge.data;
    final p = myProgress;
    if (c == null || p == null) return null;
    return progressPercent(p, c.target);
  }

  String? get countdown {
    final c = _challenge.data;
    return c == null ? null : countdownText(c, now, mine: _mine);
  }

  String hostelName(String? id) {
    if (id == null || id.isEmpty) return '';
    return _hostels?.byId(id)?.displayName ?? id;
  }

  /// Hostels of an INTER_HOSTEL challenge (names from the hostel directory).
  List<CompetingHostel> get competingHostels {
    final c = _challenge.data;
    if (c == null || c.type != ChallengeType.interHostel) return const [];
    return [
      for (final id in c.hostelIds)
        CompetingHostel(id: id, name: hostelName(id), isMine: id == myHostelId),
    ];
  }

  /// Both competitors of an accepted buddy challenge, me first. Taken from the
  /// server leaderboard (a student can read only their own participant doc).
  List<LeaderboardRow> get buddyRows {
    final lb = _leaderboard.data;
    if (lb == null) return const [];
    final mineRow = lb.entries.where((r) => r.id == uid);
    final other = lb.entries.where((r) => r.id != uid);
    return [...mineRow, ...other];
  }

  /// MY verified steps per day inside a buddy challenge window, up to today.
  List<DailyRow> get myDailyRows {
    final c = _challenge.data;
    if (c == null || c.type != ChallengeType.buddy) return const [];
    final start = c.startAt;
    final end = c.endAt;
    if (start == null || end == null) return const [];
    final byDay = {for (final s in _daily) s.dayKey: s.verifiedSteps};
    final today = DayKey.of(now);
    final rows = <DailyRow>[];
    var cursor = DayKey.startOfDay(start);
    while (cursor.isBefore(end)) {
      final key = DayKey.of(cursor);
      if (key.compareTo(today) > 0) break;
      rows.add(DailyRow(dayKey: key, label: DayKey.label(key), verified: byDay[key] ?? 0));
      cursor = cursor.add(const Duration(days: 1));
    }
    return rows;
  }

  // ---- actions ------------------------------------------------------------------

  /// `joinChallenge`. Duplicate taps while running are ignored.
  Future<ActionResult> join() async {
    final c = _challenge.data;
    if (c == null || _busy) return const ActionResult.ok();
    final decision = joinDecision;
    if (decision != null && !decision.canJoin) {
      return ActionResult.failed(decision.reason ?? 'You cannot join this challenge.');
    }
    return _run(() async {
      await _repo.join(challengeId);
      return 'You joined "${c.title}". Only verified steps count.';
    });
  }

  /// `leaveChallenge`.
  Future<ActionResult> leave() async {
    final c = _challenge.data;
    if (c == null || _busy) return const ActionResult.ok();
    if (!canLeaveChallenge) return const ActionResult.failed('You cannot leave this challenge.');
    return _run(() async {
      await _repo.leave(challengeId);
      return 'You left "${c.title}".';
    });
  }

  /// `respondChallengeInvite` (buddy invitations).
  Future<ActionResult> respond({required bool accept}) async {
    if (_busy) return const ActionResult.ok();
    if (!hasInviteForMe) return const ActionResult.failed('There is no invitation to answer.');
    return _run(() async {
      await _repo.respondToInvite(challengeId, accept: accept);
      return accept
          ? 'Challenge accepted. It starts at the next midnight (IST).'
          : 'Invitation declined.';
    });
  }

  Future<ActionResult> _run(Future<String> Function() action) async {
    _busy = true;
    _notify();
    try {
      final message = await action();
      await _refreshAfterAction();
      return ActionResult.ok(message);
    } catch (e) {
      return ActionResult.fromError(e);
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> _refreshAfterAction() async {
    try {
      final c = await _repo.fetchChallenge(challengeId);
      if (c != null) {
        _challenge = Loadable.data(c);
        _ensureDailySubscription(c);
        _notify();
        if (c.status != ChallengeStatus.pending && c.status != ChallengeStatus.cancelled) {
          await _loadLeaderboard(quiet: true);
        }
      }
    } catch (_) {
      // The action itself succeeded; pull-to-refresh will retry the reload.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _mineSub?.cancel();
    _dailySub?.cancel();
    super.dispose();
  }
}
