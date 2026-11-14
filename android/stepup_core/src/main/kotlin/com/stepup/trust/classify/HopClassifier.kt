package com.stepup.trust.classify

import com.stepup.trust.HopLabel
import kotlin.math.abs

/**
 * Context available when a hop is classified.
 *
 * @property counterCadenceSpm steps/min implied by hardware-counter steps over the same window, or NaN
 * @property arVehicle Activity Recognition says IN_VEHICLE for this hop (downgrade-only hint, v2 §2.3)
 */
data class ClassifyContext(
    val counterCadenceSpm: Double = Double.NaN,
    val carry: CarryMode = CarryMode.UNKNOWN,
    val arVehicle: Boolean = false,
)

data class HopVerdict(
    val label: HopLabel,
    /** Human-readable evidence trace, e.g. `r0=0.82(+2) vh=2.3(+1) ... walk=7.0 shake=1.0 -> WALK`. */
    val trace: String,
    val walkPoints: Double,
    val shakePoints: Double,
)

/**
 * Explainable heuristic window classifier (v2 §L3.3). Hard rules first (H1 STILL, H2 vehicle from AR), then
 * soft evidence points. Every numeric threshold comes from [ClassifierConfig] and is provisional [CAL].
 *
 * Fail-safe: whenever evidence is ambiguous or a required feature is missing the label is UNKNOWN, which the
 * bucket verifier treats as NON-walk.
 */
class HopClassifier(private val cfg: ClassifierConfig = ClassifierConfig()) {

    /** At settlement, two consecutive independent gait verdicts can corroborate nearby
     * ambiguous footfalls at the same cadence. Recovered hops never act as anchors. */
    fun classifyInterval(rows: List<Pair<HopFeatures, ClassifyContext>>, hopMs: Long): List<HopVerdict> {
        val verdicts = rows.map { (h, c) -> classify(h, c) }
        if (verdicts.any { it.label == HopLabel.SHAKE } || rows.any { it.second.arVehicle }) return verdicts
        fun gait(index: Int) = verdicts[index].label in setOf(HopLabel.WALK, HopLabel.RUN)
        val anchors = (1 until rows.size).filter { i ->
            gait(i - 1) && gait(i) && rows[i].first.startMs - rows[i - 1].first.startMs == hopMs
        }
        if (anchors.isEmpty()) return verdicts
        return rows.mapIndexed { i, (h, ctx) ->
            val v = verdicts[i]
            val f = h.features
            if (v.label != HopLabel.UNKNOWN || f == null || !h.hasGyro ||
                h.imuSteps !in 2.0..5.0 || f.dynRms !in 0.5..5.0 || f.churnDegPerS !in 0.0..120.0 ||
                f.rotRatio !in 0.0..1.2 || f.hfFraction !in 0.0..0.5 || f.purity !in 0.0..0.8 ||
                ctx.counterCadenceSpm !in 30.0..210.0 || f.f0Hz !in cfg.f0MinHz..cfg.f0MaxHz) return@mapIndexed v
            // Short windows may contain an extra detected peak. Require the hardware
            // cadence to corroborate the spectral cadence before tolerating that difference.
            val peakRateError = abs(h.imuSteps * 1000 / hopMs - f.f0Hz)
            val corroboratedCadence = f.r0 >= cfg.r0Floor && f.hfFraction <= 0.20 &&
                abs(ctx.counterCadenceSpm - 60 * f.f0Hz) <= cfg.cadenceAgreeMax * 60 * f.f0Hz
            if (peakRateError > 0.5 && !(corroboratedCadence && peakRateError <= 0.75)) return@mapIndexed v
            val supported = anchors.any { end ->
                val near = if (i < end) end - 1 else end
                val distance = abs(i - near)
                distance in 1..2 && abs(h.startMs - rows[near].first.startMs) == distance * hopMs &&
                    (minOf(i, near)..maxOf(i, near)).all { j -> verdicts[j].label == HopLabel.UNKNOWN || gait(j) } &&
                    (end - 1..end).all { j -> abs(rows[j].first.features!!.f0Hz - f.f0Hz) <= 0.25 }
            }
            if (supported) v.copy(label = HopLabel.WALK, trace = v.trace + " -> WALK (adjacent gait cadence)") else v
        }
    }

