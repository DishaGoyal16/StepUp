package com.stepup.trust.classify

import com.stepup.trust.HopLabel
import com.stepup.trust.testsupport.Synth
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Behaviour of the L3 chain (resampler -> features -> classifier -> IMU step estimator) on SYNTHETIC signals.
 * These tests check the code does what its rules say; they are NOT real-world accuracy evidence.
 */
class ImuPipelineSyntheticTest {
    private val t0 = 1_000_000.0 // multiple of 2000 ms, so hops start at t0
    private val classifier = HopClassifier()

    private fun labels(hops: List<HopFeatures>, ctx: ClassifyContext = ClassifyContext(carry = CarryMode.POCKET)) =
        hops.map { classifier.classify(it, ctx).label }

    private fun settled(hops: List<HopFeatures>) = hops.filter { it.features != null }

    private fun fraction(l: List<HopLabel>, vararg want: HopLabel) =
        if (l.isEmpty()) 0.0 else l.count { it in want }.toDouble() / l.size

    // ---------------------------------------------------------------------------------------------------------
    @Test fun hopsTileTheTimelineOnTwoSecondBoundaries() {
        val hops = Synth.hops(Synth.walk(t0, 30.0))
        assertTrue(hops.isNotEmpty())
        assertTrue(hops.all { it.startMs % 2000 == 0L })
        assertEquals("hops are consecutive", hops.map { it.startMs }.zipWithNext().map { it.second - it.first }.toSet(), setOf(2000L))
    }

    @Test fun firstHopsAreWarmupUnknownNotInventedFeatures() {
        val hops = Synth.hops(Synth.walk(t0, 20.0))
        val first = hops.first()
        assertEquals(null, first.features)
        assertEquals("WARMUP", first.unknownReason)
        assertEquals(HopLabel.UNKNOWN, classifier.classify(first).label)
    }

    @Test fun featureDirectionsAreSane() {
        val walk = settled(Synth.hops(Synth.walk(t0, 40.0))).map { it.features!! }
        val shake = settled(Synth.hops(Synth.shake(t0, 40.0))).map { it.features!! }
        val still = settled(Synth.hops(Synth.still(t0, 40.0))).map { it.features!! }
        val veh = settled(Synth.hops(Synth.vehicle(t0, 40.0))).map { it.features!! }
        fun avg(l: List<WindowFeatures>, f: (WindowFeatures) -> Double) = l.map(f).filter { !it.isNaN() }.average()

        assertTrue("walk periodic", avg(walk) { it.r0 } > 0.5)
        assertEquals("walk cadence ~1.8 Hz", 1.8, avg(walk) { it.f0Hz }, 0.25)
        assertTrue("shake churns gravity more than walk", avg(shake) { it.churnDegPerS } > 2 * avg(walk) { it.churnDegPerS })
        assertTrue("shake rotates the phone harder in absolute terms", avg(shake) { it.gyroRms } > 2 * avg(walk) { it.gyroRms })
        val shakeAsym = avg(shake) { it.asymmetry }
        assertTrue("walk impacts are more skewed than a sinusoidal shake (or the shake has no vertical share => NaN)",
            shakeAsym.isNaN() || avg(walk) { it.asymmetry } > shakeAsym)
        assertTrue("walk is vertical dominant", avg(walk) { it.vhRatio } > 0.9)
        assertTrue("still is quiet", avg(still) { it.dynRms } < 0.15)
        assertTrue("vehicle is not periodic", avg(veh) { it.r0 } < 0.35)
    }

    // ---- classification ----------------------------------------------------------------------------------------
    @Test fun pocketWalkIsMostlyWalk() {
        val l = labels(settled(Synth.hops(Synth.walk(t0, 60.0))))
        println("pocket walk: " + l.groupingBy { it }.eachCount())
        assertTrue("WALK fraction ${fraction(l, HopLabel.WALK, HopLabel.RUN)}", fraction(l, HopLabel.WALK, HopLabel.RUN) >= 0.8)
        assertEquals("never SHAKE on a walk", 0, l.count { it == HopLabel.SHAKE })
    }

