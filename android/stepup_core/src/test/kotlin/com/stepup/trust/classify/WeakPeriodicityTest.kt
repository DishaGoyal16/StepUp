package com.stepup.trust.classify

import com.stepup.trust.HopLabel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/**
 * Regression for the first real-device test (realme RMX3990, slow walk, pocket/hand): genuine walking hops had
 * r0 0.21-0.35 (< r0Gait 0.35) and were all rejected as UNKNOWN. The features below are a REAL hop taken from
 * that recording (hop @1794508926000), not a synthetic signal.
 */
class WeakPeriodicityTest {
    private val classifier = HopClassifier()

    private fun realHop(r0: Double = 0.335937, hf: Double = 0.49893, f0: Double = 1.790518) = HopFeatures(
        startMs = 1794508926000L, imuSteps = 4.0, hasGyro = true, unknownReason = null,
        features = WindowFeatures(
            dynRms = 4.112862, vecRms = 6.197816, r0 = r0, f0Hz = f0, vhRatio = 0.615606,
            churnDegPerS = 100.695782, gyroRms = 1.826935, rotRatio = 0.294771, subHarmonic = 1.870498,
            asymmetry = 0.692867, purity = 0.371639, hfFraction = hf,
            gravX = -0.515203, gravY = -0.854896, gravZ = -0.027957,
        ),
    )

    private val ctx = ClassifyContext(counterCadenceSpm = 105.0, carry = CarryMode.POCKET)

    @Test fun realWeaklyPeriodicWalkHopIsNowWalk() {
        assertEquals(HopLabel.WALK, classifier.classify(realHop(), ctx).label)
    }

    @Test fun belowR0FloorIsStillNeverWalk() {
        assertNotEquals(HopLabel.WALK, classifier.classify(realHop(r0 = 0.12), ctx).label)
    }

    @Test fun vehicleLikeSpectrumCannotUseWeakPath() {
        assertNotEquals(HopLabel.WALK, classifier.classify(realHop(hf = 0.70), ctx).label)
    }

    @Test fun outOfGaitBandIsNeverWalk() {
        assertNotEquals(HopLabel.WALK, classifier.classify(realHop(f0 = 0.6), ctx).label)
    }

    @Test fun weakPathNeedsAnExtraMargin() {
        // With a huge extra margin the weak path closes, while a normally periodic hop (r0 >= r0Gait) is unaffected.
        val strict = HopClassifier(ClassifierConfig(weakPeriodicityExtraMargin = 10.0))
        assertNotEquals(HopLabel.WALK, strict.classify(realHop(r0 = 0.30), ctx).label)
        assertEquals(HopLabel.WALK, strict.classify(realHop(r0 = 0.50), ctx).label)
    }
}
