package com.stepup.trust.testsupport

import com.stepup.trust.classify.HopFeatures
import com.stepup.trust.classify.ImuHopProcessor
import com.stepup.trust.classify.ClassifierConfig
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.sin

/**
 * SYNTHETIC motion generators — TEST SOURCES ONLY. These encode my physical assumptions about each activity
 * (see v2 Appendix B caveat). Passing tests on this data proves the code follows its rules; it says NOTHING
 * about accuracy on real phones. Never reference this file from `src/main`.
 */
object Synth {
    class Frame(val tMs: Double, val a: DoubleArray, val g: DoubleArray?)

    class Signal(val frames: List<Frame>, val trueStepTimesMs: List<Double>)

    private fun pulse(tau: Double): Double =
        exp(-(tau / 0.05) * (tau / 0.05)) - 0.4 * exp(-((tau - 0.12) / 0.07) * ((tau - 0.12) / 0.07))

    private fun jitter(rnd: java.util.Random) = rnd.nextGaussian() * 0.0015 * 1000.0 // ms

    /** Gait with impact pulses on the gravity axis. [axis] 1 = y (upright pocket), 2 = z (flat in hand). */
    fun walk(
        startMs: Double, durS: Double, stepHz: Double = 1.8, amp: Double = 3.2, axis: Int = 1,
        gyroAmp: Double = 1.2, seed: Long = 1, fs: Double = 50.0, withGyro: Boolean = true,
    ): Signal {
        val rnd = java.util.Random(seed)
        val stepTimes = ArrayList<Double>()
        val amps = ArrayList<Double>()
        var i = 0
        while (true) {
            val t = startMs / 1000.0 + (i + 0.5) / stepHz + rnd.nextGaussian() * 0.02 / stepHz
            if (t > startMs / 1000.0 + durS + 0.5) break
            stepTimes += t
            amps += amp * (1.0 + 0.08 * rnd.nextGaussian()) * (if (i % 2 == 0) 1.12 else 0.90)
            i++
        }
        val strideHz = stepHz / 2
        val n = (durS * fs).toInt()
        val frames = ArrayList<Frame>(n)
        for (j in 0 until n) {
            val t = startMs + j * 1000.0 / fs + jitter(rnd)
            val ts = t / 1000.0
            var vert = 0.0
            var vertDelayed = 0.0
            for (k in stepTimes.indices) {
                val tau = ts - stepTimes[k]
                if (tau < -0.2 || tau > 0.5) continue
                vert += amps[k] * pulse(tau)
                vertDelayed += amps[k] * pulse(tau - 0.04)
            }
            val lat = 0.25 * amp * sin(2 * PI * strideHz * ts)
            val fwd = 0.4 * vertDelayed
            val a = DoubleArray(3)
            a[axis] = 9.80665 + vert + rnd.nextGaussian() * 0.12
            val other = if (axis == 1) intArrayOf(0, 2) else intArrayOf(0, 1)
            a[other[0]] = lat + rnd.nextGaussian() * 0.1
            a[other[1]] = fwd + rnd.nextGaussian() * 0.1
            val g = if (withGyro) doubleArrayOf(
                gyroAmp * sin(2 * PI * strideHz * ts + 0.5) + rnd.nextGaussian() * 0.05,
                0.2 * gyroAmp * sin(2 * PI * stepHz * ts) + rnd.nextGaussian() * 0.05,
                0.15 * gyroAmp * cos(2 * PI * strideHz * ts) + rnd.nextGaussian() * 0.05,
            ) else null
            frames += Frame(t, a, g)
        }
        return Signal(frames, stepTimes.map { it * 1000.0 }.filter { it >= startMs && it < startMs + durS * 1000 })
    }

    /** Hand shaking: linear stroke along x plus phone tilting about y, like a wrist shake. Human-like variability. */
    fun shake(
        startMs: Double, durS: Double, freqHz: Double = 2.8, strokeAmp: Double = 14.0, tiltRad: Double = 0.5,
        seed: Long = 2, fs: Double = 50.0, withGyro: Boolean = true, mechanical: Boolean = false,
    ): Signal {
        val rnd = java.util.Random(seed)
        val n = (durS * fs).toInt()
        val frames = ArrayList<Frame>(n)
        var phase = 0.0
        var ampMod = 1.0
        val times = ArrayList<Double>()
        var lastCross = -1.0
        for (j in 0 until n) {
            val t = startMs + j * 1000.0 / fs + jitter(rnd)
            if (!mechanical) {
                ampMod += 0.02 * (1.0 - ampMod) + 0.03 * rnd.nextGaussian() * 0.3
            }
            val f = if (mechanical) freqHz else freqHz * (1.0 + 0.03 * sin(2 * PI * 0.3 * t / 1000.0) + 0.01 * rnd.nextGaussian())
            phase += 2 * PI * f / fs
            val theta = tiltRad * ampMod * sin(phase + 0.7)
            val dtheta = tiltRad * ampMod * cos(phase + 0.7) * 2 * PI * f
            val lin = strokeAmp * ampMod * sin(phase)
            val a = doubleArrayOf(
                9.80665 * sin(theta) + lin + rnd.nextGaussian() * 0.15,
                rnd.nextGaussian() * 0.15,
                9.80665 * cos(theta) + rnd.nextGaussian() * 0.15,
            )
            val g = if (withGyro) doubleArrayOf(rnd.nextGaussian() * 0.05, dtheta + rnd.nextGaussian() * 0.1, rnd.nextGaussian() * 0.05) else null
            frames += Frame(t, a, g)
            val s = sin(phase)
            if (lastCross < 0 || (s >= 0 && sin(phase - 2 * PI * f / fs) < 0)) { times += t; lastCross = t }
        }
        return Signal(frames, times)
    }

