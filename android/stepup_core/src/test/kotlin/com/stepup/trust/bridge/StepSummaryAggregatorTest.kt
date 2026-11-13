package com.stepup.trust.bridge

import com.stepup.trust.counter.GapRecord
import com.stepup.trust.ledger.Adjustment
import com.stepup.trust.ledger.BucketRecord
import com.stepup.trust.ledger.LedgerState
import com.stepup.trust.ledger.LedgerSummary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StepSummaryAggregatorTest {
    private val day0 = 1_000_000_000L
    private val dayEnd = day0 + 86_400_000L

    private fun agg(
        b: List<BucketRecord>,
        a: List<Adjustment> = emptyList(),
        pending: Map<Long, Int> = emptyMap(),
        gaps: List<GapRecord> = emptyList(),
        s: Long = day0, e: Long = dayEnd,
    ) = StepSummaryAggregator.aggregate(b, a, pending, gaps, s, e)

    @Test fun verifiedAndPartialExcess() {
        val d = agg(listOf(
            rec(day0, 20, 20, LedgerState.VERIFIED),
            rec(day0 + 10_000, 30, 18, LedgerState.PARTIAL, "EXCESS_OVER_IMU"),
        ))
        assertEquals(38L, d.verified)
        assertEquals("partial excess counts as rejected", 12L, d.rejected)
        assertEquals("EXCESS_OVER_IMU is not suspicious", 0L, d.suspicious)
        assertEquals(50L, d.raw)
        assertTrue(d.reconciles())
    }

    @Test fun suspiciousIsSubsetOfRejectedAndOnlyForListedReasons() {
        val reasons = mapOf(
            "SHAKE_PATTERN" to true, "CADENCE_EXCEEDED" to true, "VEHICLE_MOTION" to true, "IN_VEHICLE" to true,
            "ON_BICYCLE" to true, "NO_MOTION_EVIDENCE" to false, "NOT_GAIT" to false, "NO_GAIT_STEPS" to false,
        )
        var start = day0
        var expectSuspicious = 0L; var expectRejected = 0L
        val buckets = reasons.map { (reason, susp) ->
            start += 10_000
            expectRejected += 10
            if (susp) expectSuspicious += 10
            rec(start, 10, 0, LedgerState.REJECTED, reason)
        }
        val d = agg(buckets)
        assertEquals(expectRejected, d.rejected)
        assertEquals(expectSuspicious, d.suspicious)
        assertEquals(50L, d.suspicious)
        assertTrue(d.suspicious <= d.rejected)
        assertEquals(0L, d.verified)
        assertTrue(d.reconciles())
    }

    @Test fun unwitnessedIsNeitherRejectedNorVerified() {
        val d = agg(listOf(rec(day0, 12, 0, LedgerState.UNWITNESSED, "NO_IMU_EVIDENCE")))
        assertEquals(12L, d.unwitnessed); assertEquals(0L, d.rejected); assertEquals(0L, d.verified)
        assertEquals(12L, d.raw)
    }

    @Test fun dayRangeIsHalfOpenOnBucketStart() {
        val before = rec(day0 - 10_000, 10, 10, LedgerState.VERIFIED)
        val first = rec(day0, 11, 11, LedgerState.VERIFIED)
        val last = rec(dayEnd - 10_000, 12, 12, LedgerState.VERIFIED)
        val next = rec(dayEnd, 13, 13, LedgerState.VERIFIED)
        val d = agg(listOf(before, first, last, next))
        assertEquals(23L, d.verified)
        assertEquals(23L, d.raw)
    }

    @Test fun pendingAndGapAreCountedInRangeOnly() {
        val d = agg(
            listOf(rec(day0, 10, 10, LedgerState.VERIFIED)),
            pending = mapOf(day0 + 20_000 to 7, day0 - 10_000 to 99, dayEnd to 98),
            gaps = listOf(GapRecord(day0 + 5, 40, "SERVICE_NOT_LISTENING"), GapRecord(dayEnd + 5, 500, "x")),
        )
        assertEquals(7L, d.pending)
        assertEquals(40L, d.gap)
        assertEquals(10L, d.verified)
        assertEquals("raw = settled + pending + gap", 57L, d.raw)
        assertTrue(d.reconciles())
    }

    @Test fun pendingIsNeverVerifiedOrRejected() {
        val d = agg(emptyList(), pending = mapOf(day0 to 25))
        assertEquals(25L, d.pending); assertEquals(0L, d.verified); assertEquals(0L, d.rejected); assertEquals(25L, d.raw)
    }

    @Test fun lateAdjustmentsAreIncludedConsistently() {
        // VERIFIED bucket of 20; a late event adds 5 raw / 5 credited.
        val v = rec(day0, 20, 20, LedgerState.VERIFIED)
        // REJECTED (shake) bucket of 10; a late event adds 4 raw, credited stays 0.
        val r = rec(day0 + 10_000, 10, 0, LedgerState.REJECTED, "SHAKE_PATTERN")
        val d = agg(listOf(v, r), listOf(adj(day0, 5, 5), adj(day0 + 10_000, 4, 0)))
        assertEquals(25L, d.verified)
        assertEquals(14L, d.rejected)
        assertEquals(14L, d.suspicious)
        assertEquals(39L, d.raw)
        assertTrue(d.reconciles())
    }

    @Test fun negativeLateCreditIsClampedAndNeverExceedsRaw() {
        // Late steps push a bucket over the physical ceiling: creditedAdded negative beyond what was credited.
        val v = rec(day0, 30, 30, LedgerState.VERIFIED)
        val d = agg(listOf(v), listOf(adj(day0, 10, -50)))
        assertEquals(0L, d.verified)
        assertEquals(40L, d.rejected)
        assertEquals(40L, d.raw)
        assertTrue(d.reconciles())
    }

    @Test fun lateAdjustmentOutsideRangeIsIgnored() {
        val v = rec(day0 - 10_000, 20, 20, LedgerState.VERIFIED)
        val d = agg(listOf(v), listOf(adj(day0 - 10_000, 5, 5)))
        assertEquals(0L, d.raw)
    }

    @Test fun matchesLedgerSummaryForTheWholeRange() {
        val buckets = listOf(
            rec(day0, 20, 20, LedgerState.VERIFIED),
            rec(day0 + 10_000, 30, 18, LedgerState.PARTIAL, "EXCESS_OVER_IMU"),
            rec(day0 + 20_000, 40, 0, LedgerState.REJECTED, "CADENCE_EXCEEDED"),
            rec(day0 + 30_000, 9, 0, LedgerState.UNWITNESSED, "NO_IMU_EVIDENCE"),
        )
        val adjs = listOf(adj(day0 + 10_000, 2, 1))
        val pending = mapOf(day0 + 40_000 to 6)
        val gaps = listOf(GapRecord(day0 + 50_000, 15, "SERVICE_NOT_LISTENING"))
        val d = agg(buckets, adjs, pending, gaps)
        val ls = LedgerSummary.compute(buckets, adjs, pending, 15)
        assertEquals(ls.rawAll, d.raw)
        assertEquals(ls.verifiedSteps, d.verified)
        assertEquals(ls.pendingSteps, d.pending)
        assertEquals(ls.partialExcessSteps + ls.rejectedSteps, d.rejected)
        assertEquals(ls.unwitnessedSteps, d.unwitnessed)
        assertEquals(ls.gapSteps, d.gap)
        assertEquals(40L, d.suspicious)
    }

    @Test fun toMapHasContractKeysAndLongValues() {
        val m = agg(listOf(rec(day0, 5, 5, LedgerState.VERIFIED))).toMap()
        assertEquals(setOf("raw", "verified", "pending", "rejected", "suspicious", "unwitnessed", "gap"), m.keys)
        assertTrue(m.values.all { it is Long })
        assertFalse(m.isEmpty())
    }
}
