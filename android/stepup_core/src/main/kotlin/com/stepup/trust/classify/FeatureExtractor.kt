package com.stepup.trust.classify

import com.stepup.trust.dsp.Dsp
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.sqrt

/** The 100 grid samples (4 s @ 25 Hz) of one analysis window, oldest first. */
class WindowInput(
    /** |a| - |g_lowpass| */
    val s: DoubleArray,
    /** |a - g_lowpass| */
    val vec: DoubleArray,
    /** dynamic acceleration projected on the gravity direction */
    val av: DoubleArray,
    /** dynamic acceleration perpendicular to gravity */
    val ah: DoubleArray,
    /** |omega| per sample, or null when the gyroscope did not cover the whole window */
    val gyroMag: DoubleArray?,
    /** gravity-direction angular speed per sample, deg/s */
    val churn: DoubleArray,
    val gravUnitX: DoubleArray,
    val gravUnitY: DoubleArray,
    val gravUnitZ: DoubleArray,
)

/** Orientation-independent feature extraction (v2 §L3.2). Deterministic, no Android imports. */
object FeatureExtractor {
    private const val FS = ClassifierConfig.GRID_HZ

    fun extract(w: WindowInput, cfg: ClassifierConfig): WindowFeatures {
        val dynRms = Dsp.rms(w.s)
        val vecRms = Dsp.rms(w.vec)

        // --- periodicity of |a|-g over the gait band --------------------------------------------------------
        val minLag = ceil(FS / cfg.f0MaxHz).toInt()
        val maxLag = floor(FS / cfg.f0MinHz).toInt()
        val per = if (dynRms > 1e-6) Dsp.periodicity(w.s, minLag, maxLag) else null
        val r0 = per?.r0 ?: 0.0
        val f0 = if (per != null && per.refinedLag > 0) FS / per.refinedLag else Double.NaN
        val subHarm = if (per != null && per.r0 > 0.1 && !per.rAtDoubleLag.isNaN()) per.rAtDoubleLag / per.r0 else Double.NaN

        // --- vertical / horizontal split --------------------------------------------------------------------
        val rv = Dsp.rms(w.av)
        val rh = Dsp.rms(w.ah)
        val vh = if (rv + rh < 1e-6) Double.NaN else (rv / maxOf(rh, 1e-3)).coerceAtMost(20.0)

        // --- gravity-direction churn ------------------------------------------------------------------------
        val churn = Dsp.mean(w.churn)

        // --- gyroscope: rotation-to-translation ratio -------------------------------------------------------
        val gyroRms = w.gyroMag?.let { Dsp.rms(it) } ?: Double.NaN
        val rot = if (w.gyroMag != null && vecRms > 1e-3) gyroRms / vecRms else Double.NaN

        // --- impact asymmetry --------------------------------------------------------------------------------
        // Skewness of a negligible vertical component is noise, so it is only reported when the vertical part is a
        // meaningful share of the dynamic motion; otherwise NaN (=> the classifier's impact gate fails => UNKNOWN).
        val asym = if (rv > 0.05 && rv >= 0.3 * vecRms) abs(Dsp.skewness(w.av)) else Double.NaN

        // --- spectral purity and high-frequency share --------------------------------------------------------
        var purity = Double.NaN
        var hf = Double.NaN
        if (dynRms > 1e-6) {
            val x = Dsp.hann(w.s)
            var total = 0.0
            var near = 0.0
            var high = 0.0
            var f = 0.5
            while (f <= 12.0 + 1e-9) {
                val p = Dsp.goertzelPower(x, FS, f)
                total += p
                if (f > 4.0) high += p
                if (!f0.isNaN() && (abs(f - f0) <= 0.3 || (2 * f0 <= 12.0 && abs(f - 2 * f0) <= 0.3))) near += p
                f += 0.05
            }
            if (total > 1e-9) {
                hf = high / total
                if (!f0.isNaN()) purity = (near / total).coerceIn(0.0, 1.0)
            }
        }

        return WindowFeatures(
            dynRms = dynRms,
            vecRms = vecRms,
            r0 = r0,
            f0Hz = f0,
            vhRatio = vh,
            churnDegPerS = churn,
            gyroRms = gyroRms,
            rotRatio = rot,
            subHarmonic = subHarm,
            asymmetry = asym,
            purity = purity,
            hfFraction = hf,
            gravX = Dsp.mean(w.gravUnitX),
            gravY = Dsp.mean(w.gravUnitY),
            gravZ = Dsp.mean(w.gravUnitZ),
        )
    }

    /** Angle in degrees between two unit vectors (clamped). */
    fun angleDeg(ax: Double, ay: Double, az: Double, bx: Double, by: Double, bz: Double): Double {
        val d = (ax * bx + ay * by + az * bz).coerceIn(-1.0, 1.0)
        return Math.toDegrees(Math.acos(d))
    }

    fun norm(x: Double, y: Double, z: Double) = sqrt(x * x + y * y + z * z)
}
