import '../../core/errors/app_exception.dart';

/// Outcome of a user action (join, leave, accept, ...) for the UI: a success
/// message or the server's / data layer's human-readable error.
class ActionResult {
  const ActionResult.ok([this.message]) : ok = true;
  const ActionResult.failed(this.message) : ok = false;

  final bool ok;
  final String? message;

  static ActionResult fromError(Object e) => ActionResult.failed(
        e is AppException ? e.message : 'Something went wrong. Please try again.',
      );
}

/// Loading / data / error of one async piece of a screen.
class Loadable<T> {
  const Loadable.loading()
      : data = null,
        error = null,
        loading = true;
  const Loadable.data(T this.data)
      : error = null,
        loading = false;
  const Loadable.failed(String this.error)
      : data = null,
        loading = false;

  final T? data;
  final String? error;
  final bool loading;

  bool get hasData => data != null;
}

String errorMessage(Object e) =>
    e is AppException ? e.message : 'Something went wrong. Please try again.';