    @Test fun handHeldWalkIsMostlyWalk() {
        val sig = Synth.walk(t0, 60.0, stepHz = 1.9, amp = 1.7, axis = 2, gyroAmp = 0.35, seed = 11)
        val l = labels(settled(Synth.hops(sig)), ClassifyContext(carry = CarryMode.HAND_HELD))
        println("hand walk: " + l.groupingBy { it }.eachCount())
        assertTrue("WALK fraction ${fraction(l, HopLabel.WALK, HopLabel.RUN)}", fraction(l, HopLabel.WALK, HopLabel.RUN) >= 0.7)
    }

    @Test fun slowAndFastWalkAreStillWalk() {
        for ((hz, seed) in listOf(1.3 to 21L, 2.2 to 22L)) {
            val l = labels(settled(Synth.hops(Synth.walk(t0, 60.0, stepHz = hz, seed = seed))))
            println("walk @${hz}Hz: " + l.groupingBy { it }.eachCount())
            assertTrue("hz=$hz WALK fraction ${fraction(l, HopLabel.WALK, HopLabel.RUN)}", fraction(l, HopLabel.WALK, HopLabel.RUN) >= 0.75)
        }
    }

    @Test fun runningIsLabelledRun() {
        val l = labels(settled(Synth.hops(Synth.walk(t0, 60.0, stepHz = 2.9, amp = 7.0, gyroAmp = 2.0, seed = 31))))
        println("run: " + l.groupingBy { it }.eachCount())
        assertTrue(fraction(l, HopLabel.RUN) >= 0.6)
    }

    @Test fun fastHandShakeIsNeverWalk() {
        val l = labels(settled(Synth.hops(Synth.shake(t0, 60.0))), ClassifyContext(carry = CarryMode.HAND_HELD))
        println("fast shake: " + l.groupingBy { it }.eachCount())
        assertEquals("no hop of a fast shake may be WALK/RUN", 0, l.count { it == HopLabel.WALK || it == HopLabel.RUN })
        assertTrue(fraction(l, HopLabel.SHAKE) >= 0.8)
    }

    @Test fun slowRhythmicShakeIsNeverWalk() {
        val sig = Synth.shake(t0, 60.0, freqHz = 1.7, strokeAmp = 6.0, tiltRad = 0.3, seed = 41)
        for (carry in listOf(CarryMode.HAND_HELD, CarryMode.UNKNOWN)) {
            val l = labels(settled(Synth.hops(sig)), ClassifyContext(carry = carry))
            println("slow shake ($carry): " + l.groupingBy { it }.eachCount())
            assertEquals(0, l.count { it == HopLabel.WALK || it == HopLabel.RUN })
        }
    }

    @Test fun shakeWithoutGyroIsStillNotWalk() {
        val l = labels(settled(Synth.hops(Synth.shake(t0, 60.0, withGyro = false))), ClassifyContext(carry = CarryMode.UNKNOWN))
        println("fast shake no gyro: " + l.groupingBy { it }.eachCount())
        assertEquals(0, l.count { it == HopLabel.WALK || it == HopLabel.RUN })
    }

    @Test fun mechanicalPerfectShakeIsNeverWalk() {
        val l = labels(settled(Synth.hops(Synth.shake(t0, 60.0, freqHz = 1.9, strokeAmp = 5.0, tiltRad = 0.05, mechanical = true))))
        println("mechanical: " + l.groupingBy { it }.eachCount())
        assertEquals(0, l.count { it == HopLabel.WALK || it == HopLabel.RUN })
    }

    @Test fun legBounceIsNeverWalk() {
        val l = labels(settled(Synth.hops(Synth.legBounce(t0, 60.0))))
        println("leg bounce: " + l.groupingBy { it }.eachCount())
        assertEquals(0, l.count { it == HopLabel.WALK || it == HopLabel.RUN })
    }

    @Test fun vehicleVibrationIsNeverWalk() {
        val l = labels(settled(Synth.hops(Synth.vehicle(t0, 60.0))))
        println("vehicle: " + l.groupingBy { it }.eachCount())
        assertEquals(0, l.count { it == HopLabel.WALK || it == HopLabel.RUN })
        assertTrue("IMU-only vehicle heuristic fires", fraction(l, HopLabel.VEHICLE) >= 0.6)
    }

