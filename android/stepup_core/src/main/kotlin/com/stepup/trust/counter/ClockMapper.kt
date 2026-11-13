package com.stepup.trust.counter

import kotlin.math.abs

/**
 * Maps sensor timestamps to UTC ms:
 * `utcMs = (wallNow - elapsedNow) + sensorTsNs / 1_000_000`   (v2 §L2.2 step 2)
 *
 * The `(wallNow - elapsedNow)` offset is re-sampled at each delivery. If it jumps by more than [maxJumpMs]
 * the wall clock was adjusted: we log CLOCK_ADJUST (counted) and keep the previous offset so that bucketing
 * continues from the monotonic clock only (v2 §L2.2 step 5, T10).
 *
 * Delivery time is used ONLY to obtain the offset; it never influences which bucket an event belongs to.
 */
class ClockMapper(private val maxJumpMs: Long = 2_000L) {
    private var offsetMs: Long? = null
    var clockAdjustCount: Int = 0
        private set

    fun reset() {
        offsetMs = null
        clockAdjustCount = 0
    }

    /** Same mapping with sub-millisecond precision (used for the IMU resampler). */
    fun toUtcMsExact(sensorTsNs: Long, wallNowMs: Long, elapsedNowMs: Long): Double {
        val base = toUtcMs(0L, wallNowMs, elapsedNowMs) // updates / validates the offset
        return base + sensorTsNs / 1_000_000.0
    }

    fun toUtcMs(sensorTsNs: Long, wallNowMs: Long, elapsedNowMs: Long): Long {
        val current = wallNowMs - elapsedNowMs
        val known = offsetMs
        if (known == null) {
            offsetMs = current
        } else if (abs(current - known) > maxJumpMs) {
            clockAdjustCount++ // keep `known`
        } else {
            offsetMs = current
        }
        return (offsetMs ?: current) + sensorTsNs / 1_000_000L
    }
}
