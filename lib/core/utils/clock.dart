/// Injectable time source so that time-dependent logic (sync back-off,
/// "today" boundaries, cooldowns) can be unit tested deterministically.
abstract class Clock {
  const Clock();

  /// Current instant. Implementations should return a UTC [DateTime].
  DateTime now();
}

/// Real wall clock.
class SystemClock extends Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

/// Manually advanced clock for tests and `AppDependencies.fake()`.
class FakeClock extends Clock {
  FakeClock([DateTime? start]) : _now = (start ?? DateTime.utc(2026, 11, 13, 6)).toUtc();

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration d) => _now = _now.add(d);

  void set(DateTime value) => _now = value.toUtc();
}
