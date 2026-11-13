import 'dart:async';

import '../../core/errors/app_exception.dart';
import 'buddies_repository.dart';
import 'buddy_directory.dart';
import 'buddy_models.dart';
import 'buddy_requests_source.dart';

/// A stream value that replays its latest state to every new listener.
class _Replay<T> {
  _Replay(this._value);

  T _value;
  final StreamController<T> _controller = StreamController<T>.broadcast();

  T get value => _value;

  set value(T v) {
    _value = v;
    _controller.add(v);
  }

  void addError(Object e) => _controller.addError(e);

  Stream<T> get stream => Stream<T>.multi((c) {
        c.add(_value);
        final sub = _controller.stream.listen(c.add, onError: c.addError);
        c.onCancel = sub.cancel;
      }, isBroadcast: true);
}

/// In-memory [BuddyRequestsSource] for tests / fake mode.
class FakeBuddyRequestsSource implements BuddyRequestsSource {
  final _incoming = _Replay<List<BuddyRequest>>(const []);
  final _outgoing = _Replay<List<BuddyRequest>>(const []);

  void setIncoming(List<BuddyRequest> v) => _incoming.value = List.unmodifiable(v);
  void setOutgoing(List<BuddyRequest> v) => _outgoing.value = List.unmodifiable(v);

  /// Makes listeners of the incoming / outgoing stream receive an error.
  void failIncoming(Object e) => _incoming.addError(e);
  void failOutgoing(Object e) => _outgoing.addError(e);

  @override
  Stream<List<BuddyRequest>> watchIncoming(String uid) => _incoming.stream;

  @override
  Stream<List<BuddyRequest>> watchOutgoing(String uid) => _outgoing.stream;
}

/// The in-memory data sources used when `AppDependencies.rawFirestore` is
/// null (fake mode). A test seeds them with `fakeBuddiesBackendFor(deps)`.
class FakeBuddiesBackend {
  final FakeBuddyRequestsSource requests = FakeBuddyRequestsSource();
  final FakeBuddyDirectory directory = FakeBuddyDirectory();
}

final Expando<FakeBuddiesBackend> _backends = Expando<FakeBuddiesBackend>('fakeBuddiesBackend');

/// One [FakeBuddiesBackend] per [owner] (pass the `AppDependencies`), created
/// on first use so the app wiring and a test see the same instance.
FakeBuddiesBackend fakeBuddiesBackendFor(Object owner) =>
    _backends[owner] ??= FakeBuddiesBackend();

/// Complete in-memory [BuddiesRepository] (no functions client): seeds a list
/// of students, applies the search filters, paginates with a numeric cursor
/// and keeps relations consistent across send / respond / cancel / remove.
class FakeBuddiesRepository implements BuddiesRepository {
  FakeBuddiesRepository({
    this.myUid = 'me',
    List<BuddyProfile> students = const [],
    this.myName = 'Me',
  }) : _students = List.of(students);

  final String myUid;
  final String myName;
  final List<BuddyProfile> _students;
  final Map<String, List<Object>> _failures = {};
  final _incoming = _Replay<List<BuddyRequest>>(const []);
  final _outgoing = _Replay<List<BuddyRequest>>(const []);
  final _buddies = _Replay<List<BuddySummary>>(const []);

  /// Every call: `name` and its arguments.
  final List<({String name, Map<String, Object?> args})> calls = [];

  /// Gate that lets a test hold a call open: complete it to release it.
  Completer<void>? gate;

  Iterable<({String name, Map<String, Object?> args})> callsTo(String name) =>
      calls.where((c) => c.name == name);

  /// Queues an error thrown by the next call of [name] (`search`,
  /// `sendRequest`, `respond`, `cancel`, `removeBuddy`, `report`).
  void failNext(String name, Object error) => (_failures[name] ??= []).add(error);

  void setStudents(List<BuddyProfile> students) {
    _students
      ..clear()
      ..addAll(students);
  }

  BuddyProfile? student(String uid) {
    for (final s in _students) {
      if (s.uid == uid) return s;
    }
    return null;
  }

  Future<void> _enter(String name, Map<String, Object?> args) async {
    calls.add((name: name, args: args));
    final g = gate;
    if (g != null) await g.future;
    final q = _failures[name];
    if (q != null && q.isNotEmpty) throw q.removeAt(0);
  }

  bool _matches(BuddyProfile p, BuddyFilters f) {
    final q = f.query.trim().toLowerCase();
    if (q.isNotEmpty && !p.displayName.toLowerCase().contains(q)) return false;
    if (f.fitnessLevel != null && p.fitnessLevel != f.fitnessLevel) return false;
    if (f.hostelId != null && p.hostelId != f.hostelId) return false;
    if (f.preferredTime != null && p.preferredTime != f.preferredTime) return false;
    if (f.buddyType != null && p.buddyType != f.buddyType) return false;
    if (f.sports.isNotEmpty && !f.sports.any(p.sportsInterests.contains)) return false;
    if (f.goals.isNotEmpty && !f.goals.any(p.goals.contains)) return false;
    if (f.availability.isNotEmpty && !f.availability.any(p.availability.contains)) return false;
    return true;
  }

