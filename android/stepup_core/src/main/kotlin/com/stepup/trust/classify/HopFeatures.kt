package com.stepup.trust.classify

/**
 * The v2 §L3.2 features for one 4 s window. `NaN` means "could not be computed reliably" (never a guess); the
 * classifier treats NaN as "no evidence either way" for soft features and returns UNKNOWN when a feature that is
 * required for a gait decision (periodicity) is missing.
 *
 *  - [dynRms]       RMS of |a| - |g_lowpass|                       (dynamic acceleration RMS, m/s^2)
 *  - [vecRms]       RMS of |a - g_lowpass|                         (also catches pure re-orientation)
 *  - [r0]           max normalised autocorrelation, lags for 1.0-3.5 Hz (periodicity)
 *  - [f0Hz]         step frequency at that lag
 *  - [vhRatio]      RMS(vertical dynamic) / RMS(horizontal dynamic)  (gravity-projected)
 *  - [churnDegPerS] mean angular speed of the smoothed gravity direction
 *  - [gyroRms]/[rotRatio]  RMS(|omega|) and RMS(|omega|)/RMS(|a_dyn|)  (NaN without gyro)
 *  - [subHarmonic]  r(2L)/r(L): stride (left/right alternation) strength; DEVIATION from the spec's spectral
 *                   f0/2 energy, because a 4 s window has ~0.25 Hz resolution (see KNOWN_LIMITATIONS.md)
 *  - [asymmetry]    |skewness| of vertical dynamic acceleration (heel-strike impulses are skewed)
 *  - [purity]       fraction of 0.5-12 Hz energy within +-0.3 Hz of f0 and 2*f0
 *  - [hfFraction]   fraction of 0.5-12 Hz energy above 4 Hz (used by the vehicle heuristic)
 *  - [gravX..Z]     mean unit gravity vector in device axes (carry-mode estimate)
 */
data class WindowFeatures(
    val dynRms: Double,
    val vecRms: Double,
    val r0: Double,
    val f0Hz: Double,
    val vhRatio: Double,
    val churnDegPerS: Double,
    val gyroRms: Double,
    val rotRatio: Double,
    val subHarmonic: Double,
    val asymmetry: Double,
    val purity: Double,
    val hfFraction: Double,
    val gravX: Double,
    val gravY: Double,
    val gravZ: Double,
) {
    fun toList(): List<Double> = listOf(
        dynRms, vecRms, r0, f0Hz, vhRatio, churnDegPerS, gyroRms, rotRatio, subHarmonic, asymmetry, purity,
        hfFraction, gravX, gravY, gravZ,
    )

    companion object {
        val NAMES = listOf(
            "dynRms", "vecRms", "r0", "f0Hz", "vhRatio", "churnDegPerS", "gyroRms", "rotRatio", "subHarmonic",
            "asymmetry", "purity", "hfFraction", "gravX", "gravY", "gravZ",
        )

        fun fromList(l: List<Double>) = WindowFeatures(
            l[0], l[1], l[2], l[3], l[4], l[5], l[6], l[7], l[8], l[9], l[10], l[11], l[12], l[13], l[14],
        )
    }
}

/**
 * Evidence for one 2 s hop (the later half of its 4 s analysis window).
 *
 * @property startMs hop start in UTC ms (multiple of 2000) derived from SENSOR timestamps
 * @property imuSteps gait peaks the independent IMU estimator counted INSIDE this hop only
 * @property features null when the window could not be analysed; then [unknownReason] says why
 * @property hasGyro gyroscope data covered this window
 */
data class HopFeatures(
    val startMs: Long,
    val imuSteps: Double,
    val features: WindowFeatures?,
    val unknownReason: String?,
    val hasGyro: Boolean,
) {
    fun serialize(): List<String> {
        val f = features?.toList() ?: List(WindowFeatures.NAMES.size) { Double.NaN }
        return listOf(startMs.toString(), imuSteps.toString(), (unknownReason ?: ""), hasGyro.toString(), (features != null).toString()) +
            f.map { it.toString() }
    }

    companion object {
        fun deserialize(c: List<String>): HopFeatures {
            val hasFeatures = c[4].toBoolean()
            val f = if (hasFeatures) WindowFeatures.fromList(c.drop(5).map { it.toDouble() }) else null
            return HopFeatures(c[0].toLong(), c[1].toDouble(), f, c[2].ifEmpty { null }, c[3].toBoolean())
        }
    }
}
