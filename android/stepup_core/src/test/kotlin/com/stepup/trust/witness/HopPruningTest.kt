package com.stepup.trust.witness

import com.stepup.trust.ledger.LedgerState
import com.stepup.trust.store.FileLedgerStore
import com.stepup.trust.store.InMemoryLedgerStore
import com.stepup.trust.testsupport.CounterSynth
import com.stepup.trust.testsupport.ScenarioRunner
import com.stepup.trust.testsupport.Synth
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * Hop compaction (hops older than 48 h are dropped at startup and at most hourly while running) must NEVER change
 * a classification/verification result for a bucket that is still unsettled. SYNTHETIC scenarios.
 */
class HopPruningTest {
    @get:Rule val tmp = TemporaryFolder()

    private val hourMs = 3_600_000L
    private val tOld = 1_000_000.0
    private val tNew = tOld + 72 * hourMs            // 72 h after the old walk

    private fun hopStarts(dir: File): List<Long> =
        File(dir, "hops.tsv").takeIf { it.exists() }?.readLines()?.filter { it.isNotEmpty() }
            ?.map { it.substringBefore('\t').toLong() } ?: emptyList()

    /** Old walk (fully settled) + a restart + a recent walk whose last buckets are still PENDING. Returns the dir. */
    private fun buildLedgerWithPendingBuckets(): File {
        val dir = tmp.newFolder()
        val old = Synth.walk(tOld, 60.0, seed = 301)
        val p1 = WitnessPipeline(FileLedgerStore(dir)); p1.evidenceMode = EvidenceMode.E1
        ScenarioRunner(p1).run(old, CounterSynth.events(old.trueStepTimesMs))
        assertTrue(p1.buckets().isNotEmpty())

        val recent = Synth.walk(tNew, 60.0, seed = 302)
        val p2 = WitnessPipeline(FileLedgerStore(dir)); p2.evidenceMode = EvidenceMode.E1
        p2.onListenerRegistered()
        ScenarioRunner(p2).run(recent, CounterSynth.events(recent.trueStepTimesMs, base = 50_000), finish = false)
        assertTrue("scenario must leave unsettled buckets", p2.pendingBuckets().isNotEmpty())
        return dir
    }

    private fun copy(dir: File): File = tmp.newFolder().also { dir.copyRecursively(it, overwrite = true) }

    private val noPrune = PipelineConfig(hopRetentionMs = Long.MAX_VALUE / 4)

    @Test fun pendingBucketVerdictIsIdenticalBeforeAndAfterPruningAndOldHopsDisappear() {
        val base = buildLedgerWithPendingBuckets()
        val dirPruned = copy(base)
        val dirKept = copy(base)
        val tNewMs = tNew.toLong()
        assertTrue("fixture has old hops", hopStarts(dirKept).any { it < tNewMs - hourMs })

        val pruned = WitnessPipeline(FileLedgerStore(dirPruned))                    // default: 48 h retention
        val kept = WitnessPipeline(FileLedgerStore(dirKept), noPrune)               // reference: nothing pruned
        pruned.evidenceMode = EvidenceMode.E1; kept.evidenceMode = EvidenceMode.E1

        // old hops are gone (memory and disk), recent ones are untouched
        assertTrue(pruned.classifiedHopHistory().none { it.startMs < tNewMs - hourMs })
        assertTrue(kept.classifiedHopHistory().any { it.startMs < tNewMs - hourMs })
        assertTrue(hopStarts(dirPruned).none { it < tNewMs - hourMs })
        assertTrue(hopStarts(dirKept).any { it < tNewMs - hourMs })
        assertEquals(
            hopStarts(dirKept).filter { it >= tNewMs - hourMs }, hopStarts(dirPruned),
        )

        // the unsettled buckets are the same set before settling ...
        assertTrue(pruned.pendingBuckets().isNotEmpty())
        assertEquals(kept.pendingBuckets(), pruned.pendingBuckets())

        // ... and settle to exactly the same verdicts (state, reason, credited, hops, walk fraction, ...)
        val far = tNewMs + 10 * 60_000L
        pruned.tick(far); kept.tick(far)
        assertTrue(pruned.pendingBuckets().isEmpty())
        assertEquals(kept.buckets(), pruned.buckets())
        assertEquals(kept.summary(), pruned.summary())
        assertTrue("non-vacuous: something was actually verified", pruned.summary().verifiedSteps > 0)
        assertTrue(pruned.buckets().any { it.startMs >= tNewMs && it.state != LedgerState.UNWITNESSED })
    }

