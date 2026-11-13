package com.stepup.trust.classify

import com.stepup.trust.testsupport.Synth
import org.junit.Test

/** Prints feature means per synthetic scenario (development aid for tuning provisional thresholds). */
class FeatureDumpTest {
    private val t0 = 1_000_000.0

    @Test fun dump() {
        val scen = linkedMapOf(
            "walkPocket1.8" to Synth.walk(t0, 60.0),
            "walkPocket1.3" to Synth.walk(t0, 60.0, stepHz = 1.3, seed = 21),
            "walkPocket2.2" to Synth.walk(t0, 60.0, stepHz = 2.2, seed = 22),
            "walkHand" to Synth.walk(t0, 60.0, stepHz = 1.9, amp = 1.7, axis = 2, gyroAmp = 0.35, seed = 11),
            "run" to Synth.walk(t0, 60.0, stepHz = 2.9, amp = 7.0, gyroAmp = 2.0, seed = 31),
            "shakeFast" to Synth.shake(t0, 60.0),
            "shakeSlow" to Synth.shake(t0, 60.0, freqHz = 1.7, strokeAmp = 6.0, tiltRad = 0.3, seed = 41),
            "shakeMech" to Synth.shake(t0, 60.0, freqHz = 1.9, strokeAmp = 5.0, tiltRad = 0.05, mechanical = true),
            "legBounce" to Synth.legBounce(t0, 60.0),
            "vehicle" to Synth.vehicle(t0, 60.0),
        )
        val sb = StringBuilder()
        sb.appendLine("%-14s %s".format("scenario", WindowFeatures.NAMES.take(12).joinToString(" ") { it.take(8).padStart(8) }))
        for ((name, sig) in scen) {
            val f = Synth.hops(sig).mapNotNull { it.features }
            val means = (0 until 12).map { i ->
                val v = f.map { it.toList()[i] }.filter { !it.isNaN() }
                if (v.isEmpty()) Double.NaN else v.average()
            }
            sb.appendLine("%-14s %s".format(name, means.joinToString(" ") { "%8.2f".format(it) }))
        }
        println("FEATUREDUMP\n$sb")
    }
}
