package com.stepup.trust

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The nine golden vectors V1-V9 from docs/StepUp_AntiFraud_Architecture_v2.md §5 L4 / §8.1, copied from the
 * reference test. They were produced by the spec author's reference implementation of the same rule. Do NOT
 * change expectations without changing the architecture document.
 */
class BucketVerifierGoldenTest {
    private val verifier = BucketVerifier()
    private val s = 0L

    private fun hops(labels: List<HopLabel>, imuSteps: List<Double>): List<Hop> =
        labels.mapIndexed { i, label -> Hop(s + i * 2_000L, label, imuSteps[i]) }

    private fun uniform(label: HopLabel, imuSteps: Double, count: Int = 5): List<Hop> =
        hops(List(count) { label }, List(count) { imuSteps })

    @Test
    fun v1_pureWalk_isVerified() {
        val r = verifier.verify(
            s, listOf(CounterDelta(3_000, 9), CounterDelta(8_000, 9)), uniform(HopLabel.WALK, 3.6), false,
        )!!
        assertEquals(18, r.rawDelta)
        assertEquals(18, r.credited)
        assertEquals(BucketStatus.VERIFIED, r.status)
    }

    @Test
    fun v2_shake_isRejected() {
        val r = verifier.verify(
            s, listOf(CounterDelta(4_000, 13), CounterDelta(9_000, 13)), uniform(HopLabel.SHAKE, 0.0), false,
        )!!
        assertEquals(26, r.rawDelta)
        assertEquals(0, r.credited)
        assertEquals(BucketStatus.REJECTED, r.status)
        assertEquals("SHAKE_PATTERN", r.reason)
    }

    @Test
    fun v3_counterWithoutMotion_isRejected() {
        val r = verifier.verify(s, listOf(CounterDelta(5_000, 18)), uniform(HopLabel.STILL, 0.0), false)!!
        assertEquals(0, r.credited)
        assertEquals(BucketStatus.REJECTED, r.status)
        assertEquals("NO_MOTION_EVIDENCE", r.reason)
    }

    @Test
    fun v4_mixedBucket_isCappedByImuEstimate() {
        val h = hops(
            listOf(HopLabel.WALK, HopLabel.WALK, HopLabel.WALK, HopLabel.SHAKE, HopLabel.SHAKE),
            listOf(3.6, 3.6, 3.6, 0.0, 0.0),
        )
        val r = verifier.verify(s, listOf(CounterDelta(5_500, 11), CounterDelta(9_500, 13)), h, false)!!
        assertEquals(24, r.rawDelta)
        assertEquals(12, r.credited)
        assertEquals(BucketStatus.PARTIAL, r.status)
        assertEquals("EXCESS_OVER_IMU", r.reason)
    }

    @Test
    fun v5_impossibleCadence_isRejected() {
        val r = verifier.verify(s, listOf(CounterDelta(9_000, 50)), uniform(HopLabel.WALK, 7.0), false)!!
        assertEquals(0, r.credited)
        assertEquals(BucketStatus.REJECTED, r.status)
        assertEquals("CADENCE_EXCEEDED", r.reason)
    }

    @Test
    fun v6_vehicle_isRejected() {
        val r = verifier.verify(s, listOf(CounterDelta(5_000, 12)), uniform(HopLabel.WALK, 2.4), true)!!
        assertEquals(0, r.credited)
        assertEquals(BucketStatus.REJECTED, r.status)
        assertEquals("IN_VEHICLE", r.reason)
    }

    @Test
    fun v7_missingImuCoverage_isUnwitnessed() {
        val r = verifier.verify(s, listOf(CounterDelta(5_000, 18)), uniform(HopLabel.WALK, 3.6, count = 3), false)!!
        assertEquals(0, r.credited)
        assertEquals(BucketStatus.UNWITNESSED, r.status)
        assertEquals("NO_IMU_EVIDENCE", r.reason)
    }

    @Test
    fun v8_minorityWalk_isRejected() {
        val h = hops(
            listOf(HopLabel.WALK, HopLabel.WALK, HopLabel.SHAKE, HopLabel.SHAKE, HopLabel.SHAKE),
            listOf(3.6, 3.6, 0.0, 0.0, 0.0),
        )
        val r = verifier.verify(s, listOf(CounterDelta(5_000, 18)), h, false)!!
        assertEquals(0, r.credited)
        assertEquals(BucketStatus.REJECTED, r.status)
        assertEquals("SHAKE_PATTERN", r.reason)
    }

    @Test
    fun v9_emptyBucket_returnsNull() {
        assertNull(verifier.verify(s, emptyList(), uniform(HopLabel.WALK, 3.6), false))
    }
}
