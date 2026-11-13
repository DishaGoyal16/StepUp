import 'package:intl/intl.dart';

final NumberFormat _count = NumberFormat('#,##0');

/// `12,345`.
String formatCount(int n) => _count.format(n);

/// `+10` / `-50` for ledger deltas.
String formatSigned(int n) => n > 0 ? '+${_count.format(n)}' : _count.format(n);

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `13 Nov 2026` in IST (the campus timezone), or `''` for null.
String formatShortDate(DateTime? at) {
  if (at == null) return '';
  final ist = at.toUtc().add(const Duration(hours: 5, minutes: 30));
  return '${ist.day} ${_months[ist.month - 1]} ${ist.year}';
}
