package com.stepup.trust.classify

import com.stepup.trust.HopLabel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/**
 * Regression from the REAL hand-held slow-walk recording (realme RMX3990, 50 true steps, counter 52): before the
 * 2026-11-13 changes only 25 of 52 steps were credited. Two causes are covered here:
 *  1. heel-strike asymmetry gate 0.25 rejected hops with asymmetry 0.10-0.23 (hand-held arm damps the impact);
 *  2. a counter cadence BELOW the body cadence (walk start/stop artefact) was scored as shake evidence.
 */
class GenuineWalkRetentionTest {
    private val c = HopClassifier()

    private fun hop(
        dyn: Double, vec: Double, r0: Double, f0: Double, vh: Double, churn: Double, gyro: Double, rot: Double,
        sub: Double, asym: Double, purity: Double, hf: Double, g: Triple<Double, Double, Double>,
    ) = HopFeatures(
        1L, 3.0, WindowFeatures(dyn, vec, r0, f0, vh, churn, gyro, rot, sub, asym, purity, hf, g.first, g.second, g.third),
        null, true,
    )

    /** hop @1794511094000: r0 0.66, asym 0.138 (was UNKNOWN: "no heel-strike impact signature"). */
    private val lowAsymWalk = hop(
        1.148282, 1.60332, 0.661589, 1.640349, 1.006399, 23.285692, 0.501985, 0.313091, 1.025663, 0.138346,
        0.68059, 0.130751, Triple(-0.017468, 0.182561, 0.981798),
    )

    /** hop @1794511114000: last steps before the user stopped; counter cadence read 60 spm vs body ~90 spm. */
    private val walkEnd = hop(
        0.937609, 1.455334, 0.503014, 1.510901, 0.815209, 25.335059, 0.948299, 0.651602, 0.645435, 0.101078,
        0.458015, 0.25423, Triple(0.005002, 0.193136, 0.980605),
    )

    @Test fun lowAsymmetryHandHeldWalkIsNowWalk() {
        assertEquals(HopLabel.WALK, c.classify(lowAsymWalk, ClassifyContext(135.0, CarryMode.HAND_HELD)).label)
    }

    @Test fun counterBelowBodyCadenceAtWalkEndIsNoLongerShakeEvidence() {
        val v = c.classify(walkEnd, ClassifyContext(60.0, CarryMode.HAND_HELD))
        assertEquals(HopLabel.WALK, v.label)
        assertEquals(false, v.trace.contains("cadDisagree"))
    }

    @Test fun counterFarAboveBodyCadenceIsStillShakeEvidence() {
        // Injection signature: counter claims 3x the steps the body makes. Must still be penalised.
        val v = c.classify(walkEnd, ClassifyContext(270.0, CarryMode.HAND_HELD))
        assertEquals(true, v.trace.contains("cadDisagree"))
        assertNotEquals(HopLabel.WALK, v.label)
    }

    @Test fun symmetricMechanicalToneIsStillNotWalk() {
        // pure tone + asymmetry 0.10 (real hop @1794511092000): the mechanical-oscillator signature must still block it.
        val mech = hop(
            1.291411, 1.696288, 0.821743, 1.619609, 1.154216, 24.031362, 0.705946, 0.416171, 0.853798, 0.104585,
            0.870335, 0.035523, Triple(-0.083079, 0.197108, 0.975584),
        )
        assertNotEquals(HopLabel.WALK, c.classify(mech, ClassifyContext(115.0, CarryMode.HAND_HELD)).label)
    }
}
