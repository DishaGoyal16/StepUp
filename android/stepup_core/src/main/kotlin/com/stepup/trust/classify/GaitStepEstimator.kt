package com.stepup.trust.classify

import kotlin.math.ceil
import kotlin.math.sqrt

/**
 * Independent IMU gait-step estimator (v2 §L3.1 `imuSteps`).
 *
 * It looks ONLY at the accelerometer-derived signal `s = |a| - |g_lowpass|`; it never reads the hardware step
 * counter, so it is a genuinely independent estimate that the bucket verifier can use to cap credit.
 *
 * Method (explainable, heuristic, uncalibrated):
 *  1. 3-tap moving average of `s` (removes sample-level noise, ~5 Hz cut-off).
 *  2. A local maximum counts as a step candidate if it exceeds
 *     `max(stepPeakAbsMin, stepPeakRelK * recentRMS)` where recentRMS is an exponential tracker of the
 *     signal's own RMS (time constant [ClassifierConfig.stepRmsTauS]).
 *  3. Candidates closer than `stepMinIntervalMs` collapse to the larger one (a heel-strike followed by a
 *     toe-off bounce is ONE step). 3.5 steps/s is the physical upper limit, so no faster counting is possible.
 *
 * Streaming: feed grid samples in order with [push]; confirmed step grid indices are returned with a delay of
 * about `stepMinIntervalMs` + 2 samples, so the caller must wait [confirmationLookaheadSamples] before closing a
 * hop. Call [reset] after a data gap and [flush] at end of stream.
 */
class GaitStepEstimator(private val cfg: ClassifierConfig) {
    private val minIntervalSamples = ceil(cfg.stepMinIntervalMs / ClassifierConfig.GRID_MS).toLong()
    private val alpha = ClassifierConfig.GRID_MS / 1000.0 / cfg.stepRmsTauS

    private var emaVar = 0.0

    // raw history: r0 = s[k], r1 = s[k-1], r2 = s[k-2]
    private var r0 = Double.NaN
    private var r1 = Double.NaN
    private var r2 = Double.NaN

    // smoothed history: y(k-1) = c, y(k-2) = b, y(k-3) = a (after the update in push())
    private var yPrev = Double.NaN
    private var yPrev2 = Double.NaN

    private var pendingIdx = Long.MIN_VALUE
    private var pendingVal = 0.0

    /** Number of steps ever confirmed (diagnostics). */
    var totalSteps = 0L
        private set

    /** Forget the signal history (after a data gap). The adaptive RMS is kept. */
    fun reset() {
        r0 = Double.NaN; r1 = Double.NaN; r2 = Double.NaN
        yPrev = Double.NaN; yPrev2 = Double.NaN
        pendingIdx = Long.MIN_VALUE
    }

    /** Confirms a still-pending candidate (end of stream / before a gap). */
    fun flush(): List<Long> {
        if (pendingIdx == Long.MIN_VALUE) return emptyList()
        val p = pendingIdx
        pendingIdx = Long.MIN_VALUE
        totalSteps++
        return listOf(p)
    }

    /**
     * @param k absolute grid index of the sample (contiguous; call [reset] after a data gap)
     * @param s |a| - |g_lowpass|
     * @return grid indices of steps confirmed by this sample (usually empty)
     */
    fun push(k: Long, s: Double): List<Long> {
        val out = ArrayList<Long>(1)
        emaVar += alpha * (s * s - emaVar)
        r2 = r1; r1 = r0; r0 = s
        if (r2.isNaN()) return out
        val c = (r2 + r1 + r0) / 3.0 // smoothed value centred at k-1
        val b = yPrev                  // centred at k-2
        val a = yPrev2                 // centred at k-3
        yPrev2 = yPrev
        yPrev = c
        if (!a.isNaN() && !b.isNaN()) {
            val peakIdx = k - 2
            val thr = maxOf(cfg.stepPeakAbsMin, cfg.stepPeakRelK * sqrt(emaVar))
            if (b > a && b >= c && b >= thr) {
                if (pendingIdx != Long.MIN_VALUE && peakIdx - pendingIdx < minIntervalSamples) {
                    if (b > pendingVal) { pendingIdx = peakIdx; pendingVal = b }
                } else {
                    if (pendingIdx != Long.MIN_VALUE) { out += pendingIdx; totalSteps++ }
                    pendingIdx = peakIdx; pendingVal = b
                }
            }
        }
        // A pending candidate is final once no later sample can fall within the minimum interval of it.
        if (pendingIdx != Long.MIN_VALUE && k - pendingIdx > minIntervalSamples + 1) {
            out += pendingIdx; totalSteps++
            pendingIdx = Long.MIN_VALUE
        }
        return out
    }

    /** Extra samples a caller must wait after a hop ends before all of its steps are confirmed. */
    val confirmationLookaheadSamples: Int get() = (minIntervalSamples + 4).toInt()
}
