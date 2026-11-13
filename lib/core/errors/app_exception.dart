/// The single error type surfaced to the UI by the data layer
/// (callable functions, auth, native engine).
///
/// * [code]    - machine readable category (Firebase function code such as
///               `invalid-argument`, an auth code such as `wrong-password`,
///               or a local code such as `engine-unavailable`).
/// * [reason]  - stable server reason code from `details.reason` (nullable).
/// * [message] - human readable, safe to show directly in a snackbar/banner.
class AppException implements Exception {
  const AppException({required this.code, required this.message, this.reason});

  final String code;
  final String? reason;
  final String message;

  /// True when retrying later without changing anything may succeed.
  bool get isRetryable =>
      code == 'unavailable' ||
      code == 'deadline-exceeded' ||
      code == 'network-request-failed' ||
      code == 'network' ||
      code == 'internal' ||
      code == 'resource-exhausted';

  /// Maps a Firebase callable error ([code], optional server [message] and
  /// `details`) to an [AppException]. `details['reason']` is used when
  /// present. Pure Dart so it is unit-testable without Firebase types.
  factory AppException.fromCallable({
    required String code,
    String? message,
    Object? details,
  }) {
    String? reason;
    if (details is Map) {
      final r = details['reason'];
      if (r is String && r.isNotEmpty) reason = r;
    }
    final server = (message ?? '').trim();
    // Messages from our own backend for these codes are written for humans.
    const serverMessageCodes = {
      'invalid-argument',
      'failed-precondition',
      'already-exists',
      'not-found',
      'permission-denied',
      'resource-exhausted',
    };
    final useServer = server.isNotEmpty &&
        serverMessageCodes.contains(code) &&
        server.toLowerCase().replaceAll('_', '-') != code.toLowerCase() &&
        !server.toLowerCase().startsWith('internal');
    final friendly = switch (code) {
      'unauthenticated' => 'Your session has expired. Please sign in again.',
      'permission-denied' => 'You do not have permission to do that.',
      'invalid-argument' => 'Some of the details are not valid.',
      'failed-precondition' => 'That action is not available right now.',
      'already-exists' => 'That already exists.',
      'not-found' => 'We could not find what you were looking for.',
      'resource-exhausted' => 'Too many requests. Please wait a moment and try again.',
      'unavailable' ||
      'deadline-exceeded' =>
        'Network problem. Check your connection and try again.',
      'cancelled' => 'The request was cancelled.',
      _ => 'Something went wrong. Please try again.',
    };
    return AppException(
      code: code,
      reason: reason,
      message: useServer ? server : friendly,
    );
  }

  @override
  String toString() => 'AppException($code${reason == null ? '' : '/$reason'}): $message';
}
