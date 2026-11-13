import '../../core/errors/app_exception.dart';

/// Outcome of a user action (send / accept / cancel / remove / report),
/// ready to show in a snackbar.
class BuddyActionResult {
  const BuddyActionResult.success(this.message)
      : ok = true,
        needsRefresh = false;

  const BuddyActionResult.failure(this.message, {this.needsRefresh = false}) : ok = false;

  final bool ok;
  final String message;

  /// True when the failure means the local view is out of date (for example
  /// the request was already answered) and should be reloaded.
  final bool needsRefresh;
}

/// Stable server reasons that mean the screen shows stale data.
const Set<String> _staleReasons = {
  'ALREADY_BUDDIES',
  'REQUEST_PENDING',
  'REVERSE_REQUEST_PENDING',
  'REQUEST_NOT_PENDING',
  'REQUEST_NOT_FOUND',
  'NOT_BUDDIES',
};

/// Friendly text for a failed buddy action. Uses the server reason when it is
/// one of the known ones, otherwise the generic [AppException.message].
String buddyErrorMessage(AppException e) {
  switch (e.reason) {
    case 'ALREADY_BUDDIES':
      return 'You are already buddies.';
    case 'REQUEST_PENDING':
      return 'A request to this student is already pending.';
    case 'REVERSE_REQUEST_PENDING':
      return 'This student already sent you a request. Check your incoming requests.';
    case 'REQUEST_COOLDOWN':
      return 'You can send this student another request a little later.';
    case 'TOO_MANY_PENDING_REQUESTS':
      return 'You have too many pending requests. Cancel a few and try again.';
    case 'TARGET_NOT_DISCOVERABLE':
      return 'This student is not accepting buddy requests.';
    case 'TARGET_NOT_FOUND':
      return 'We could not find this student.';
    case 'REQUEST_NOT_PENDING':
      return 'This request was already answered.';
    case 'REQUEST_NOT_FOUND':
      return 'This request no longer exists.';
    case 'NOT_BUDDIES':
      return 'You are not buddies with this student.';
    case 'CANNOT_REQUEST_SELF':
      return 'You cannot send a request to yourself.';
    case 'CANNOT_REPORT_SELF':
      return 'You cannot report yourself.';
  }
  return e.message;
}

BuddyActionResult buddyFailure(AppException e) => BuddyActionResult.failure(
      buddyErrorMessage(e),
      needsRefresh: _staleReasons.contains(e.reason),
    );
