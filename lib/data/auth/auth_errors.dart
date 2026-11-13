import '../../core/errors/app_exception.dart';

/// Maps a Firebase Auth error [code] (without the `auth/` prefix) to a
/// friendly [AppException]. Pure so it is unit-testable.
AppException mapAuthError(String code, {String? message}) {
  final c = code.startsWith('auth/') ? code.substring(5) : code;
  final text = switch (c) {
    'email-already-in-use' =>
      'An account with this email already exists. Try signing in instead.',
    'wrong-password' ||
    'invalid-credential' ||
    'invalid-login-credentials' ||
    'user-not-found' =>
      'Incorrect email or password.',
    'weak-password' =>
      'That password is too weak. Use at least 8 characters with letters and numbers.',
    'invalid-email' => 'That email address does not look right.',
    'network-request-failed' =>
      'Network problem. Check your internet connection and try again.',
    'too-many-requests' =>
      'Too many attempts. Please wait a few minutes and try again.',
    'user-disabled' => 'This account has been disabled. Contact support.',
    'operation-not-allowed' => 'This sign-in method is not enabled.',
    'requires-recent-login' => 'Please sign in again to continue.',
    'blocking-function-error-response' ||
    'internal-error' when (message ?? '').toLowerCase().contains('thapar') =>
      'Only @thapar.edu email addresses can use StepUp.',
    'wrong-domain' => 'Only @thapar.edu email addresses can use StepUp.',
    'cancelled' => 'Sign-in was cancelled.',
    'no-user' => 'You are not signed in.',
    _ => 'Something went wrong. Please try again.',
  };
  return AppException(code: c, message: text);
}