  @override
  Future<BuddySearchPage> search(BuddyFilters filters, {String? cursor, int limit = 20}) async {
    await _enter('search', {'filters': filters.toParams(), 'cursor': cursor, 'limit': limit});
    final matching = _students.where((s) => s.uid != myUid && _matches(s, filters)).toList();
    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = (start + limit).clamp(0, matching.length);
    final page = matching.sublist(start.clamp(0, matching.length), end);
    return BuddySearchPage(profiles: page, nextCursor: end < matching.length ? '$end' : null);
  }

  void _replaceStudent(String uid, BuddyProfile Function(BuddyProfile) f) {
    final i = _students.indexWhere((s) => s.uid == uid);
    if (i >= 0) _students[i] = f(_students[i]);
  }

  @override
  Future<String?> sendRequest(String toUid, {String? message}) async {
    await _enter('sendRequest', {'toUid': toUid, 'message': message});
    final id = '${myUid}_$toUid';
    _replaceStudent(toUid, (s) => s.withRelation(BuddyRelation.requestSent, requestId: id));
    final s = student(toUid);
    _outgoing.value = [
      ..._outgoing.value,
      BuddyRequest(
        id: id,
        fromUid: myUid,
        toUid: toUid,
        incoming: false,
        otherName: s?.displayName ?? 'Student',
        otherPhotoUrl: s?.photoUrl,
        message: message?.trim() ?? '',
      ),
    ];
    return id;
  }

  /// Simulates another student sending the signed-in one a request.
  void receiveRequest(String fromUid, {String message = ''}) {
    final s = student(fromUid);
    final id = '${fromUid}_$myUid';
    _replaceStudent(fromUid, (p) => p.withRelation(BuddyRelation.requestReceived, requestId: id));
    _incoming.value = [
      ..._incoming.value,
      BuddyRequest(
        id: id,
        fromUid: fromUid,
        toUid: myUid,
        incoming: true,
        otherName: s?.displayName ?? 'Student',
        otherPhotoUrl: s?.photoUrl,
        message: message,
      ),
    ];
  }

  @override
  Future<void> respond(String requestId, {required bool accept}) async {
    await _enter('respond', {'requestId': requestId, 'accept': accept});
    final req = _incoming.value.where((r) => r.id == requestId).firstOrNull;
    _incoming.value = _incoming.value.where((r) => r.id != requestId).toList();
    if (req == null) return;
    if (accept) {
      _replaceStudent(req.fromUid, (p) => p.withRelation(BuddyRelation.buddy));
      _buddies.value = [
        ..._buddies.value,
        BuddySummary(uid: req.fromUid, displayName: req.otherName, photoUrl: req.otherPhotoUrl),
      ];
    } else {
      _replaceStudent(req.fromUid, (p) => p.withRelation(BuddyRelation.none));
    }
  }

  @override
  Future<void> cancel(String requestId) async {
    await _enter('cancel', {'requestId': requestId});
    final req = _outgoing.value.where((r) => r.id == requestId).firstOrNull;
    _outgoing.value = _outgoing.value.where((r) => r.id != requestId).toList();
    if (req != null) _replaceStudent(req.toUid, (p) => p.withRelation(BuddyRelation.none));
  }

  @override
  Future<void> removeBuddy(String buddyUid) async {
    await _enter('removeBuddy', {'buddyUid': buddyUid});
    _buddies.value = _buddies.value.where((b) => b.uid != buddyUid).toList();
    _replaceStudent(buddyUid, (p) => p.withRelation(BuddyRelation.none));
  }

  /// Seeds an existing buddy.
  void addBuddy(BuddySummary b) {
    _buddies.value = [..._buddies.value, b];
    _replaceStudent(b.uid, (p) => p.withRelation(BuddyRelation.buddy));
  }

  @override
  Future<void> report(String targetUid, ReportReason reason, {String? details}) async {
    await _enter('report', {'targetUid': targetUid, 'reason': reason.wire, 'details': details});
  }

  @override
  Stream<List<BuddyRequest>> watchIncoming(String uid) => _incoming.stream;

  @override
  Stream<List<BuddyRequest>> watchOutgoing(String uid) => _outgoing.stream;

  @override
  Stream<List<BuddySummary>> watchBuddies(String uid) => _buddies.stream;

  @override
  Future<int?> activeBuddyCount(String uid) async => _buddies.value.length;

  /// Errors injected into the live streams.
  void failIncoming(Object e) => _incoming.addError(e);
  void failOutgoing(Object e) => _outgoing.addError(e);
  void failBuddies(Object e) => _buddies.addError(e);

  /// Convenience for tests that need a request failure of a given code.
  static AppException error(String code, {String? message, String? reason}) =>
      AppException.fromCallable(
        code: code,
        message: message,
        details: reason == null ? null : {'reason': reason},
      );
}