    @Test fun startupCompactionWithWallClockStillKeepsHopsOfUnsettledBuckets() {
        val base = buildLedgerWithPendingBuckets()
        val dirPruned = copy(base); val dirKept = copy(base)
        val tNewMs = tNew.toLong()
        // "Phone was off for 100 h": by the wall clock EVERYTHING is older than 48 h, but pending buckets need their hops.
        val wall = { tNewMs + 100 * hourMs }
        val pruned = WitnessPipeline(FileLedgerStore(dirPruned), clock = wall)
        val kept = WitnessPipeline(FileLedgerStore(dirKept), noPrune)
        pruned.evidenceMode = EvidenceMode.E1; kept.evidenceMode = EvidenceMode.E1
        assertTrue(pruned.classifiedHopHistory().none { it.startMs < tNewMs - hourMs })
        val oldestPending = pruned.pendingBuckets().keys.min()
        assertTrue("hops of the pending buckets survive", hopStarts(dirPruned).any { it >= oldestPending })
        val far = tNewMs + 10 * 60_000L
        pruned.tick(far); kept.tick(far)
        assertEquals(kept.buckets(), pruned.buckets())
        assertTrue(pruned.summary().verifiedSteps > 0)
    }

    @Test fun periodicCompactionRunsAtMostOncePerHourAndLeavesSettledBucketsAlone() {
        val dir = tmp.newFolder()
        val old = Synth.walk(tOld, 60.0, seed = 311)
        val p = WitnessPipeline(FileLedgerStore(dir)); p.evidenceMode = EvidenceMode.E1
        ScenarioRunner(p).run(old, CounterSynth.events(old.trueStepTimesMs))
        val settled = p.buckets()
        assertTrue(settled.isNotEmpty())
        assertEquals("ticks within the first hour never compact", 0, p.hopPruneRuns)
        assertTrue(hopStarts(dir).isNotEmpty())

        val t = tOld.toLong()
        p.tick(t + 49 * hourMs)                          // > 1 h since the first tick, hops now > 48 h old
        assertEquals(1, p.hopPruneRuns)
        assertTrue(p.classifiedHopHistory().isEmpty())
        assertTrue(hopStarts(dir).isEmpty())
        assertEquals("settled buckets keep their own hop evidence", settled, p.buckets())
        assertTrue(p.buckets().all { it.hops.isNotEmpty() })

        p.tick(t + 49 * hourMs + 10 * 60_000L)           // only 10 min later: rate-limited
        assertEquals(1, p.hopPruneRuns)
        p.tick(t + 50 * hourMs + 1)                      // > 1 h after the previous compaction
        assertEquals(2, p.hopPruneRuns)
    }

    @Test fun startupCompactionByNewestHopNeverPrunesSyntheticTimelines() {
        // clock == null: reference is the newest persisted hop, so a replay timeline far from "now" is untouched.
        val dir = tmp.newFolder()
        val sig = Synth.walk(tOld, 60.0, seed = 321)
        val p1 = WitnessPipeline(FileLedgerStore(dir)); p1.evidenceMode = EvidenceMode.E1
        ScenarioRunner(p1).run(sig, CounterSynth.events(sig.trueStepTimesMs))
        val before = hopStarts(dir)
        WitnessPipeline(FileLedgerStore(dir))
        assertEquals(before, hopStarts(dir))
    }

    @Test fun inMemoryStorePrunesToo() {
        val store = InMemoryLedgerStore()
        val sig = Synth.walk(tOld, 30.0, seed = 331)
        val p = WitnessPipeline(store); p.evidenceMode = EvidenceMode.E1
        ScenarioRunner(p).run(sig, CounterSynth.events(sig.trueStepTimesMs))
        val n = store.loadHops().size
        assertTrue(n > 0)
        p.tick(tOld.toLong() + 49 * hourMs)
        assertTrue(store.loadHops().isEmpty())
        assertFalse(p.classifiedHopHistory().isNotEmpty())
    }
}
