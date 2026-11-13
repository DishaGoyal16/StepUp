package com.stepup.trust.classify

import com.stepup.trust.HopLabel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/**
 * Regression from REAL recordings on a realme RMX3990 (not synthetic):
 * - A fast hand shake hop (hop @1794513292000) was labelled WALK (r0 0.91, asym 0.37, cadence agreed) and leaked
 *   steps in an earlier session. Its dynRms 13.8 m/s^2 and churn 260 deg/s are far above any recorded walk.
 * - Real walking hops (pocket hop @1794508926000 and hand-held hop @1794511096000) must still be WALK.
 */
class ShakeVetoTest {
    private val c = HopClassifier()

    private fun hop(
        dyn: Double, vec: Double, r0: Double, f0: Double, vh: Double, churn: Double, gyro: Double, rot: Double,
        sub: Double, asym: Double, purity: Double, hf: Double, g: Triple<Double, Double, Double>,
    ) = HopFeatures(
        1L, 4.0, WindowFeatures(dyn, vec, r0, f0, vh, churn, gyro, rot, sub, asym, purity, hf, g.first, g.second, g.third),
        null, true,
    )

    private val shakeHop = hop(
        13.778174, 17.361787, 0.90509, 2.277277, 0.51083, 259.534259, 6.617377, 0.381146, 0.93684, 0.370497,
        0.820114, 0.155567, Triple(-0.081972, 0.178916, 0.978297),
    )
    private val pocketWalk = hop(
        4.112862, 6.197816, 0.335937, 1.790518, 0.615606, 100.695782, 1.826935, 0.294771, 1.870498, 0.692867,
        0.371639, 0.49893, Triple(-0.515203, -0.854896, -0.027957),
    )
    private val handWalk = hop(
        0.949893, 1.45533, 0.594091, 1.58979, 0.856473, 23.55761, 0.890483, 0.611877, 0.674429, 0.293588,
        0.700874, 0.091686, Triple(0.012126, 0.181289, 0.982752),
    )

    @Test fun realFastShakeHopIsNowShake() {
        val v = c.classify(shakeHop, ClassifyContext(counterCadenceSpm = 120.0, carry = CarryMode.HAND_HELD))
        assertEquals(HopLabel.SHAKE, v.label)
    }

    @Test fun realWalkingHopsAreUnaffected() {
        assertEquals(HopLabel.WALK, c.classify(pocketWalk, ClassifyContext(105.0, CarryMode.POCKET)).label)
        assertEquals(HopLabel.WALK, c.classify(handWalk, ClassifyContext(95.0, CarryMode.HAND_HELD)).label)
    }

    @Test fun vetoNeedsBothSignalsExtreme() {
        // Large motion but moderate rotation (e.g. fast arm swing) is not vetoed by H3.
        val f = shakeHop.features!!
        val onlyMotion = shakeHop.copy(features = f.copy(churnDegPerS = 40.0))
        val onlyChurn = shakeHop.copy(features = f.copy(dynRms = 3.0))
        assertNotEquals("H3", c.classify(onlyMotion).trace.take(2))
        assertNotEquals("H3", c.classify(onlyChurn).trace.take(2))
    }

    @Test fun vetoThresholdsAreOverridable() {
        val off = HopClassifier(ClassifierConfig().withOverrides(mapOf("shakeVetoDynRms" to 1000.0)))
        assertNotEquals("H3", off.classify(shakeHop).trace.take(2))
    }
}
