package com.stepup.trust.classify

/** Carry mode estimated over 30-60 s (v2 §L3.5). Thresholds are chosen per mode; UNKNOWN is stricter. */
enum class CarryMode { POCKET, HAND_HELD, BAG, UNKNOWN }

/**
 * Every tunable of L3 in one place. ALL numeric thresholds here are **[CAL] provisional engineering estimates**
 * (v2 §0): they are NOT validated on hardware and must be fitted from real recordings with the replay harness.
 * The defaults were only tuned so the *synthetic test signals* behave sensibly; synthetic results say nothing
 * about real-world accuracy.
 *
 * Overridable by name via [withOverrides] so the replay harness can sweep them without recompiling.
 */
data class ClassifierConfig(
    // ---- signal conditioning ------------------------------------------------------------------------------
    /** Gravity low-pass cut-off (v2: ~0.3 Hz). */
    val gravityCutoffHz: Double = 0.3,
    /** Raw-sample gaps longer than this are NOT interpolated; they invalidate the affected grid samples. */
    val maxInterpGapMs: Double = 250.0,
    /** Minimum fraction of valid grid samples inside the 2 s hop for the hop to exist (else: no evidence). */
    val minHopValidFraction: Double = 0.9,
    /** Moving-average length (grid samples, 25 Hz) used for the gravity-direction churn estimate (~0.4 s). */
    val churnSmoothSamples: Int = 10,

    // ---- H1 STILL ------------------------------------------------------------------------------------------
    /** H1: dynamic RMS < max(stillMinRms, stillSigmaMult * restingSigma) => STILL. */
    val stillMinRms: Double = 0.15,
    val stillSigmaMult: Double = 5.0,
    /** Resting accelerometer noise std (m/s^2). Default is a generic MEMS guess until the device is fingerprinted. */
    val restingSigma: Double = 0.03,

    // ---- periodicity / cadence ----------------------------------------------------------------------------
    val f0MinHz: Double = 1.0,
    val f0MaxHz: Double = 3.5,
    /** Periodicity r0 needed to call a window gait-like at all (v2 parameter register: 0.35). */
    val r0Gait: Double = 0.35,
    val r0Strong: Double = 0.60,
    /** Hard periodicity floor: below this r0 a window can never be WALK/RUN. Between this and [r0Gait] it is "weakly periodic". */
    val r0Floor: Double = 0.20,
    /** Extra walk-over-shake margin required when a window is only weakly periodic (r0Floor <= r0 < r0Gait). */
    val weakPeriodicityExtraMargin: Double = 1.0,
    /** Step frequency at/above which a gait-like window is RUN rather than WALK (165 steps/min). */
    val runCadenceHz: Double = 2.75,
    /** |cadence_imu - cadence_counter| / cadence_counter below this => counter and body agree. */
    val cadenceAgreeMax: Double = 0.25,
    /** ... above this => they disagree (evidence against gait, e.g. injected counter). */
    val cadenceDisagreeMin: Double = 0.50,
    /** Shake points when the counter cadence is far ABOVE the body cadence (counter injection signature). */
    val highCounterDisagreePoints: Double = 2.0,
    /** Shake points when the counter cadence is far BELOW the body cadence (walk start/stop artefact; cannot add credit). */
    val lowCounterDisagreePoints: Double = 0.0,
    // ---- carry-mode estimator (v2 L3.5), sweepable in replay ---------------------------------------------------
    val carryWindowHops: Int = 15,
    val carryMinHops: Int = 8,
    val carrySwitchAfter: Int = 3,
    /** Counter cadence is only used when at least this many counter steps fall in the window. */
    val cadenceMinCounterSteps: Int = 3,

    // ---- soft-score thresholds (hypotheses, see v2 §3.2) ---------------------------------------------------
    val vhWalkMin: Double = 0.9,
    val vhShakeMax: Double = 0.45,
    val churnWalkMax: Double = 45.0,
    val churnShakeMin: Double = 80.0,
    val rotWalkMax: Double = 0.3,
    val rotShakeMin: Double = 1.5,
    val subHarmWalkMin: Double = 1.05,
    val asymWalkMin: Double = 0.35,
    val asymShakeMax: Double = 0.20,
    /**
     * Impact-signature GATE: a WALK/RUN label additionally REQUIRES |skewness| of vertical dynamic
     * acceleration >= this (heel-strike impulses are skewed; a symmetric push-pull shake, pendulum or leg
     * bounce is not). A missing (NaN) value fails the gate => UNKNOWN (fail-safe). Set to 0 to disable.
     */
    // 0.25 -> 0.10 (2026-11-13): real hand-held walking had skewness 0.08-0.23 (the arm damps heel strikes) and lost 7 of
    // 19 hops to this gate. Safe on the 4 real recordings only because H3 (shake veto) now catches violent shakes;
    // symmetric slow shake / leg bounce are NOT TESTED on hardware yet, so re-validate before relaxing further.
    val asymGateMin: Double = 0.10,
    val purityShakeMin: Double = 0.80,
    val purityWalkMax: Double = 0.50,
    val shakeRmsHigh: Double = 6.0,
    /** H3 hard shake veto: a hop with dynRms >= this AND churn >= [shakeVetoChurnDegPerS] is SHAKE (provisional [CAL]). */
    val shakeVetoDynRms: Double = 8.0,
    val shakeVetoChurnDegPerS: Double = 150.0,
    /** Walk evidence must beat shake evidence by this many points (or vice versa) to commit; else UNKNOWN. */
    val scoreMargin: Double = 2.0,
    /** Extra margin when the carry mode is UNKNOWN: stricter, never looser (v2 §3.5). */
    val unknownCarryExtraMargin: Double = 1.0,

    // ---- VEHICLE (IMU-only heuristic; AR is the stronger signal) -------------------------------------------
    val vehicleRmsMax: Double = 1.5,
    val vehicleHfFractionMin: Double = 0.55,
    val vehicleChurnMax: Double = 60.0,

    // ---- IMU gait-step estimator ----------------------------------------------------------------------------
    /** Minimum time between two counted steps (3.5 steps/s physical limit => 286 ms). */
    val stepMinIntervalMs: Double = 280.0,
    /** A peak must exceed this many "recent RMS" units... */
    val stepPeakRelK: Double = 0.6,
    /** ...and at least this absolute height in m/s^2. */
    val stepPeakAbsMin: Double = 0.5,
    /** Time constant of the recent-RMS tracker, seconds. */
    val stepRmsTauS: Double = 3.0,

    // ---- carry-mode multipliers ----------------------------------------------------------------------------
    val churnScalePocket: Double = 1.6,
    val churnScaleBag: Double = 1.3,
    val vhWalkMinHandHeld: Double = 0.5,
    val vhWalkMinBag: Double = 0.6,
) {
    /** The effective STILL threshold in m/s^2. */
    val stillThreshold: Double get() = maxOf(stillMinRms, stillSigmaMult * restingSigma)

    /**
     * Returns a copy with named fields replaced (used by the replay CLI: `--set r0Gait=0.4`).
     * Unknown names throw so typos never silently do nothing.
     */
    fun withOverrides(map: Map<String, Double>): ClassifierConfig {
        var c = this
        for ((k, v) in map) {
            c = when (k) {
                "gravityCutoffHz" -> c.copy(gravityCutoffHz = v)
                "maxInterpGapMs" -> c.copy(maxInterpGapMs = v)
                "minHopValidFraction" -> c.copy(minHopValidFraction = v)
                "churnSmoothSamples" -> c.copy(churnSmoothSamples = v.toInt())
                "stillMinRms" -> c.copy(stillMinRms = v)
                "stillSigmaMult" -> c.copy(stillSigmaMult = v)
                "restingSigma" -> c.copy(restingSigma = v)
                "f0MinHz" -> c.copy(f0MinHz = v)
                "f0MaxHz" -> c.copy(f0MaxHz = v)
                "r0Gait" -> c.copy(r0Gait = v)
                "r0Strong" -> c.copy(r0Strong = v)
                "r0Floor" -> c.copy(r0Floor = v)
                "weakPeriodicityExtraMargin" -> c.copy(weakPeriodicityExtraMargin = v)
                "runCadenceHz" -> c.copy(runCadenceHz = v)
                "cadenceAgreeMax" -> c.copy(cadenceAgreeMax = v)
                "cadenceDisagreeMin" -> c.copy(cadenceDisagreeMin = v)
                "highCounterDisagreePoints" -> c.copy(highCounterDisagreePoints = v)
                "lowCounterDisagreePoints" -> c.copy(lowCounterDisagreePoints = v)
                "carryWindowHops" -> c.copy(carryWindowHops = v.toInt())
                "carryMinHops" -> c.copy(carryMinHops = v.toInt())
                "carrySwitchAfter" -> c.copy(carrySwitchAfter = v.toInt())
                "cadenceMinCounterSteps" -> c.copy(cadenceMinCounterSteps = v.toInt())
                "vhWalkMin" -> c.copy(vhWalkMin = v)
                "vhShakeMax" -> c.copy(vhShakeMax = v)
                "churnWalkMax" -> c.copy(churnWalkMax = v)
                "churnShakeMin" -> c.copy(churnShakeMin = v)
                "rotWalkMax" -> c.copy(rotWalkMax = v)
                "rotShakeMin" -> c.copy(rotShakeMin = v)
                "subHarmWalkMin" -> c.copy(subHarmWalkMin = v)
                "asymWalkMin" -> c.copy(asymWalkMin = v)
                "asymShakeMax" -> c.copy(asymShakeMax = v)
                "asymGateMin" -> c.copy(asymGateMin = v)
                "purityShakeMin" -> c.copy(purityShakeMin = v)
                "purityWalkMax" -> c.copy(purityWalkMax = v)
                "shakeRmsHigh" -> c.copy(shakeRmsHigh = v)
                "shakeVetoDynRms" -> c.copy(shakeVetoDynRms = v)
                "shakeVetoChurnDegPerS" -> c.copy(shakeVetoChurnDegPerS = v)
                "scoreMargin" -> c.copy(scoreMargin = v)
                "unknownCarryExtraMargin" -> c.copy(unknownCarryExtraMargin = v)
                "vehicleRmsMax" -> c.copy(vehicleRmsMax = v)
                "vehicleHfFractionMin" -> c.copy(vehicleHfFractionMin = v)
                "vehicleChurnMax" -> c.copy(vehicleChurnMax = v)
                "stepMinIntervalMs" -> c.copy(stepMinIntervalMs = v)
                "stepPeakRelK" -> c.copy(stepPeakRelK = v)
                "stepPeakAbsMin" -> c.copy(stepPeakAbsMin = v)
                "stepRmsTauS" -> c.copy(stepRmsTauS = v)
                "churnScalePocket" -> c.copy(churnScalePocket = v)
                "churnScaleBag" -> c.copy(churnScaleBag = v)
                "vhWalkMinHandHeld" -> c.copy(vhWalkMinHandHeld = v)
                "vhWalkMinBag" -> c.copy(vhWalkMinBag = v)
                else -> throw IllegalArgumentException("Unknown ClassifierConfig parameter '$k'")
            }
        }
        return c
    }

    companion object {
        /** Fixed analysis grid: 25 Hz => 40 ms samples; hop = 50 samples (2 s); window = 100 samples (4 s). */
        const val GRID_MS = 40L
        const val HOP_SAMPLES = 50
        const val WINDOW_SAMPLES = 100
        const val HOP_MS = GRID_MS * HOP_SAMPLES // 2000
        const val GRID_HZ = 25.0
        const val STANDARD_GRAVITY = 9.80665
    }
}
