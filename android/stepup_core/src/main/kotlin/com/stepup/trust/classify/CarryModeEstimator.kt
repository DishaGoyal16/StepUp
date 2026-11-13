package com.stepup.trust.classify

import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Sticky carry-mode estimate (v2 §L3.5) from gravity-direction statistics over ~30 s of hops.
 *
 * HYPOTHESIS ONLY (not validated): a flat phone (|gz| large) is hand-held/reading, an upright phone with a
 * stable gravity axis is in a pocket, a tumbling gravity direction suggests a bag. Until [minHops] hops have been
 * seen, and whenever the evidence is ambiguous, the mode is UNKNOWN, which makes the classifier STRICTER.
 * A new mode must be seen on [switchAfter] consecutive hops before it replaces the current one (hysteresis).
 */
class CarryModeEstimator(
    private val windowHops: Int = 15,
    private val minHops: Int = 8,
    private val switchAfter: Int = 3,
    private val maxStableDispersionDeg: Double = 40.0,
) {
    private val recent = ArrayDeque<DoubleArray>()
    var mode: CarryMode = CarryMode.UNKNOWN
        private set
    private var candidate: CarryMode = CarryMode.UNKNOWN
    private var candidateCount = 0

    fun reset() {
        recent.clear(); mode = CarryMode.UNKNOWN; candidate = CarryMode.UNKNOWN; candidateCount = 0
    }

    fun onHop(f: WindowFeatures?) {
        if (f == null) return
        val n = sqrt(f.gravX * f.gravX + f.gravY * f.gravY + f.gravZ * f.gravZ)
        if (n.isNaN() || n < 1e-6) return
        recent.addLast(doubleArrayOf(f.gravX, f.gravY, f.gravZ))
        while (recent.size > windowHops) recent.removeFirst()
        if (recent.size < minHops) return
        var mx = 0.0; var my = 0.0; var mz = 0.0
        for (v in recent) { mx += v[0]; my += v[1]; mz += v[2] }
        mx /= recent.size; my /= recent.size; mz /= recent.size
        val ml = sqrt(mx * mx + my * my + mz * mz)
        var disp = 0.0
        for (v in recent) {
            val vl = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
            val dot = if (ml < 1e-6 || vl < 1e-6) 0.0 else (v[0] * mx + v[1] * my + v[2] * mz) / (vl * ml)
            disp += Math.toDegrees(Math.acos(dot.coerceIn(-1.0, 1.0)))
        }
        disp /= recent.size
        val ux = if (ml > 1e-6) mx / ml else 0.0
        val uy = if (ml > 1e-6) my / ml else 0.0
        val uz = if (ml > 1e-6) mz / ml else 0.0
        val cand = when {
            disp > maxStableDispersionDeg -> CarryMode.BAG
            abs(uz) >= 0.7 -> CarryMode.HAND_HELD
            abs(uy) >= 0.7 || abs(ux) >= 0.7 -> CarryMode.POCKET
            else -> CarryMode.UNKNOWN
        }
        if (cand == mode) { candidate = cand; candidateCount = 0; return }
        if (cand == candidate) candidateCount++ else { candidate = cand; candidateCount = 1 }
        if (candidateCount >= switchAfter) { mode = cand; candidateCount = 0 }
    }
}
