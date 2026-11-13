import '../../domain/hostel.dart';
import '../../domain/hostel_seed.dart';
import 'firestore_access.dart';

/// Loads the hostel directory: the Firestore `hostels` collection (admin
/// configurable, active only) when reachable, otherwise the built-in seed
/// (display only; flagged via [HostelDirectory.isFallback]).
class HostelRepository {
  HostelRepository(this._firestore, {this.timeout = const Duration(seconds: 6)});

  final FirestoreAccess _firestore;
  final Duration timeout;

  Future<HostelDirectory> load() async {
    try {
      final live = await _firestore.fetchActiveHostels().timeout(timeout);
      if (live.isNotEmpty) {
        return HostelDirectory(hostels: live, isFallback: false);
      }
    } catch (_) {
      // Offline, not yet signed in, or denied - fall back to the seed.
    }
    return const HostelDirectory(hostels: hostelSeed, isFallback: true);
  }
}
