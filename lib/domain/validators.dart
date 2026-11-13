import 'profile_enums.dart';
import 'thapar_email.dart';

/// Form validators shared by the auth and onboarding screens.
/// Each returns an error message, or `null` when the value is valid.
abstract final class Validators {
  static const int minPasswordLength = 8;

  static String? fullName(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Enter your full name';
    if (s.length < 2) return 'Name is too short';
    if (s.length > 60) return 'Name is too long';
    return null;
  }

  static String? email(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Enter your Thapar email';
    if (!ThaparEmail.isValid(s)) return 'Use your @thapar.edu email address';
    return null;
  }

  static String? password(String? v) {
    final s = v ?? '';
    if (s.isEmpty) return 'Enter a password';
    if (s.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters';
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) {
      return 'Include at least one letter and one number';
    }
    return null;
  }

  /// Login only needs a non-empty password (do not leak the rules there).
  static String? loginPassword(String? v) =>
      (v == null || v.isEmpty) ? 'Enter your password' : null;

  static String? confirmPassword(String? password, String? confirm) {
    if (confirm == null || confirm.isEmpty) return 'Re-enter your password';
    if (password != confirm) return 'Passwords do not match';
    return null;
  }

  static String? bio(String? v) {
    if ((v ?? '').length > kBioMaxLength) {
      return 'Keep it under $kBioMaxLength characters';
    }
    return null;
  }

  static String? required(Object? v, String message) {
    if (v == null) return message;
    if (v is String && v.trim().isEmpty) return message;
    if (v is Iterable && v.isEmpty) return message;
    return null;
  }
}
