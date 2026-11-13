package com.stepup.trust.bridge

import com.stepup.trust.counter.GapRecord
import com.stepup.trust.ledger.LedgerState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class UserBindingTest {
    @get:Rule val tmp = TemporaryFolder()

    private val t1 = 1_700_000_123_456L              // not on a bucket boundary
    private val s1 = 1_700_000_120_000L              // t1 floored to 10 s
    private val t2 = t1 + 3_600_000L
    private val s2 = 1_700_003_720_000L

    @Test fun nothingBoundMeansNothingIsFiltered() {
        val b = UserBinding(File(tmp.root, "binding.tsv"))
        assertNull(b.uid)
        assertEquals(0L, b.sinceMs)
    }

    @Test fun firstBindSetsSinceToFlooredNow() {
        val b = UserBinding(File(tmp.root, "binding.tsv"))
        val r = b.bind("uidA", t1)
        assertTrue(r.changed)
        assertEquals(s1, r.sinceMs)
        assertEquals("uidA", b.uid)
        assertEquals(mapOf("bound" to true, "changed" to true, "sinceMs" to s1), r.toMap())
    }

    @Test fun rebindingSameUidKeepsSince() {
        val b = UserBinding(File(tmp.root, "binding.tsv"))
        b.bind("uidA", t1)
        val r = b.bind("uidA", t2)
        assertFalse(r.changed)
        assertEquals(s1, r.sinceMs)
        assertEquals(s1, b.sinceMs)
    }

    @Test fun bindingAnotherUidMovesSince() {
        val b = UserBinding(File(tmp.root, "binding.tsv"))
        b.bind("uidA", t1)
        val r = b.bind("uidB", t2)
        assertTrue(r.changed)
        assertEquals(s2, r.sinceMs)
        assertEquals("uidB", b.uid)
        // switching back is also a change (account A's steps from B's session must not reappear under A)
        val back = b.bind("uidA", t2 + 60_000)
        assertTrue(back.changed)
        assertEquals(Math.floorDiv(t2 + 60_000, 10_000L) * 10_000L, back.sinceMs)
    }

    @Test fun bindingSurvivesRestartThroughTheSameFile() {
        val f = File(tmp.root, "binding.tsv")
        UserBinding(f).bind("uidA", t1)
        val reopened = UserBinding(f)
        assertEquals("uidA", reopened.uid)
        assertEquals(s1, reopened.sinceMs)
        val r = reopened.bind("uidA", t2)
        assertFalse(r.changed)
        assertEquals(s1, r.sinceMs)
        UserBinding(f).bind("uidB", t2)
        assertEquals(s2, UserBinding(f).sinceMs)
    }

    @Test fun corruptBindingFileMeansUnbound() {
        val f = File(tmp.root, "binding.tsv")
        f.writeText("uidA\tnot-a-number\n")
        val b = UserBinding(f)
        assertNull(b.uid); assertEquals(0L, b.sinceMs)
    }

    @Test(expected = IllegalArgumentException::class) fun blankUidIsRejected() {
        UserBinding(File(tmp.root, "binding.tsv")).bind("  ", t1)
    }

    @Test(expected = IllegalArgumentException::class) fun uidWithWhitespaceIsRejected() {
        UserBinding(File(tmp.root, "binding.tsv")).bind("a b", t1)
    }

    // ---- consumers honour the boundary -----------------------------------------------------------------------------

    private val since = s1
    private val oldA = since - 20_000
    private val oldB = since - 10_000
    private val newA = since            // the bucket containing the bind instant is included
    private val newB = since + 10_000

    private val buckets = listOf(
        rec(oldA, 20, 20, LedgerState.VERIFIED, null, walkHops(oldA)),
        rec(oldB, 10, 0, LedgerState.REJECTED, "SHAKE_PATTERN"),
        rec(newA, 15, 15, LedgerState.VERIFIED, null, walkHops(newA)),
        rec(newB, 8, 0, LedgerState.UNWITNESSED, "NO_IMU_EVIDENCE"),
    )

    @Test fun summaryExcludesBucketsPendingAndGapsBeforeTheBinding() {
        val d = StepSummaryAggregator.aggregate(
            buckets, listOf(adj(oldA, 5, 5), adj(newA, 2, 2)),
            pendingByBucket = mapOf(oldB to 50, newB + 10_000 to 6),
            gaps = listOf(GapRecord(oldA, 99, "SERVICE_NOT_LISTENING"), GapRecord(newB, 11, "SERVICE_NOT_LISTENING")),
            dayStartMs = since - 3_600_000, dayEndMs = since + 3_600_000, sinceMs = since,
        )
        assertEquals(17L, d.verified)      // 15 + 2 late; the 20 + 5 of the old account are gone
        assertEquals(0L, d.rejected); assertEquals(0L, d.suspicious)
        assertEquals(8L, d.unwitnessed)
        assertEquals(6L, d.pending)
        assertEquals(11L, d.gap)
        assertEquals(42L, d.raw)
        assertTrue(d.reconciles())
    }

    @Test fun sinceZeroChangesNothing() {
        val all = StepSummaryAggregator.aggregate(buckets, emptyList(), emptyMap(), emptyList(), since - 1_000_000, since + 1_000_000)
        val explicit = StepSummaryAggregator.aggregate(buckets, emptyList(), emptyMap(), emptyList(), since - 1_000_000, since + 1_000_000, 0L)
        assertEquals(all, explicit)
        assertEquals(53L, all.raw)
    }

    @Test fun syncNeverOffersBucketsBeforeTheBindingAndDoesNotAckThem() {
        val now = since + 600_000
        val ledger = SyncLedger(File(tmp.root, "acks.tsv"), nowMs = now)
        val items = ledger.pending(buckets, emptyList(), 200, now, sinceMs = since)
        assertEquals(listOf(newA, newB), items.map { it.startMs })
        // not acked either: with the boundary lifted (sinceMs = 0) they would still be offered
        assertFalse(ledger.isAcked(oldA)); assertFalse(ledger.isAcked(oldB))
        assertEquals(listOf(oldA, oldB, newA, newB), ledger.pending(buckets, emptyList(), 200, now, 0L).map { it.startMs })
    }

    @Test fun lateAdjustmentOfAPreviousAccountsBucketIsNotSurfaced() {
        val now = since + 600_000
        val ledger = SyncLedger(File(tmp.root, "acks.tsv"), nowMs = now)
        val items = ledger.pending(buckets, listOf(adj(oldA, 9, 9)), 200, now, since)
        assertEquals(listOf(newA, newB), items.map { it.startMs })
    }

    @Test fun filteringAfterRestartUsesThePersistedBoundary() {
        val bf = File(tmp.root, "binding.tsv")
        val af = File(tmp.root, "acks.tsv")
        UserBinding(bf).bind("uidB", t1)
        // "process death": everything reopened from the same files
        val binding = UserBinding(bf)
        val now = since + 600_000
        val ledger = SyncLedger(af, nowMs = now)
        assertEquals(listOf(newA, newB), ledger.pending(buckets, emptyList(), 200, now, binding.sinceMs).map { it.startMs })
        val d = StepSummaryAggregator.aggregate(buckets, emptyList(), emptyMap(), emptyList(), since - 1_000_000, since + 1_000_000, binding.sinceMs)
        assertEquals(23L, d.raw)
    }
}
