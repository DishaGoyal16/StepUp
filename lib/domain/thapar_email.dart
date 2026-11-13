/// Validation of institute e-mail addresses.
///
/// Only `local@thapar.edu` is accepted: case-insensitive, surrounding
/// whitespace ignored, exact domain (no sub-domains such as `a@x.thapar.edu`,
/// no look-alikes such as `thapar.edu.evil.com`, `thapar-edu.com`,
/// `notthapar.edu`). This is the client-side layer only; the backend
/// (`beforeUserCreated`, callables, Firestore rules) re-checks it.
abstract final class ThaparEmail {
  static const String domain = 'thapar.edu';

  // Conservative local part: ASCII letters/digits with single separators
  // (. _ + -) between them; no leading/trailing/consecutive separators.
  static final RegExp _pattern =
      RegExp(r'^[a-z0-9]+(?:[._+\-][a-z0-9]+)*@thapar\.edu$');

  /// Lower-cased, trimmed form used for comparisons and account creation.
  static String normalize(String input) => input.trim().toLowerCase();

  static bool isValid(String? input) {
    if (input == null) return false;
    final value = normalize(input);
    if (value.length > 254) return false;
    return _pattern.hasMatch(value);
  }
}
