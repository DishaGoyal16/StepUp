package com.stepup.trust.witness

import com.stepup.trust.counter.CounterEvent
import com.stepup.trust.counter.CounterEventKind
import com.stepup.trust.store.FileLedgerStore
import com.stepup.trust.store.InMemoryLedgerStore
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class WitnessPipelineCounterTest {
    @get:Rule val tmp = TemporaryFolder()

    private fun ev(tsMs: Long, cum: Long, boot: Int = 1) =
        CounterEvent(tsMs * 1_000_000L, tsMs, cum, boot, tsMs + 3_000)

    @Test fun rawTotalSumsOnlyDeltasNeverBaselineOrGap() {
        val p = WitnessPipeline(InMemoryLedgerStore())
        p.onCounterEvent(ev(1_000, 10_000))      // baseline
        p.onCounterEvent(ev(5_000, 10_006))      // +6
        p.onCounterEvent(ev(5_000, 10_006))      // duplicate
        p.onCounterEvent(ev(9_000, 10_011))      // +5
        assertEquals(11L, p.rawDeltaTotal())
        assertEquals(0L, p.gapTotal())
    }

    @Test fun baselineIsPersistedBeforeReturnAndSurvivesProcessRestart() {
        val dir = tmp.newFolder()
        val p1 = WitnessPipeline(FileLedgerStore(dir))
        p1.onCounterEvent(ev(1_000, 500))
        p1.onCounterEvent(ev(4_000, 508))
        // "Process death": brand new pipeline over the same directory.
        val p2 = WitnessPipeline(FileLedgerStore(dir))
        assertEquals("deltas persisted", 8L, p2.rawDeltaTotal())
        p2.onListenerRegistered()
        val r = p2.onCounterEvent(ev(70_000, 530))
        assertEquals(CounterEventKind.BASELINE_AFTER_RESTART, r.kind)
        assertEquals("steps taken while dead are GAP, not raw/verified", 22L, p2.gapTotal())
        assertEquals(8L, p2.rawDeltaTotal())
    }

    @Test fun resetSessionStartsFromScratch() {
        val p = WitnessPipeline(InMemoryLedgerStore())
        p.onCounterEvent(ev(1_000, 10)); p.onCounterEvent(ev(2_000, 15))
        p.resetSession()
        assertEquals(0L, p.rawDeltaTotal())
        assertEquals(CounterEventKind.BASELINE_FIRST, p.onCounterEvent(ev(3_000, 40)).kind)
        assertEquals(0L, p.rawDeltaTotal())
    }
}

