package com.stepup.trust.counter

/**
 * One `TYPE_STEP_COUNTER` event as the app receives it.
 *
 * @property sensorTsNs raw `SensorEvent.timestamp` (nanoseconds; time of the LAST step in the event)
 * @property tsMs the sensor timestamp mapped to UTC ms ([ClockMapper]); this is what buckets are keyed by
 * @property cumulative steps since boot as reported by the hardware counter
 * @property bootCount `Settings.Global.BOOT_COUNT` when the event was handled, or -1 if unavailable
 * @property deliveredAtMs wall-clock time the app received the event. DIAGNOSTICS ONLY, never used to bucket.
 */
data class CounterEvent(
    val sensorTsNs: Long,
    val tsMs: Long,
    val cumulative: Long,
    val bootCount: Int,
    val deliveredAtMs: Long,
)

/** Persisted after every event so restarts/reboots can be detected (v2 §L2.2 step 4). */
data class CounterState(
    val bootCount: Int,
    val lastCumulative: Long,
    val lastTsMs: Long,
    val lastSensorTsNs: Long,
)

/** A counter increment attributed to the SENSOR timestamp [tsMs]. These feed the bucket verifier. */
data class StoredDelta(
    val tsMs: Long,
    val delta: Int,
    val bootCount: Int,
    val cumulative: Long,
    val sensorTsNs: Long,
    val deliveredAtMs: Long,
)

/** Steps the hardware counted while this app was not listening. DISPLAY-ONLY, never reward-eligible. */
data class GapRecord(val tsMs: Long, val steps: Int, val reason: String)

enum class CounterEventKind {
    /** Very first event ever (no stored state). Baseline only; no steps. */
    BASELINE_FIRST,

    /** First event after (re)registration / service restart. Baseline only; the missed steps become a GAP. */
    BASELINE_AFTER_RESTART,

    /** Boot count changed: the hardware counter restarted from 0. Baseline only; no credit for the jump. */
    BASELINE_REBOOT,

    /** Cumulative went DOWN without a boot-count change. Treated like a reboot. */
    BASELINE_COUNTER_RESET,

    /** Normal increment. */
    DELTA,

    /** Same (timestamp, cumulative) delivered again, or an older stale event. Ignored: cannot be credited twice. */
    DUPLICATE,
}

data class CounterResult(
    val kind: CounterEventKind,
    val delta: StoredDelta?,
    val gap: GapRecord?,
    val state: CounterState,
)

/**
 * Turns raw cumulative counter events into per-event deltas, exactly as v2 §L2.2 prescribes:
 *
 *  1. First event after (re)registration / restart / reboot is a BASELINE only (no delta).
 *  2. `cumulative < previous` or a changed boot count => reboot => new baseline.
 *  3. Steps taken while the service was not listening become a GAP (display-only).
 *  4. State is returned after every event so the caller persists it.
 *
 * Pure Kotlin; not thread-safe (the Witness serialises calls).
 */
class CounterTracker(initial: CounterState?) {
    var state: CounterState? = initial
        private set

    /** True until the first event after construction / [markRegistered] has been seen. */
    private var awaitingBaseline = true

    /** Call whenever the sensor listener is (re)registered. */
    fun markRegistered() {
        awaitingBaseline = true
    }

    /** Forget everything (Reset Test Session): next event is a fresh first baseline. */
    fun reset() {
        state = null
        awaitingBaseline = true
    }

    fun onEvent(e: CounterEvent): CounterResult {
        val prev = state
        val fresh = CounterState(e.bootCount, e.cumulative, e.tsMs, e.sensorTsNs)

        if (prev == null) {
            state = fresh
            awaitingBaseline = false
            return CounterResult(CounterEventKind.BASELINE_FIRST, null, null, fresh)
        }

        if (e.bootCount != prev.bootCount) {
            state = fresh
            awaitingBaseline = false
            return CounterResult(CounterEventKind.BASELINE_REBOOT, null, null, fresh)
        }

        // Same boot from here on.
        if (e.cumulative < prev.lastCumulative) {
            if (e.sensorTsNs <= prev.lastSensorTsNs) {
                // Older stale event delivered out of order / replayed. Never moves the baseline backwards.
                return CounterResult(CounterEventKind.DUPLICATE, null, null, prev)
            }
            state = fresh
            awaitingBaseline = false
            return CounterResult(CounterEventKind.BASELINE_COUNTER_RESET, null, null, fresh)
        }

        if (e.cumulative == prev.lastCumulative) {
            if (awaitingBaseline) {
                // The sensor re-delivered its current value on registration: that IS the baseline, no steps missed.
                val s = prev.copy(
                    lastTsMs = maxOf(prev.lastTsMs, e.tsMs),
                    lastSensorTsNs = maxOf(prev.lastSensorTsNs, e.sensorTsNs),
                )
                state = s
                awaitingBaseline = false
                return CounterResult(CounterEventKind.BASELINE_AFTER_RESTART, null, null, s)
            }
            return CounterResult(CounterEventKind.DUPLICATE, null, null, prev)
        }

        // cumulative > previous
        val increment = e.cumulative - prev.lastCumulative
        val next = CounterState(
            e.bootCount,
            e.cumulative,
            maxOf(prev.lastTsMs, e.tsMs),
            maxOf(prev.lastSensorTsNs, e.sensorTsNs),
        )
        state = next
        if (awaitingBaseline) {
            awaitingBaseline = false
            val gap = GapRecord(e.tsMs, increment.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(), "SERVICE_NOT_LISTENING")
            return CounterResult(CounterEventKind.BASELINE_AFTER_RESTART, null, gap, next)
        }
        val delta = StoredDelta(
            tsMs = e.tsMs,
            delta = increment.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
            bootCount = e.bootCount,
            cumulative = e.cumulative,
            sensorTsNs = e.sensorTsNs,
            deliveredAtMs = e.deliveredAtMs,
        )
        return CounterResult(CounterEventKind.DELTA, delta, null, next)
    }
}
