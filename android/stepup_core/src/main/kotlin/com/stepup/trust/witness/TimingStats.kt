package com.stepup.trust.witness

import kotlin.math.sqrt

/**
 * Spike S1 helper: measures the *delivered* sample rate and gaps of a continuous sensor from its SENSOR
 * timestamps (`samplingPeriodUs` is only a hint). Gaps > [gapThresholdMs] indicate FIFO overflow / Doze /
 * CPU suspension and therefore lost IMU evidence.
 */
class StreamTimingStats(private val gapThresholdMs: Double = 1000.0) {
    var count = 0L; private set
    var gapCount = 0L; private set
    var maxGapMs = 0.0; private set
    var totalGapMs = 0.0; private set
    private var firstTsNs = 0L
    private var lastTsNs = 0L
    private var sumDt = 0.0
    private var sumDt2 = 0.0
    private var dtN = 0L

    /** @return false if the timestamp was not strictly increasing (ignored, counted as out-of-order). */
    fun add(tsNs: Long): Boolean {
        if (count == 0L) {
            firstTsNs = tsNs; lastTsNs = tsNs; count = 1; return true
        }
        if (tsNs <= lastTsNs) {
            outOfOrder++; return false
        }
        val dtMs = (tsNs - lastTsNs) / 1_000_000.0
        if (dtMs > gapThresholdMs) {
            gapCount++; totalGapMs += dtMs
            if (dtMs > maxGapMs) maxGapMs = dtMs
        } else {
            sumDt += dtMs; sumDt2 += dtMs * dtMs; dtN++
        }
        lastTsNs = tsNs
        count++
        return true
    }

    var outOfOrder = 0L; private set

    val spanSeconds: Double get() = if (count < 2) 0.0 else (lastTsNs - firstTsNs) / 1e9

    /** Delivered rate in Hz computed over the whole span (includes gaps). */
    val overallRateHz: Double get() = if (spanSeconds <= 0.0) 0.0 else (count - 1) / spanSeconds

    /** Mean inter-sample interval (ms) excluding gaps. */
    val meanDtMs: Double get() = if (dtN == 0L) 0.0 else sumDt / dtN

    /** Standard deviation of the inter-sample interval (ms) excluding gaps = timing jitter. */
    val jitterMs: Double
        get() {
            if (dtN < 2) return 0.0
            val m = sumDt / dtN
            return sqrt(maxOf(0.0, sumDt2 / dtN - m * m))
        }

    /** Fraction of the span covered by contiguous data (1.0 = no gaps over the threshold). */
    val coverage: Double get() = if (spanSeconds <= 0.0) 0.0 else 1.0 - (totalGapMs / 1000.0) / spanSeconds

    fun summary(label: String): String =
        "%s: n=%d span=%.1fs rate=%.2fHz meanDt=%.1fms jitter=%.1fms gaps>%.0fms=%d maxGap=%.0fms coverage=%.3f outOfOrder=%d".format(
            label, count, spanSeconds, overallRateHz, meanDtMs, jitterMs, gapThresholdMs, gapCount, maxGapMs, coverage, outOfOrder,
        )
}

/**
 * Spike S2 helper: step-counter event timing. Records the lag between the event's SENSOR timestamp (time of the
 * last step in the event) and the moment it was delivered to the app, plus lump sizes.
 */
class CounterTimingStats {
    var events = 0L; private set
    var minLagMs = Double.MAX_VALUE; private set
    var maxLagMs = 0.0; private set
    var sumLagMs = 0.0; private set
    var maxDelta = 0; private set
    private var lastCumulative = -1L
    private val lumpHistogram = sortedMapOf<Int, Int>()

    /** @param lagMs deliveredAt - sensorTimestamp, both mapped to the same clock. */
    fun add(cumulative: Long, lagMs: Double) {
        events++
        sumLagMs += lagMs
        if (lagMs < minLagMs) minLagMs = lagMs
        if (lagMs > maxLagMs) maxLagMs = lagMs
        if (lastCumulative >= 0 && cumulative > lastCumulative) {
            val d = (cumulative - lastCumulative).toInt()
            if (d > maxDelta) maxDelta = d
            lumpHistogram.merge(d.coerceAtMost(20), 1, Int::plus)
        }
        lastCumulative = cumulative
    }

    val meanLagMs: Double get() = if (events == 0L) 0.0 else sumLagMs / events

    fun summary(): String =
        if (events == 0L) "StepCounter: no events"
        else "StepCounter: events=%d lag min/mean/max=%.0f/%.0f/%.0fms maxDelta=%d lumpSizes(%s)".format(
            events, minLagMs, meanLagMs, maxLagMs, maxDelta,
            lumpHistogram.entries.joinToString(",") { "${it.key}:${it.value}" },
        )
}
