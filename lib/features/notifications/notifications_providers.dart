import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../app_dependencies.dart';
import '../../data/notifications_center/notifications_reader.dart';

/// Providers owned by the notifications feature.
///
/// The reader uses `deps.rawFirestore`; when that is `null` (fake mode in
/// tests) an in-memory reader is used.
List<SingleChildWidget> notificationsProviders(AppDependencies deps) {
  final raw = deps.rawFirestore;
  final NotificationsReader reader =
      raw == null ? FakeNotificationsReader() : FirestoreNotificationsReader(raw);
  return [Provider<NotificationsReader>.value(value: reader)];
}
