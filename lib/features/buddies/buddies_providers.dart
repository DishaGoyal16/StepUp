import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../app_dependencies.dart';
import '../../data/buddies/buddies_repository.dart';
import '../../data/buddies/buddy_directory.dart';
import '../../data/buddies/buddy_requests_source.dart';
import '../../data/buddies/fake_buddies_repository.dart';
import '../../domain/campus_activity.dart';

/// Builds the buddies repository for [deps]: callables for writes
/// (`deps.functions`) and Firestore reads when `deps.rawFirestore` is
/// available; in fake mode (`rawFirestore == null`, tests only) the in-memory
/// sources of `fakeBuddiesBackendFor(deps)`.
BuddiesRepository buildBuddiesRepository(AppDependencies deps) {
  final db = deps.rawFirestore;
  if (db != null) {
    return CallableBuddiesRepository(
      functions: deps.functions,
      requests: FirestoreBuddyRequestsSource(db),
      directory: FirestoreBuddyDirectory(db),
    );
  }
  final fakes = fakeBuddiesBackendFor(deps);
  return CallableBuddiesRepository(
    functions: deps.functions,
    requests: fakes.requests,
    directory: fakes.directory,
  );
}

/// Providers owned by the buddies feature. Also registers the number of the
/// student's active buddies for the Home "Campus activity" block (null when it
/// cannot be read).
List<SingleChildWidget> buddiesProviders(AppDependencies deps) {
  final repo = buildBuddiesRepository(deps);
  deps.campusActivity.register(CampusSlot.buddiesAvailable, repo.activeBuddyCount);
  return [
    Provider<BuddiesRepository>.value(value: repo),
  ];
}
