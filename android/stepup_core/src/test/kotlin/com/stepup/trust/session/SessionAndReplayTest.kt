package com.stepup.trust.session

import com.stepup.trust.classify.ClassifierConfig
import com.stepup.trust.export.Csv
import com.stepup.trust.export.ResultsCsv
import com.stepup.trust.replay.RawRecording
import com.stepup.trust.replay.RawRecordingWriter
import com.stepup.trust.replay.ReplayRunner
import com.stepup.trust.store.InMemoryLedgerStore
import com.stepup.trust.testsupport.CounterSynth
import com.stepup.trust.testsupport.ScenarioRunner
import com.stepup.trust.testsupport.Synth
import com.stepup.trust.witness.PipelineConfig
import com.stepup.trust.witness.WitnessPipeline
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** SYNTHETIC data only: verifies the session/metrics/CSV/replay plumbing, not detection accuracy. */
class SessionAndReplayTest {
    @get:Rule val tmp = TemporaryFolder()
    private val t0 = 1_000_000.0

    private fun walkPipeline(): Triple<WitnessPipeline, Synth.Signal, Int> {
        val sig = Synth.walk(t0, 90.0, seed = 301)
        val p = WitnessPipeline(InMemoryLedgerStore())
        ScenarioRunner(p).run(sig, CounterSynth.events(sig.trueStepTimesMs))
        return Triple(p, sig, sig.trueStepTimesMs.size)
    }

    @Test fun genuineTestComputesRetentionRatioAndMape() {
        val (p, _, truth) = walkPipeline()
        val test = LabeledTest(1, TestScenario.NORMAL_WALK, t0.toLong() - 5_000, t0.toLong() + 95_000, truth)
        val r = TestMetrics.compute(test, p, nowMs = t0.toLong() + 1_000_000)
        println("metrics: ret=${r.retention} ratio=${r.creditRatio} mape=${r.mapePercent} cov=${r.sensorCoverage} raw=${r.rawSteps} verified=${r.verifiedSteps}")
        assertTrue(r.retention!! in 0.8..1.0)
        assertEquals(r.verifiedSteps.toDouble() / truth, r.creditRatio!!, 1e-9)
        assertTrue(r.mapePercent!! < 20.0)
        assertNull("genuine tests have no leakage", r.leakage)
        assertTrue(r.sensorCoverage > 0.5)
        assertEquals(0, r.pendingSteps)
        assertTrue(r.reasonCounts.isNotEmpty() || r.buckets.all { it.reason == null })
    }

    @Test fun fakeTestComputesLeakageOnly() {
        val sig = Synth.shake(t0, 90.0, seed = 311)
        val p = WitnessPipeline(InMemoryLedgerStore())
        ScenarioRunner(p).run(sig, CounterSynth.events(sig.trueStepTimesMs))
        val r = TestMetrics.compute(LabeledTest(2, TestScenario.FAST_SHAKE, t0.toLong() - 5_000, t0.toLong() + 95_000, null), p, t0.toLong() + 1_000_000)
        assertEquals(0.0, r.leakage!!, 1e-9)
        assertNull(r.retention)
        assertTrue(r.rejectedSteps > 0)
        assertTrue(r.labelCounts.keys.any { it.name == "SHAKE" })
    }

    @Test fun stillTestWithNoCounterStepsHasNoLeakageValue() {
        val sig = Synth.still(t0, 60.0)
        val p = WitnessPipeline(InMemoryLedgerStore())
        ScenarioRunner(p).run(sig, emptyList())
        val r = TestMetrics.compute(LabeledTest(3, TestScenario.SITTING_STILL, t0.toLong(), t0.toLong() + 60_000, null), p, t0.toLong() + 500_000)
        assertNull(r.leakage)
        assertEquals(0, r.rawSteps)
    }

    @Test fun metricsAreNullUntilGroundTruthIsEntered() {
        val (p, _, _) = walkPipeline()
        val r = TestMetrics.compute(LabeledTest(4, TestScenario.NORMAL_WALK, t0.toLong(), t0.toLong() + 90_000, null), p, t0.toLong() + 1_000_000)
        assertNull(r.retention); assertNull(r.creditRatio); assertNull(r.mapePercent)
        assertTrue(r.note.contains("manually counted"))
    }

    @Test fun mixedTestReportsCreditRatioButNotInventedRetention() {
        val (p, _, truth) = walkPipeline()
        val r = TestMetrics.compute(LabeledTest(5, TestScenario.MIXED_WALK_SHAKE, t0.toLong(), t0.toLong() + 90_000, truth / 2), p, t0.toLong() + 1_000_000)
        assertNotNull(r.creditRatio); assertNull(r.retention); assertNull(r.leakage)
    }

