package com.stepup.trust.bridge

import com.stepup.trust.counter.CounterEvent
import com.stepup.trust.ledger.LedgerState
import com.stepup.trust.store.FileLedgerStore
import com.stepup.trust.witness.WitnessPipeline
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class SyncLedgerTest {
    @get:Rule val tmp = TemporaryFolder()

    private val now = 10_000_000_000L
    private val b1 = now - 3_600_000L
    private val b2 = b1 + 10_000
    private val b3 = b2 + 10_000

    private fun buckets() = listOf(
        rec(b1, 12, 12, LedgerState.VERIFIED, null, walkHops(b1)),
        rec(b2, 20, 0, LedgerState.REJECTED, "SHAKE_PATTERN"),
        rec(b3, 9, 0, LedgerState.UNWITNESSED, "NO_IMU_EVIDENCE"),
    )

    private fun ledger(f: File, at: Long = now) = SyncLedger(f, nowMs = at)
    private fun known() = buckets().map { it.startMs }.toSet()

    @Test fun offersSettledBucketsOldestFirstAndHonoursLimit() {
        val l = ledger(tmp.newFile())
        assertEquals(listOf(b1, b2, b3), l.pending(buckets().reversed(), emptyList(), 200, now).map { it.startMs })
        assertEquals(listOf(b1, b2), l.pending(buckets(), emptyList(), 2, now).map { it.startMs })
        assertTrue(l.pending(buckets(), emptyList(), 0, now).isEmpty())
    }

    @Test fun ackRemovesFromPendingAndIsIdempotent() {
        val l = ledger(tmp.newFile())
        l.pending(buckets(), emptyList(), 200, now)
        assertEquals(2, l.ack(listOf(b1, b2), known(), now))
        assertEquals(listOf(b3), l.pending(buckets(), emptyList(), 200, now).map { it.startMs })
        // second, third ack of the same ids: same answer, nothing changes
        assertEquals(2, l.ack(listOf(b1, b2), known(), now))
        assertEquals(2, l.ack(listOf(b2, b1, b1), known(), now))
        assertEquals(2, l.ackedCount())
        assertEquals(listOf(b3), l.pending(buckets(), emptyList(), 200, now).map { it.startMs })
    }

    @Test fun ackOfUnknownBucketIsIgnoredAndCannotSuppressAFutureBucket() {
        val f = tmp.newFile()
        val l = ledger(f)
        assertEquals(0, l.ack(listOf(b3 + 10_000, 123L), known(), now))
        assertFalse(l.isAcked(b3 + 10_000))
        val future = rec(b3 + 10_000, 5, 5, LedgerState.VERIFIED, null, walkHops(b3 + 10_000))
        assertTrue(l.pending(buckets() + future, emptyList(), 200, now).any { it.startMs == b3 + 10_000 })
    }

    @Test fun acknowledgementsSurviveProcessRestart() {
        val f = tmp.newFile()
        val l1 = ledger(f)
        l1.pending(buckets(), emptyList(), 200, now)
        l1.ack(listOf(b1, b3), known(), now)
        val l2 = ledger(f) // "process death": new instance over the same file
        assertTrue(l2.isAcked(b1)); assertTrue(l2.isAcked(b3)); assertFalse(l2.isAcked(b2))
        assertEquals(listOf(b2), l2.pending(buckets(), emptyList(), 200, now).map { it.startMs })
    }

    @Test fun tornLastLineIsIgnoredSafely() {
        val f = tmp.newFile()
        val l1 = ledger(f)
        l1.ack(listOf(b1), known(), now)
        f.appendText("1234\tgarb") // crash mid-write
        val l2 = ledger(f)
        assertTrue(l2.isAcked(b1))
        assertEquals(1, l2.ackedCount())
    }

    @Test fun lateAdjustmentToAnAckedBucketIsSurfacedAgainWithFlagAndUpdatedTotals() {
        val f = tmp.newFile()
        val l = ledger(f)
        val first = l.pending(buckets(), emptyList(), 200, now)
        assertTrue(first.all { it.lateRawAdded == 0 })
        l.ack(first.map { it.startMs }, known(), now)
        assertTrue(l.pending(buckets(), emptyList(), 200, now).isEmpty())

        val adjs = listOf(adj(b1, 4, 4))
        val again = l.pending(buckets(), adjs, 200, now)
        assertEquals(listOf(b1), again.map { it.startMs })
        val item = again.single()
        assertEquals(16, item.rawDelta); assertEquals(16, item.credited)
        assertEquals(4, item.lateRawAdded); assertEquals(4, item.lateCreditedAdded)

        // Dart re-sends and acks the new version: gone again, also after a restart.
        l.ack(listOf(b1), known(), now)
        assertTrue(l.pending(buckets(), adjs, 200, now).isEmpty())
        assertTrue(ledger(f).pending(buckets(), adjs, 200, now).isEmpty())

        // A second late event => version 2 => surfaced once more.
        val adjs2 = adjs + adj(b1, 1, 0)
        assertEquals(listOf(b1), l.pending(buckets(), adjs2, 200, now).map { it.startMs })
    }

    @Test fun adjustmentArrivingBetweenOfferAndAckIsNotLost() {
        val l = ledger(tmp.newFile())
        l.pending(buckets(), emptyList(), 200, now) // offered with version 0
        // a late event lands while Dart is still syncing, THEN Dart acks what it was offered
        l.ack(listOf(b1, b2, b3), known(), now)
        val adjs = listOf(adj(b1, 2, 2))
        assertEquals(listOf(b1), l.pending(buckets(), adjs, 200, now).map { it.startMs })
    }

    @Test fun lostOfferMemoryCausesAtMostOneExtraOfferNeverALoss() {
        val f = tmp.newFile()
        val adjs = listOf(adj(b1, 2, 2))
        val l1 = ledger(f)
        l1.pending(buckets(), adjs, 200, now)        // offered with version 1
        val l2 = ledger(f)                            // process died before the ack arrived
        l2.ack(listOf(b1, b2, b3), known(), now)      // falls back to version 0 for b1 (b2/b3 have no adjustments)
        assertEquals(listOf(b1), l2.pending(buckets(), adjs, 200, now).map { it.startMs }) // one extra offer
        l2.ack(listOf(b1), known(), now)              // now the offered version (1) is known
        assertTrue(l2.pending(buckets(), adjs, 200, now).isEmpty())
    }

    @Test fun pendingAndGapStatesAreNeverOffered() {
        val l = ledger(tmp.newFile())
        val rows = listOf(rec(b1, 3, 0, LedgerState.PENDING), rec(b2, 3, 0, LedgerState.GAP))
        assertTrue(l.pending(rows, emptyList(), 200, now).isEmpty())
    }

    @Test fun bucketsOlderThanTheOfferWindowAreNotOffered() {
        val l = ledger(tmp.newFile())
        val oldStart = now - 73 * SyncLedger.HOUR_MS
        val freshStart = now - 71 * SyncLedger.HOUR_MS
        val old = rec(oldStart, 10, 10, LedgerState.VERIFIED, null, walkHops(oldStart))
        val fresh = rec(freshStart, 10, 10, LedgerState.VERIFIED, null, walkHops(freshStart))
        assertEquals(listOf(fresh.startMs), l.pending(listOf(old, fresh), emptyList(), 200, now).map { it.startMs })
    }

    @Test fun ackEntriesArePrunedAfterFourteenDaysAndTheFileShrinks() {
        val f = tmp.newFile()
        val oldStart = now - 15 * SyncLedger.DAY_MS
        val recentStart = now - 2 * SyncLedger.DAY_MS
        val l1 = SyncLedger(f, nowMs = now - 14 * SyncLedger.DAY_MS)
        l1.ack(listOf(oldStart, recentStart), setOf(oldStart, recentStart), now - 14 * SyncLedger.DAY_MS)
        assertEquals(2, l1.ackedCount())
        val l2 = SyncLedger(f, nowMs = now)
        assertFalse(l2.isAcked(oldStart))
        assertTrue(l2.isAcked(recentStart))
        assertEquals(1, f.readLines().filter { it.isNotEmpty() }.size)
    }

    @Test fun prunedHorizonNeverResurrectsAnOldBucket() {
        // offer window (72 h) < retention (14 d): a bucket whose ack was pruned is already outside the offer window.
        val l = ledger(tmp.newFile())
        val ancientStart = now - 15 * SyncLedger.DAY_MS
        val ancient = rec(ancientStart, 10, 10, LedgerState.VERIFIED, null, walkHops(ancientStart))
        assertTrue(l.pending(listOf(ancient), emptyList(), 200, now).isEmpty())
    }

    // ---- end to end with the real pipeline: counter events -> settlement -> late event -> sync item -----------------

    private fun ev(tsMs: Long, cum: Long) = CounterEvent(tsMs * 1_000_000L, tsMs, cum, 1, tsMs + 3_000)

    @Test fun pipelineLateEventResurfacesAckedBucketAndSummaryStaysConsistent() {
        val dir = tmp.newFolder()
        val base = 1_700_000_000_000L - (1_700_000_000_000L % 10_000)
        val p = WitnessPipeline(FileLedgerStore(dir))
        p.onCounterEvent(ev(base, 1_000))            // baseline
        p.onCounterEvent(ev(base + 2_000, 1_008))    // +8 in bucket `base` (no IMU at all => UNWITNESSED)
        val settleNow = base + 10_000 + 90_000 + 1
        p.tick(settleNow)
        assertEquals(1, p.buckets().size)
        assertEquals(LedgerState.UNWITNESSED, p.buckets().single().state)

        val l = SyncLedger(File(dir, "acks.tsv"), nowMs = settleNow)
        val first = l.pending(p.buckets(), p.adjustmentsList(), 200, settleNow)
        assertEquals(1, first.size); assertEquals(8, first[0].rawDelta); assertEquals("UNWITNESSED", first[0].state)
        l.ack(first.map { it.startMs }, p.buckets().map { it.startMs }.toSet(), settleNow)
        assertTrue(l.pending(p.buckets(), p.adjustmentsList(), 200, settleNow).isEmpty())

        p.onCounterEvent(ev(base + 5_000, 1_012))    // LATE: +4 for the already-settled bucket
        assertEquals(1, p.adjustmentsList().size)
        val again = l.pending(p.buckets(), p.adjustmentsList(), 200, settleNow)
        assertEquals(1, again.size)
        assertEquals(12, again[0].rawDelta); assertEquals(0, again[0].credited); assertEquals(4, again[0].lateRawAdded)

        val day = StepSummaryAggregator.aggregate(
            p.buckets(), p.adjustmentsList(), p.pendingBuckets(), p.counterGaps(), base - 1_000, base + 1_000_000,
        )
        assertEquals(12L, day.unwitnessed); assertEquals(12L, day.raw); assertEquals(0L, day.verified)
        assertTrue(day.reconciles())
        assertEquals("matches the engine's own ledger summary", p.summary().rawAll, day.raw)
    }
}
