import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../app_dependencies.dart';
import '../../data/admin/admin_catalog_reader.dart';
import '../../data/admin/admin_repository.dart';
import '../../data/admin/callable_admin_repository.dart';

/// Providers owned by the admin feature: the [AdminRepository] used by every
/// admin screen (view-models are created per screen). All admin power is
/// checked by the backend (`token.admin === true`); nothing here grants it.
///
/// With real Firebase the lists come from Firestore (`rawFirestore`); in fake
/// wiring (`AppDependencies.fake`) they come from an empty in-memory reader.
List<SingleChildWidget> adminProviders(AppDependencies deps) {
  final db = deps.rawFirestore;
  final AdminCatalogReader reader =
      db != null ? FirestoreAdminCatalogReader(db) : FakeAdminCatalogReader();
  return [
    Provider<AdminRepository>(
      create: (_) => CallableAdminRepository(functions: deps.functions, reader: reader),
    ),
  ];
}