    @Test fun labeledTestStorePersistsStartStopAndGroundTruth() {
        val dir = tmp.newFolder()
        val s = LabeledTestStore(dir)
        val t = s.start(TestScenario.SLOW_WALK, 1_000)
        assertTrue(s.running()!!.id == t.id)
        s.stop(t.id, 61_000)
        s.setGroundTruth(t.id, 77)
        val s2 = LabeledTestStore(dir)
        val back = s2.all().single()
        assertEquals(TestScenario.SLOW_WALK, back.scenario)
        assertEquals(61_000L, back.endMs)
        assertEquals(77, back.groundTruthSteps)
        assertNull(s2.running())
        // starting a new test while one is running stops the old one (never two open tests)
        val a = s2.start(TestScenario.FAST_WALK, 70_000); val b = s2.start(TestScenario.VEHICLE, 90_000)
        assertEquals(90_000L, s2.all().first { it.id == a.id }.endMs)
        assertEquals(b.id, s2.running()!!.id)
        s2.clear(); assertTrue(LabeledTestStore(dir).all().isEmpty())
    }

    @Test fun csvExportsAreWellFormedAndLabelledWithTheirSource() {
        val (p, _, truth) = walkPipeline()
        val test = LabeledTest(1, TestScenario.NORMAL_WALK, t0.toLong(), t0.toLong() + 90_000, truth)
        val r = TestMetrics.compute(test, p, t0.toLong() + 1_000_000)
        val tests = Csv.parse(ResultsCsv.testsCsv(listOf(r), "LIVE"))
        assertEquals(2, tests.size)
        assertEquals(tests[0].size, tests[1].size)
        assertEquals("LIVE", tests[1][0])
        val buckets = Csv.parse(ResultsCsv.bucketsCsv(p.buckets(), p.adjustmentsList(), listOf(test), "LIVE"))
        assertEquals(p.buckets().size + 1, buckets.size)
        assertTrue(buckets.drop(1).all { it.size == buckets[0].size })
        val hops = Csv.parse(ResultsCsv.hopsCsv(p.classifiedHopHistory(), "LIVE"))
        assertTrue(hops.size > 10); assertTrue(hops.all { it.size == hops[0].size })
        val sum = Csv.parse(ResultsCsv.summaryCsv(p.summary(), "REPLAY"))
        assertEquals("true", sum[1][10]); assertEquals("true", sum[1][11])
        val ctr = Csv.parse(ResultsCsv.countersCsv(p.counterDeltas(), p.counterGaps(), "LIVE"))
        assertEquals(p.counterDeltas().size + 1, ctr.size)
    }

    // ---- raw recording + replay -------------------------------------------------------------------------------
    private fun writeSyntheticRecording(dir: java.io.File, shakeToo: Boolean): Pair<Synth.Signal, List<LabeledTest>> {
        val walk = Synth.walk(t0, 60.0, seed = 321)
        val shake = if (shakeToo) Synth.shake(t0 + 70_000, 60.0, seed = 322) else null
        val sig = if (shake != null) Synth.concat(walk, Synth.still(t0 + 60_000, 10.0, seed = 323), shake) else walk
        val steps = walk.trueStepTimesMs + (shake?.trueStepTimesMs ?: emptyList())
        val events = CounterSynth.events(steps)
        RawRecordingWriter(dir).use { w ->
            w.writeMeta("device" to "SYNTHETIC-TEST-FIXTURE")
            for (f in sig.frames) {
                val deliver = (Math.floor(f.tMs / 30_000) + 1).toLong() * 30_000
                w.imuSample('A', (f.tMs * 1e6).toLong(), f.tMs, f.a[0], f.a[1], f.a[2], deliver)
                f.g?.let { w.imuSample('G', (f.tMs * 1e6).toLong(), f.tMs, it[0], it[1], it[2], deliver) }
            }
            events.forEach { w.counterEvent(it) }
        }
        val tests = listOfNotNull(
            LabeledTest(1, TestScenario.NORMAL_WALK, t0.toLong(), t0.toLong() + 60_000, walk.trueStepTimesMs.size),
            if (shake != null) LabeledTest(2, TestScenario.FAST_SHAKE, t0.toLong() + 70_000, t0.toLong() + 130_000, 0) else null,
        )
        RawRecordingWriter(java.io.File(dir, "tmp")).use { it.writeLabels(tests) }
        java.io.File(dir, "tmp/labels.csv").copyTo(java.io.File(dir, "labels.csv"), overwrite = true)
        return sig to tests
    }

