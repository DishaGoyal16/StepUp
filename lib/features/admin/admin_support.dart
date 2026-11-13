import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';

/// Outcome of a mutating admin action, shown in a snackbar.
class AdminResult {
  const AdminResult.ok(this.message) : ok = true;
  const AdminResult.fail(this.message) : ok = false;

  final bool ok;
  final String message;
}

/// True when the server refused because the caller is not an admin.
bool isPermissionDenied(Object e) => e is AppException && e.code == 'permission-denied';

/// Human readable message for any error from the admin data layer.
/// `permission-denied` is spelled out: the screen is only a convenience, the
/// server decides who is an admin.
String adminErrorMessage(Object e) {
  if (e is AppException) {
    if (e.code == 'permission-denied') {
      return 'Admin access required. The server did not recognise this account as an admin.';
    }
    return e.message;
  }
  return 'Something went wrong. Please try again.';
}

/// [ChangeNotifier] that ignores notifications after `dispose` (async calls
/// finishing after the screen is gone).
class SafeNotifier extends ChangeNotifier {
  bool _disposed = false;

  bool get disposed => _disposed;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Admin route paths. The first six are in `AppRoutes`; these extend them.
abstract final class AdminPaths {
  static const badges = '/admin/badges';
  static const newChallenge = '/admin/challenges/new';
}
