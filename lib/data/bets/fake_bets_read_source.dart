import '../../core/errors/app_exception.dart';
import '../firestore/fake_firestore_access.dart' show ReplayValue;
import 'bet_models.dart';
import 'bets_repository.dart';

/// In-memory [BetsReadSource] for tests and fake mode. Passive: it does not
/// react to callables - tests call [setBets] / [upsertBet] / [setLedger].
class FakeBetsReadSource implements BetsReadSource {
  FakeBetsReadSource({List<StepBet> bets = const [], List<LedgerEntry> ledger = const []})
      : _bets = ReplayValue(List.of(bets)),
        _ledger = List.of(ledger);

  final ReplayValue<List<StepBet>> _bets;
  List<LedgerEntry> _ledger;

  /// Number of `fetchLedger` calls (to assert pagination).
  int ledgerFetches = 0;

  /// When set, `watchBets` / `watchBet` emit this error instead of data.
  Object? streamError;

  /// Thrown (once) by the next [fetchLedger].
  Object? failNextLedger;

  void setBets(List<StepBet> bets) => _bets.value = List.of(bets);

  void upsertBet(StepBet bet) {
    final next = [for (final b in _bets.value) if (b.id != bet.id) b, bet];
    _bets.value = next;
  }

  /// Newest first, as the real query returns them.
  void setLedger(List<LedgerEntry> entries) => _ledger = List.of(entries);

  @override
  Stream<List<StepBet>> watchBets(String uid) {
    final err = streamError;
    if (err != null) return Stream.error(err);
    return _bets.stream.map((l) {
      final mine = l.where((b) => b.involves(uid)).toList()
        ..sort((a, b) => b.sortKey.compareTo(a.sortKey));
      return mine;
    });
  }

  @override
  Stream<StepBet?> watchBet(String betId) {
    final err = streamError;
    if (err != null) return Stream.error(err);
    return _bets.stream.map((l) {
      for (final b in l) {
        if (b.id == betId) return b;
      }
      return null;
    });
  }

  @override
  Future<LedgerPage> fetchLedger(String uid, {Object? cursor, int limit = 30}) async {
    ledgerFetches++;
    final fail = failNextLedger;
    if (fail != null) {
      failNextLedger = null;
      throw fail is AppException ? fail : AppException.fromCallable(code: 'unavailable');
    }
    final start = cursor is int ? cursor : 0;
    final end = (start + limit) > _ledger.length ? _ledger.length : start + limit;
    return LedgerPage(
      entries: _ledger.sublist(start, end),
      cursor: end,
      hasMore: end < _ledger.length,
    );
  }
}