    /** Seated leg bounce: pure vertical oscillation of a thigh-pocket phone, no gait impacts. */
    fun legBounce(startMs: Double, durS: Double, freqHz: Double = 2.4, amp: Double = 1.8, seed: Long = 3, fs: Double = 50.0, withGyro: Boolean = true): Signal {
        val rnd = java.util.Random(seed)
        val n = (durS * fs).toInt()
        val frames = ArrayList<Frame>(n)
        for (j in 0 until n) {
            val t = startMs + j * 1000.0 / fs + jitter(rnd)
            val ts = t / 1000.0
            val v = amp * sin(2 * PI * freqHz * ts) + 0.1 * amp * sin(2 * PI * 2 * freqHz * ts)
            val a = doubleArrayOf(rnd.nextGaussian() * 0.06, 9.80665 + v + rnd.nextGaussian() * 0.06, rnd.nextGaussian() * 0.06)
            val g = if (withGyro) doubleArrayOf(0.25 * sin(2 * PI * freqHz * ts) + rnd.nextGaussian() * 0.03, rnd.nextGaussian() * 0.03, rnd.nextGaussian() * 0.03) else null
            frames += Frame(t, a, g)
        }
        return Signal(frames, emptyList())
    }

    /** Vehicle: broadband low-level vibration + slow sway, no gait periodicity. */
    fun vehicle(startMs: Double, durS: Double, rms: Double = 0.55, seed: Long = 4, fs: Double = 50.0, withGyro: Boolean = true): Signal {
        val rnd = java.util.Random(seed)
        val n = (durS * fs).toInt()
        val frames = ArrayList<Frame>(n)
        var sway = 0.0
        for (j in 0 until n) {
            val t = startMs + j * 1000.0 / fs + jitter(rnd)
            sway += 0.02 * (rnd.nextGaussian() * 0.5 - sway)
            val a = doubleArrayOf(
                rnd.nextGaussian() * rms * 0.6 + sway,
                rnd.nextGaussian() * rms * 0.6,
                9.80665 + rnd.nextGaussian() * rms,
            )
            val g = if (withGyro) doubleArrayOf(rnd.nextGaussian() * 0.04, rnd.nextGaussian() * 0.04, rnd.nextGaussian() * 0.04) else null
            frames += Frame(t, a, g)
        }
        return Signal(frames, emptyList())
    }

    fun still(startMs: Double, durS: Double, seed: Long = 5, fs: Double = 50.0, withGyro: Boolean = true): Signal {
        val rnd = java.util.Random(seed)
        val n = (durS * fs).toInt()
        val frames = ArrayList<Frame>(n)
        for (j in 0 until n) {
            val t = startMs + j * 1000.0 / fs + jitter(rnd)
            val a = doubleArrayOf(rnd.nextGaussian() * 0.03, rnd.nextGaussian() * 0.03, 9.80665 + rnd.nextGaussian() * 0.03)
            val g = if (withGyro) doubleArrayOf(rnd.nextGaussian() * 0.005, rnd.nextGaussian() * 0.005, rnd.nextGaussian() * 0.005) else null
            frames += Frame(t, a, g)
        }
        return Signal(frames, emptyList())
    }

    fun concat(vararg parts: Signal): Signal =
        Signal(parts.flatMap { it.frames }, parts.flatMap { it.trueStepTimesMs })

    /** Runs a signal through the real production processor and returns every emitted hop. */
    fun hops(signal: Signal, cfg: ClassifierConfig = ClassifierConfig()): List<HopFeatures> {
        val out = ArrayList<HopFeatures>()
        val p = ImuHopProcessor(cfg) { out += it }
        feed(p, signal)
        p.finish()
        return out
    }

    fun feed(p: ImuHopProcessor, signal: Signal) {
        for (f in signal.frames) {
            p.onAccel(f.tMs, f.a[0], f.a[1], f.a[2])
            f.g?.let { p.onGyro(f.tMs, it[0], it[1], it[2]) }
        }
    }
}
