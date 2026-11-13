package com.stepup.trust.dsp

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sqrt

/** Small, dependency-free DSP helpers. All functions are pure and deterministic. */
object Dsp {
    fun mean(x: DoubleArray): Double {
        if (x.isEmpty()) return 0.0
        var s = 0.0
        for (v in x) s += v
        return s / x.size
    }

    fun rms(x: DoubleArray): Double {
        if (x.isEmpty()) return 0.0
        var s = 0.0
        for (v in x) s += v * v
        return sqrt(s / x.size)
    }

    fun removeMean(x: DoubleArray): DoubleArray {
        val m = mean(x)
        return DoubleArray(x.size) { x[it] - m }
    }

    /** Sample skewness; 0.0 for (near-)constant signals. */
    fun skewness(x: DoubleArray): Double {
        if (x.size < 3) return 0.0
        val m = mean(x)
        var m2 = 0.0
        var m3 = 0.0
        for (v in x) {
            val d = v - m
            m2 += d * d
            m3 += d * d * d
        }
        m2 /= x.size
        m3 /= x.size
        if (m2 < 1e-12) return 0.0
        return m3 / (m2 * sqrt(m2))
    }

    /**
     * Autocorrelation of a mean-removed signal at [lag], normalised by the zero-lag energy and rescaled for the
     * shrinking overlap ("unbiased"), so a perfectly periodic signal gives ~1.0 at its period.
     */
    fun autocorr(xZeroMean: DoubleArray, lag: Int, energy: Double): Double {
        val n = xZeroMean.size
        if (lag <= 0 || lag >= n || energy < 1e-12) return 0.0
        var s = 0.0
        for (i in 0 until n - lag) s += xZeroMean[i] * xZeroMean[i + lag]
        return (s / energy) * n.toDouble() / (n - lag)
    }

    data class Periodicity(val r0: Double, val lag: Int, val refinedLag: Double, val rAtDoubleLag: Double)

    /**
     * Finds the dominant periodicity in [minLag, maxLag] (samples). Prefers the fundamental: if a local maximum
     * exists near half the best lag with at least 80 % of its strength, that one wins (avoids picking 2T).
     */
    fun periodicity(x: DoubleArray, minLag: Int, maxLag: Int): Periodicity? {
        if (x.size < maxLag * 2 || minLag < 2) return null
        val z = removeMean(x)
        var energy = 0.0
        for (v in z) energy += v * v
        if (energy < 1e-9) return null
        val hi = minOf(maxLag, x.size - 2)
        val r = DoubleArray(hi + 2) { if (it in 1 until x.size) autocorr(z, it, energy) else 0.0 }
        var best = -1
        var bestR = -2.0
        for (l in minLag..hi) {
            val isPeak = r[l] >= r[l - 1] && r[l] >= r[l + 1]
            if (isPeak && r[l] > bestR) { bestR = r[l]; best = l }
        }
        if (best < 0) return null
        val half = (best / 2.0).let { Math.round(it).toInt() }
        if (half >= minLag) {
            var cand = -1
            var candR = -2.0
            for (l in maxOf(minLag, half - 1)..minOf(hi, half + 1)) {
                val isPeak = r[l] >= r[l - 1] && r[l] >= r[l + 1]
                if (isPeak && r[l] > candR) { candR = r[l]; cand = l }
            }
            if (cand > 0 && candR >= 0.8 * bestR) { best = cand; bestR = candR }
        }
        var refined = best.toDouble()
        if (best in 1 until hi) {
            val a = r[best - 1]; val b = r[best]; val c = r[best + 1]
            val den = a - 2 * b + c
            if (kotlin.math.abs(den) > 1e-9) refined = best + 0.5 * (a - c) / den
        }
        val twice = if (best * 2 < x.size - 1) autocorr(z, best * 2, energy) else Double.NaN
        return Periodicity(bestR, best, refined, twice)
    }

    /** Hann window applied to a (copy of the) mean-removed signal. */
    fun hann(x: DoubleArray): DoubleArray {
        val n = x.size
        val z = removeMean(x)
        return DoubleArray(n) { z[it] * (0.5 - 0.5 * cos(2.0 * PI * it / (n - 1))) }
    }

    /** Goertzel power at frequency [f] Hz for a signal sampled at [fs] Hz. */
    fun goertzelPower(x: DoubleArray, fs: Double, f: Double): Double {
        val w = 2.0 * PI * f / fs
        val coeff = 2.0 * cos(w)
        var s1 = 0.0
        var s2 = 0.0
        for (v in x) {
            val s0 = v + coeff * s1 - s2
            s2 = s1
            s1 = s0
        }
        return s1 * s1 + s2 * s2 - coeff * s1 * s2
    }
}
