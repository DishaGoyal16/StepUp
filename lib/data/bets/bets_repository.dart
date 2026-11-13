import 'dart:async';

import '../../core/errors/app_exception.dart';
import '../../domain/user_profile.dart';
import '../firestore/firestore_access.dart';
import '../functions/functions_client.dart';
import 'bet_models.dart';

/// Read side of the bets feature (Firestore in production, in-memory in
/// tests). Only reads that `firestore.rules` permits: own bets (participants),
/// own ledger documents.
abstract class BetsReadSource {
  /// All bets where [uid] is challenger or opponent, newest first.
  Stream<List<StepBet>> watchBets(String uid);

  /// One bet; `null` when it does not exist.
  Stream<StepBet?> watchBet(String betId);

  /// Own ledger page, newest first. Pass the previous page's `cursor`.
  Future<LedgerPage> fetchLedger(String uid, {Object? cursor, int limit = 30});
}

/// Everything the bets UI needs. Reads come from a [BetsReadSource] and the
/// user's own `users/{uid}` stream; ALL writes are callables. The client never
/// changes points, step totals or winners.
abstract class BetsRepository {
  Stream<List<StepBet>> watchBets(String uid);
  Stream<StepBet?> watchBet(String betId);

  /// Available + reserved virtual points from `users/{uid}`.
  Stream<PointsBalance> watchPoints(String uid);

  Future<LedgerPage> fetchLedger(String uid, {Object? cursor, int limit = 30});

  /// `createStepBet` - reserves the challenger's stake on the server.
  /// [requestId] makes retries idempotent (`^[A-Za-z0-9-]{8,40}$`).
  Future<CreatedBet> createBet({
    required String opponentUid,
    required int targetSteps,
    required int durationDays,
    required int stakePoints,
    String? requestId,
  });

  /// `respondStepBet` (opponent only; accepting reserves their stake).
  Future<void> respond(String betId, {required bool accept});

  /// `cancelStepBet` (challenger only, PENDING only).
  Future<void> cancel(String betId);
}

/// Production/test implementation: callables for writes.
class FunctionsBetsRepository implements BetsRepository {
  FunctionsBetsRepository({
    required FunctionsClient functions,
    required BetsReadSource source,
    required FirestoreAccess firestore,
  })  : _functions = functions,
        _source = source,
        _firestore = firestore;

  final FunctionsClient _functions;
  final BetsReadSource _source;
  final FirestoreAccess _firestore;

  @override
  Stream<List<StepBet>> watchBets(String uid) => _source.watchBets(uid);

  @override
  Stream<StepBet?> watchBet(String betId) => _source.watchBet(betId);

  @override
  Stream<PointsBalance> watchPoints(String uid) =>
      _firestore.watchUserProfile(uid).map(pointsOf);

  /// Points of a profile (`null` profile = 0, the user cannot bet anyway).
  static PointsBalance pointsOf(UserProfile? p) => p == null
      ? PointsBalance.zero
      : PointsBalance(available: p.pointsBalance, reserved: p.pointsReserved);

  @override
  Future<LedgerPage> fetchLedger(String uid, {Object? cursor, int limit = 30}) =>
      _source.fetchLedger(uid, cursor: cursor, limit: limit);

  @override
  Future<CreatedBet> createBet({
    required String opponentUid,
    required int targetSteps,
    required int durationDays,
    required int stakePoints,
    String? requestId,
  }) async {
    final r = await _functions.call('createStepBet', {
      'opponentUid': opponentUid,
      'targetSteps': targetSteps,
      'durationDays': durationDays,
      'stakePoints': stakePoints,
      'requestId': ?requestId,
    });
    final id = r['betId'];
    if (id is! String || id.isEmpty) {
      throw const AppException(
        code: 'internal',
        message: 'Something went wrong. Please try again.',
      );
    }
    return CreatedBet(betId: id, duplicate: r['duplicate'] == true);
  }

  @override
  Future<void> respond(String betId, {required bool accept}) async {
    await _functions.call('respondStepBet', {'betId': betId, 'accept': accept});
  }

  @override
  Future<void> cancel(String betId) async {
    await _functions.call('cancelStepBet', {'betId': betId});
  }
}

/// Merges the "challenger" and "opponent" query streams into one list,
/// newest first. Emits only once both have produced a value.
Stream<List<StepBet>> mergeBetStreams(Stream<List<StepBet>> a, Stream<List<StepBet>> b) {
  late StreamController<List<StepBet>> controller;
  StreamSubscription<List<StepBet>>? subA;
  StreamSubscription<List<StepBet>>? subB;
  List<StepBet>? lastA;
  List<StepBet>? lastB;

  void emit() {
    final x = lastA;
    final y = lastB;
    if (x == null || y == null) return;
    final byId = <String, StepBet>{for (final bet in x) bet.id: bet};
    for (final bet in y) {
      byId[bet.id] = bet;
    }
    final list = byId.values.toList()..sort((p, q) => q.sortKey.compareTo(p.sortKey));
    controller.add(list);
  }

  controller = StreamController<List<StepBet>>(
    onListen: () {
      subA = a.listen((v) {
        lastA = v;
        emit();
      }, onError: controller.addError);
      subB = b.listen((v) {
        lastB = v;
        emit();
      }, onError: controller.addError);
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );
  return controller.stream;
}