    fun classify(h: HopFeatures, ctx: ClassifyContext = ClassifyContext()): HopVerdict {
        val f = h.features
            ?: return HopVerdict(HopLabel.UNKNOWN, "no features: ${h.unknownReason ?: "UNAVAILABLE"}", 0.0, 0.0)

        if (ctx.arVehicle) return HopVerdict(HopLabel.VEHICLE, "H2: Activity Recognition says IN_VEHICLE", 0.0, 0.0)

        // H1: nothing physically moving.
        val motion = maxOf(f.dynRms, f.vecRms)
        if (motion < cfg.stillThreshold) {
            return HopVerdict(HopLabel.STILL, "H1: motion %.3f < still threshold %.3f".format(motion, cfg.stillThreshold), 0.0, 0.0)
        }

        // H3: extreme-shake veto. Both signals must be far beyond anything recorded for genuine walking
        // (real walks: dynRms <= 4.4 m/s^2 and churn <= 106 deg/s; fast shakes: >= 8.2 and >= 150). A hard rule,
        // because the capped soft scores cannot outweigh a regular ~2 Hz shake that mimics cadence and periodicity.
        if (f.dynRms >= cfg.shakeVetoDynRms && !f.churnDegPerS.isNaN() && f.churnDegPerS >= cfg.shakeVetoChurnDegPerS) {
            return HopVerdict(
                HopLabel.SHAKE,
                "H3: extreme shake dynRms=%.1f>=%.1f churn=%.0f>=%.0f".format(
                    f.dynRms, cfg.shakeVetoDynRms, f.churnDegPerS, cfg.shakeVetoChurnDegPerS,
                ),
                0.0, 0.0,
            )
        }

        val churnScale = when (ctx.carry) {
            CarryMode.POCKET -> cfg.churnScalePocket
            CarryMode.BAG -> cfg.churnScaleBag
            else -> 1.0
        }
        val vhWalkMin = when (ctx.carry) {
            CarryMode.HAND_HELD -> cfg.vhWalkMinHandHeld
            CarryMode.BAG -> cfg.vhWalkMinBag
            else -> cfg.vhWalkMin
        }

        val trace = StringBuilder()
        var walk = 0.0
        var shake = 0.0
        fun w(name: String, v: Double, pts: Double) { walk += pts; trace.append("%s=%.2f(+%.1fW) ".format(name, v, pts)) }
        fun s(name: String, v: Double, pts: Double) { shake += pts; trace.append("%s=%.2f(+%.1fS) ".format(name, v, pts)) }

        val inBand = !f.f0Hz.isNaN() && f.f0Hz >= cfg.f0MinHz && f.f0Hz <= cfg.f0MaxHz
        val periodic = f.r0 >= cfg.r0Gait && inBand
        // A pocket can damp heel impacts. Accept an alternative only when stride alternation,
        // body/counter cadence, gyro coverage and a non-mechanical spectrum corroborate it.
        // Counter agreement alone is never evidence enough (rhythmic shakes also fool the counter).
        val cadenceError = if (ctx.counterCadenceSpm > 0 && ctx.counterCadenceSpm.isFinite())
            abs(60.0 * f.f0Hz - ctx.counterCadenceSpm) / ctx.counterCadenceSpm else Double.NaN
        val strideCorroborated = cfg.strideImpactAlternative && inBand && f.r0 >= cfg.r0Floor && h.hasGyro && h.imuSteps >= 2.0 &&
            cadenceError <= 0.35 && f.subHarmonic >= cfg.subHarmWalkMin &&
            f.hfFraction <= 0.20 && f.purity < 0.90 &&
            f.dynRms in 0.5..5.0 && f.churnDegPerS <= 120.0 && f.rotRatio <= 1.2
        // Weak periodicity (real pocket/bag gait often has r0 0.2-0.35): not a veto by itself, but walk evidence
        // must then beat shake evidence by an extra margin. Below r0Floor (or out of band) it stays a hard veto.
        // Vehicle-like broadband spectra (high-frequency fraction) are never allowed through the weak path.
        val vehicleSpectrum = !f.hfFraction.isNaN() && f.hfFraction >= cfg.vehicleHfFractionMin
        val weaklyPeriodic = !periodic && inBand && f.r0 >= cfg.r0Floor && !vehicleSpectrum

        // periodicity (necessary for gait, never sufficient)
        if (f.r0 >= cfg.r0Strong && inBand) w("r0", f.r0, 2.0)
        else if (periodic) w("r0", f.r0, 1.0)

        // counter vs body cadence
        if (!ctx.counterCadenceSpm.isNaN() && ctx.counterCadenceSpm > 0 && !f.f0Hz.isNaN()) {
            val bodySpm = 60.0 * f.f0Hz
            val err = abs(bodySpm - ctx.counterCadenceSpm) / ctx.counterCadenceSpm
            if (err <= cfg.cadenceAgreeMax) w("cadAgree", err, 1.0)
            else if (err >= cfg.cadenceDisagreeMin) {
                // Counter claiming MORE steps than the body does is the injection signal. A counter that is LOWER
                // than the body cadence is expected at walk start/stop (pedometer batching, 4 s windows straddling
                // the stop) and can never earn extra credit (credit <= counter), so it is weighted separately.
                val pts = if (ctx.counterCadenceSpm > bodySpm) cfg.highCounterDisagreePoints else cfg.lowCounterDisagreePoints
                if (pts > 0.0) s("cadDisagree", err, pts)
            }
        }

        if (!f.vhRatio.isNaN()) {
            if (f.vhRatio >= vhWalkMin) w("vh", f.vhRatio, 1.0)
            else if (f.vhRatio <= cfg.vhShakeMax) s("vh", f.vhRatio, 1.0)
        }
        if (f.churnDegPerS <= cfg.churnWalkMax * churnScale) w("churn", f.churnDegPerS, 1.0)
        else if (f.churnDegPerS >= cfg.churnShakeMin * churnScale) s("churn", f.churnDegPerS, 2.0)

        if (!f.rotRatio.isNaN()) {
            if (f.rotRatio <= cfg.rotWalkMax) w("rot", f.rotRatio, 1.0)
            else if (f.rotRatio >= cfg.rotShakeMin) s("rot", f.rotRatio, 2.0)
        }
        if (!f.subHarmonic.isNaN() && f.subHarmonic >= cfg.subHarmWalkMin) w("subHarm", f.subHarmonic, 1.0)
        if (!f.asymmetry.isNaN()) {
            if (f.asymmetry >= cfg.asymWalkMin) w("asym", f.asymmetry, 2.0)
            else if (f.asymmetry <= cfg.asymShakeMax && !strideCorroborated) s("asym", f.asymmetry, 1.5)
        }
        if (!f.purity.isNaN()) {
            if (f.purity >= cfg.purityShakeMin) {
                s("purity", f.purity, 1.0)
                // pure tone AND symmetric = mechanical oscillator signature
                if (!f.asymmetry.isNaN() && f.asymmetry <= cfg.asymShakeMax && !strideCorroborated) s("mechanical", 1.0, 2.0)
            } else if (f.purity <= cfg.purityWalkMax) w("purity", f.purity, 1.0)
        }
        if (f.dynRms >= cfg.shakeRmsHigh) s("rms", f.dynRms, 1.0)

        val margin = cfg.scoreMargin + if (ctx.carry == CarryMode.UNKNOWN) cfg.unknownCarryExtraMargin else 0.0
        val tail = "walk=%.1f shake=%.1f margin=%.1f".format(walk, shake, margin)

        if (shake - walk >= cfg.scoreMargin) {
            return HopVerdict(HopLabel.SHAKE, "$trace$tail -> SHAKE", walk, shake)
        }
        if (strideCorroborated) trace.append("strideCorroborated ")
        val impactGate = strideCorroborated || cfg.asymGateMin <= 0.0 || (!f.asymmetry.isNaN() && f.asymmetry >= cfg.asymGateMin)
        val needed = margin + if (weaklyPeriodic) cfg.weakPeriodicityExtraMargin else 0.0
        if ((periodic || weaklyPeriodic) && walk - shake >= needed && impactGate) {
            val label = if (f.f0Hz >= cfg.runCadenceHz) HopLabel.RUN else HopLabel.WALK
            return HopVerdict(label, "$trace$tail -> $label", walk, shake)
        }
        val vehicleLike = !periodic && f.dynRms <= cfg.vehicleRmsMax && !f.hfFraction.isNaN() &&
            f.hfFraction >= cfg.vehicleHfFractionMin && f.churnDegPerS <= cfg.vehicleChurnMax
        if (vehicleLike) {
            return HopVerdict(HopLabel.VEHICLE, "$trace$tail vehicleHeuristic(hf=%.2f) -> VEHICLE".format(f.hfFraction), walk, shake)
        }
        val why = when {
            !periodic && !weaklyPeriodic -> "not periodic in gait band"
            !impactGate -> "no heel-strike impact signature (asym gate)"
            else -> "ambiguous evidence"
        }
        return HopVerdict(HopLabel.UNKNOWN, "$trace$tail ($why) -> UNKNOWN", walk, shake)
    }
}