    @Test fun stillPhoneIsStill() {
        val l = labels(settled(Synth.hops(Synth.still(t0, 40.0))))
        assertTrue(fraction(l, HopLabel.STILL) >= 0.95)
    }

    @Test fun arVehicleHintDowngradesAnyHopToVehicle() {
        val hop = settled(Synth.hops(Synth.walk(t0, 30.0))).first()
        val v = classifier.classify(hop, ClassifyContext(arVehicle = true))
        assertEquals(HopLabel.VEHICLE, v.label)
    }

    @Test fun counterCadenceDisagreementIsEvidenceAgainstGait() {
        val hop = settled(Synth.hops(Synth.walk(t0, 30.0, stepHz = 1.8))).first()
        val agree = classifier.classify(hop, ClassifyContext(counterCadenceSpm = 108.0, carry = CarryMode.POCKET))
        val disagree = classifier.classify(hop, ClassifyContext(counterCadenceSpm = 40.0, carry = CarryMode.POCKET))
        assertTrue(agree.walkPoints > disagree.walkPoints || agree.shakePoints < disagree.shakePoints)
        assertNotNull(disagree.trace)
    }

    // ---- independent IMU step estimator -----------------------------------------------------------------------
    @Test fun imuStepEstimateTracksTrueStepsWithoutUsingTheCounter() {
        for ((hz, seed) in listOf(1.3 to 51L, 1.8 to 52L, 2.2 to 53L)) {
            val sig = Synth.walk(t0, 90.0, stepHz = hz, seed = seed)
            val hops = Synth.hops(sig)
            val est = hops.sumOf { it.imuSteps }
            val truth = sig.trueStepTimesMs.count { it >= t0 + 4000 && it < hops.last().startMs + 2000 } +
                sig.trueStepTimesMs.count { it < t0 + 4000 } // warmup hops still count peaks
            println("imu steps @${hz}Hz est=$est truth=$truth")
            assertEquals("hz=$hz", truth.toDouble(), est, truth * 0.15)
        }
    }

    @Test fun imuStepEstimateIsNearZeroWhenStill() {
        val est = Synth.hops(Synth.still(t0, 60.0)).sumOf { it.imuSteps }
        assertEquals(0.0, est, 1.0)
    }

    // ---- missing / degraded data ------------------------------------------------------------------------------
    @Test fun dataGapRemovesHopsInsteadOfInventingThem() {
        val a = Synth.walk(t0, 30.0, seed = 61)
        val b = Synth.walk(t0 + 45_000, 30.0, seed = 62) // 15 s of NO samples
        val hops = Synth.hops(Synth.concat(a, b))
        val starts = hops.map { it.startMs }.toSet()
        for (ms in (t0 + 32_000).toLong() until (t0 + 44_000).toLong() step 2000) {
            assertTrue("hop at $ms must not exist inside the gap", ms !in starts)
        }
    }

    @Test fun windowStraddlingAGapIsUnknownNotClassified() {
        val a = Synth.walk(t0, 30.0, seed = 71)
        val b = Synth.walk(t0 + 31_000, 30.0, seed = 72) // 1 s hole
        val hops = Synth.hops(Synth.concat(a, b))
        val bad = hops.filter { it.features == null && it.unknownReason == "WINDOW_GAP" }
        assertTrue("some hop must be flagged WINDOW_GAP", bad.isNotEmpty())
        bad.forEach { assertEquals(HopLabel.UNKNOWN, classifier.classify(it).label) }
    }

    @Test fun missingGyroIsReportedAndFeaturesAreNaNNotZero() {
        val hops = settled(Synth.hops(Synth.walk(t0, 30.0, withGyro = false)))
        assertTrue(hops.all { !it.hasGyro })
        assertTrue(hops.all { it.features!!.rotRatio.isNaN() })
    }

    @Test fun hopFeaturesSerializeRoundTrip() {
        val h = settled(Synth.hops(Synth.walk(t0, 20.0))).first()
        val back = HopFeatures.deserialize(h.serialize())
        assertEquals(h.startMs, back.startMs)
        assertEquals(h.features!!.r0, back.features!!.r0, 1e-12)
        val w = Synth.hops(Synth.walk(t0, 20.0)).first() // warmup, no features
        assertEquals(null, HopFeatures.deserialize(w.serialize()).features)
    }
}
