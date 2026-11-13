import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/buddies/buddy_directory.dart';
import '../../data/challenges/challenge_repository.dart';
import 'action_result.dart';

/// State of the "challenge a buddy" form (`createBuddyChallenge`).
class CreateBuddyChallengeViewModel extends ChangeNotifier {
  CreateBuddyChallengeViewModel({
    required ChallengeRepository repository,
    required this.uid,
    this.initialBuddyUid,
    int initialDays = 3,
    int? initialTarget = 20000,
  })  : _repo = repository,
        _days = initialDays,
        _targetSteps = initialTarget;

  static const int minDays = 1;
  static const int maxDays = 30;
  static const int minTarget = 1000;
  static const int maxTarget = 1000000;
  static const int maxTitle = 80;

  final ChallengeRepository _repo;
  final String uid;

  /// From `?buddy=<uid>`.
  final String? initialBuddyUid;

  Loadable<List<BuddySummary>> _buddies = const Loadable.loading();
  String? _selected;
  String _title = '';
  int _days;
  int? _targetSteps;
  bool _submitting = false;
  bool _attempted = false;
  bool _disposed = false;
  String? _initialNotice;
  StreamSubscription<List<BuddySummary>>? _sub;

  Loadable<List<BuddySummary>> get buddies => _buddies;
  String? get selectedBuddyUid => _selected;
  String get title => _title;
  int get durationDays => _days;
  int? get targetSteps => _targetSteps;
  bool get submitting => _submitting;

  /// Set when `?buddy=` named someone who is not an accepted buddy.
  String? get initialNotice => _initialNotice;

  BuddySummary? get selectedBuddy {
    final id = _selected;
    if (id == null) return null;
    for (final b in _buddies.data ?? const <BuddySummary>[]) {
      if (b.uid == id) return b;
    }
    return null;
  }

  void start() => _subscribe();

  void _subscribe() {
    _sub?.cancel();
    _buddies = const Loadable.loading();
    _notify();
    _sub = _repo.watchBuddies(uid).listen(
      (list) {
        _buddies = Loadable.data(list);
        final wanted = initialBuddyUid;
        if (_selected == null && wanted != null) {
          if (list.any((b) => b.uid == wanted)) {
            _selected = wanted;
          } else {
            _initialNotice = 'That student is not one of your buddies yet. Choose a buddy below.';
          }
        }
        // A buddy removed meanwhile can no longer be challenged.
        if (_selected != null && !list.any((b) => b.uid == _selected)) _selected = null;
        _notify();
      },
      onError: (Object e) {
        _buddies = Loadable.failed(errorMessage(e));
        _notify();
      },
    );
  }

  void retry() => _subscribe();

  void selectBuddy(String? buddyUid) {
    _selected = buddyUid;
    _notify();
  }

  void setTitle(String v) {
    _title = v;
  }

  void setDuration(int days) {
    _days = days.clamp(minDays, maxDays);
    _notify();
  }

  /// Raw text of the target field; non-numeric text makes the target invalid.
  void setTargetText(String text) {
    _targetSteps = parseTarget(text);
    _notify();
  }

  static int? parseTarget(String text) {
    final cleaned = text.replaceAll(',', '').replaceAll(' ', '').trim();
    if (cleaned.isEmpty) return null;
    return int.tryParse(cleaned);
  }

  /// `null` when valid.
  static String? validateTarget(int? v) {
    if (v == null) return 'Enter the number of steps to reach';
    if (v < minTarget) return 'At least 1,000 steps';
    if (v > maxTarget) return 'At most 1,000,000 steps';
    return null;
  }

  String? get buddyError => _attempted && _selected == null ? 'Choose a buddy to challenge' : null;

  String? get targetError => (_attempted || _targetSteps != null) ? validateTarget(_targetSteps) : null;

  bool get isValid => _selected != null && validateTarget(_targetSteps) == null;

  /// Sends the invitation. Returns the new challenge id on success; duplicate
  /// taps while running are ignored.
  Future<({ActionResult result, String? challengeId})> submit() async {
    if (_submitting) return (result: const ActionResult.ok(), challengeId: null);
    _attempted = true;
    if (!isValid) {
      _notify();
      return (result: const ActionResult.failed('Please fix the highlighted fields.'), challengeId: null);
    }
    _submitting = true;
    _notify();
    try {
      final id = await _repo.createBuddyChallenge(
        buddyUid: _selected!,
        title: _title,
        durationDays: _days,
        targetSteps: _targetSteps!,
      );
      return (
        result: const ActionResult.ok('Invitation sent. The challenge starts at the next midnight (IST) after your buddy accepts.'),
        challengeId: id,
      );
    } catch (e) {
      return (result: ActionResult.fromError(e), challengeId: null);
    } finally {
      _submitting = false;
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
