/// Day arithmetic in `Asia/Kolkata` (UTC+05:30, no DST) - the timezone used by
/// the backend for `dayKey` (`YYYYMMDD`). Pure Dart, no timezone database
/// needed because IST has a fixed offset.
abstract final class DayKey {
  static const Duration istOffset = Duration(hours: 5, minutes: 30);

  /// Midnight (IST) at the start of the day containing [instant], expressed
  /// as a UTC [DateTime].
  static DateTime startOfDay(DateTime instant) {
    final ist = instant.toUtc().add(istOffset);
    return DateTime.utc(ist.year, ist.month, ist.day).subtract(istOffset);
  }

  /// `YYYYMMDD` of the IST calendar day containing [instant].
  static String of(DateTime instant) {
    final ist = instant.toUtc().add(istOffset);
    return '${ist.year.toString().padLeft(4, '0')}'
        '${ist.month.toString().padLeft(2, '0')}'
        '${ist.day.toString().padLeft(2, '0')}';
  }

  /// UTC instant of IST midnight at the start of [dayKey].
  static DateTime parse(String dayKey) {
    if (!RegExp(r'^\d{8}$').hasMatch(dayKey)) {
      throw FormatException('Not a dayKey (YYYYMMDD): $dayKey');
    }
    final y = int.parse(dayKey.substring(0, 4));
    final m = int.parse(dayKey.substring(4, 6));
    final d = int.parse(dayKey.substring(6, 8));
    return DateTime.utc(y, m, d).subtract(istOffset);
  }

  /// `[startMs, endMs)` of the IST day containing [instant], epoch millis.
  static ({int startMs, int endMs}) boundsMs(DateTime instant) {
    final start = startOfDay(instant);
    final end = start.add(const Duration(days: 1));
    return (
      startMs: start.millisecondsSinceEpoch,
      endMs: end.millisecondsSinceEpoch,
    );
  }

  /// The last [count] day keys ending with the day of [now], oldest first.
  static List<String> lastDays(DateTime now, int count) {
    final today = startOfDay(now);
    return [
      for (var i = count - 1; i >= 0; i--) of(today.add(const Duration(hours: 12)).subtract(Duration(days: i))),
    ];
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Short weekday (`Mon`) for a day key.
  static String weekdayShort(String dayKey) {
    final ist = parse(dayKey).add(istOffset);
    return _weekdays[ist.weekday - 1];
  }

  /// `Fri 13 Nov` style label.
  static String label(String dayKey) {
    final ist = parse(dayKey).add(istOffset);
    return '${_weekdays[ist.weekday - 1]} ${ist.day} ${_months[ist.month - 1]}';
  }
}
