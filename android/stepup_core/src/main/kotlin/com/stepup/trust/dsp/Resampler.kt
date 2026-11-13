package com.stepup.trust.dsp

/**
 * Streaming linear-interpolation resampler onto an ABSOLUTE grid (`t = k * gridMs`, UTC ms) so that hop
 * boundaries (multiples of 2 s) line up with 10 s bucket boundaries regardless of when the sensor started.
 *
 * Irregular raw timestamps are expected (sensor jitter, batching). A gap between consecutive raw samples larger
 * than [maxGapMs] is NOT interpolated: the grid samples inside the gap are reported through [onGap] and are
 * treated as missing evidence (never invented).
 */
class Resampler(
    private val gridMs: Long,
    private val channels: Int,
    private val maxGapMs: Double,
    private val onSample: (k: Long, values: DoubleArray) -> Unit,
    private val onGap: (fromK: Long, toK: Long) -> Unit,
) {
    private var prevT = Double.NaN
    private var prevV = DoubleArray(channels)
    private var nextK = Long.MIN_VALUE

    /** Number of raw samples dropped because their timestamp did not advance (duplicates / out of order). */
    var droppedNonMonotonic = 0L
        private set

    fun reset() {
        prevT = Double.NaN
        nextK = Long.MIN_VALUE
    }

    fun push(tMs: Double, v: DoubleArray) {
        if (prevT.isNaN()) {
            prevT = tMs
            prevV = v.copyOf()
            nextK = Math.ceil(tMs / gridMs).toLong()
            return
        }
        if (tMs <= prevT) {
            droppedNonMonotonic++
            return
        }
        val dt = tMs - prevT
        if (dt > maxGapMs) {
            // Do not bridge the gap. Grid points strictly between the two raw samples are missing.
            val firstMissing = nextK
            val lastMissing = Math.ceil(tMs / gridMs).toLong() - 1
            if (lastMissing >= firstMissing) onGap(firstMissing, lastMissing)
            nextK = Math.ceil(tMs / gridMs).toLong()
            prevT = tMs
            prevV = v.copyOf()
            // The new raw sample may sit exactly on a grid point: emit it.
            if (nextK * gridMs.toDouble() == tMs) {
                onSample(nextK, v.copyOf())
                nextK++
            }
            return
        }
        while (nextK * gridMs.toDouble() <= tMs) {
            val tg = nextK * gridMs.toDouble()
            val a = (tg - prevT) / dt
            val out = DoubleArray(channels) { prevV[it] + a * (v[it] - prevV[it]) }
            onSample(nextK, out)
            nextK++
        }
        prevT = tMs
        prevV = v.copyOf()
    }
}
