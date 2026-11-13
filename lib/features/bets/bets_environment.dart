import '../../app_dependencies.dart';
import '../../data/bets/bets_repository.dart';
import '../../data/bets/fake_bets_read_source.dart';
import '../../data/bets/firestore_bets_read_source.dart';
import '../../data/buddies/buddy_directory.dart';

/// What the bets screens need: the repository and the shared buddy list.
///
/// One instance per [AppDependencies] (cached, so tests can obtain the same
/// fakes the app uses via [BetsEnvironment.of] before pumping the app).
class BetsEnvironment {
  BetsEnvironment._({
    required this.repository,
    required this.buddies,
    this.fakeSource,
    this.fakeBuddies,
  });

  static final Expando<BetsEnvironment> _cache = Expando<BetsEnvironment>('BetsEnvironment');

  final BetsRepository repository;
  final BuddyDirectory buddies;

  /// Only in fake mode (`deps.rawFirestore == null`).
  final FakeBetsReadSource? fakeSource;
  final FakeBuddyDirectory? fakeBuddies;

  static BetsEnvironment of(AppDependencies deps) =>
      _cache[deps] ??= BetsEnvironment._create(deps);

  factory BetsEnvironment._create(AppDependencies deps) {
    final db = deps.rawFirestore;
    if (db == null) {
      final source = FakeBetsReadSource();
      final buddies = FakeBuddyDirectory();
      return BetsEnvironment._(
        repository: FunctionsBetsRepository(
          functions: deps.functions,
          source: source,
          firestore: deps.firestore,
        ),
        buddies: buddies,
        fakeSource: source,
        fakeBuddies: buddies,
      );
    }
    return BetsEnvironment._(
      repository: FunctionsBetsRepository(
        functions: deps.functions,
        source: FirestoreBetsReadSource(db),
        firestore: deps.firestore,
      ),
      buddies: FirestoreBuddyDirectory(db),
    );
  }
}