    @Test fun replayOfARecordingReproducesTheLiveResultExactly() {
        val dir = tmp.newFolder()
        val (sig, _) = writeSyntheticRecording(dir, shakeToo = false)
        // "live" run = scenario runner; replay = recorded files -> ReplayRunner
        val live = WitnessPipeline(InMemoryLedgerStore())
        val events = CounterSynth.events(Synth.walk(t0, 60.0, seed = 321).trueStepTimesMs)
        ScenarioRunner(live).run(sig, events)
        val rep = ReplayRunner.run(RawRecording.read(dir))
        assertEquals(live.summary().verifiedSteps, rep.summary.verifiedSteps)
        assertEquals(live.summary().rawAll, rep.summary.rawAll)
        assertEquals("REPLAY labelled", "LIVE_RECORDING", rep.source)
        assertTrue(rep.toText().contains("offline replay"))
    }

    @Test fun replayWithDifferentThresholdsChangesOutcomeWithoutRewalking() {
        val dir = tmp.newFolder()
        writeSyntheticRecording(dir, shakeToo = true)
        val rec = RawRecording.read(dir)
        val base = ReplayRunner.run(rec)
        assertTrue("walk earned", base.tests.first { it.test.id == 1 }.verifiedSteps > 0)
        assertEquals("shake leaked nothing", 0, base.tests.first { it.test.id == 2 }.verifiedSteps)
        // an impossible impact gate makes every hop non-walk => nothing is verified any more
        val strict = ReplayRunner.run(rec, ClassifierConfig().withOverrides(mapOf("asymGateMin" to 99.0)))
        assertEquals(0L, strict.summary.verifiedSteps)
        assertTrue(base.summary.verifiedSteps > strict.summary.verifiedSteps)
        // confusion matrix has a row per scenario
        assertTrue(base.hopConfusion.containsKey(TestScenario.NORMAL_WALK))
        assertTrue(base.hopConfusion.getValue(TestScenario.FAST_SHAKE).getOrDefault(com.stepup.trust.HopLabel.SHAKE, 0) > 0)
        val out = tmp.newFolder()
        ReplayRunner.writeCsv(base, rec, out)
        assertTrue(java.io.File(out, "replay_tests.csv").readText().lines()[1].startsWith("REPLAY"))
    }

    @Test fun replayCliRunsSetAndSweepAndWritesLabelledCsv() {
        val dir = tmp.newFolder()
        writeSyntheticRecording(dir, shakeToo = true)
        val out = tmp.newFolder()
        val buf = java.io.ByteArrayOutputStream()
        val old = System.out
        System.setOut(java.io.PrintStream(buf))
        try {
            com.stepup.trust.replay.main(arrayOf("--dir", dir.path, "--out", out.path, "--set", "scoreMargin=2.5"))
            com.stepup.trust.replay.main(arrayOf("--dir", dir.path, "--sweep", "asymGateMin=0.1,0.25,99"))
        } finally {
            System.setOut(old)
        }
        val text = buf.toString()
        assertTrue(text.contains("offline replay (NOT live data"))
        assertTrue(text.contains("SWEEP asymGateMin"))
        assertTrue(java.io.File(out, "replay_hops.csv").exists())
        assertTrue(java.io.File(out, "replay_report.txt").readText().contains("Hop-label confusion"))
    }

    @Test fun unknownOverrideNamesAreRejectedNotIgnored() {
        var threw = false
        try { ClassifierConfig().withOverrides(mapOf("noSuchThreshold" to 1.0)) } catch (e: IllegalArgumentException) { threw = true }
        assertTrue(threw)
    }

    @Test fun pipelineConfigDefaultsMatchTheSpecRegister() {
        val c = PipelineConfig()
        assertEquals(90_000L, c.settleMs)
        assertEquals(35, c.verifier.maxStepsPerBucket)
        assertEquals(1.15, c.verifier.imuSlack, 0.0)
        assertEquals(0.8, c.verifier.minCoverage, 0.0)
        assertEquals(0.5, c.verifier.minWalkFraction, 0.0)
        assertEquals(10_000L, c.verifier.bucketMs)
        assertEquals(0.35, c.classifier.r0Gait, 0.0)
        assertEquals(65, c.arMinConfidence)
        assertEquals(45_000L, c.arMarginMs)
    }
}
