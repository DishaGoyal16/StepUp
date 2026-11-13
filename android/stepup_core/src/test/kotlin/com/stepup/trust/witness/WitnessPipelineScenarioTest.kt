package com.stepup.trust.witness

import com.stepup.trust.counter.CounterEvent
import com.stepup.trust.ledger.LedgerState
import com.stepup.trust.store.FileLedgerStore
import com.stepup.trust.store.InMemoryLedgerStore
import com.stepup.trust.testsupport.CounterSynth
import com.stepup.trust.testsupport.ScenarioRunner
import com.stepup.trust.testsupport.Synth
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * End-to-end behaviour of counter ledger + IMU hops + verifier + ledgers on SYNTHETIC scenarios.
 * These prove the logic and the safety invariants; they are NOT evidence of real-world accuracy.
 */
class WitnessPipelineScenarioTest {
    @get:Rule val tmp = TemporaryFolder()

    private val t0 = 1_000_000.0

    private fun pipeline() = WitnessPipeline(InMemoryLedgerStore())

    private fun assertInvariants(p: WitnessPipeline) {
        val s = p.summary()
        assertTrue("ledger must reconcile: $s", s.reconciles())
        assertTrue("verified <= raw: $s", s.verifiedNeverExceedsRaw())
        assertTrue(s.verifiedSteps <= s.displaySteps + s.implausibleSteps)
    }

    // ---- genuine walking --------------------------------------------------------------------------------------
    @Test fun pureWalkingEarnsMostOfItsStepsAndNeverMoreThanRaw() {
        val sig = Synth.walk(t0, 120.0, seed = 101)
        val p = pipeline(); p.evidenceMode = EvidenceMode.E1
        ScenarioRunner(p).run(sig, CounterSynth.events(sig.trueStepTimesMs))
        val s = p.summary()
        println("pure walk: $s")
        assertInvariants(p)
        val raw = p.rawDeltaTotal().toDouble()
        assertTrue("retention ${s.verifiedSteps / raw}", s.verifiedSteps / raw >= 0.85)
        assertTrue(s.verifiedSteps <= raw)
        assertEquals(0L, s.pendingSteps)
        assertEquals(EvidenceMode.E1.name, p.buckets().first().evidenceMode)
    }

    // ---- fakes -------------------------------------------------------------------------------------------------
    @Test fun pureFastShakingEarnsNothing() {
        val sig = Synth.shake(t0, 120.0)
        val p = pipeline()
        ScenarioRunner(p).run(sig, CounterSynth.events(sig.trueStepTimesMs))
        val s = p.summary()
        println("pure shake: $s")
        assertInvariants(p)
        assertEquals(0L, s.verifiedSteps)
        assertTrue(s.rejectedSteps > 0)
        assertNotNull(p.snapshot().lastRejection)
    }

    @Test fun slowRhythmicShakingEarnsNothing() {
        val sig = Synth.shake(t0, 120.0, freqHz = 1.7, strokeAmp = 6.0, tiltRad = 0.3, seed = 7)
        val p = pipeline()
        ScenarioRunner(p).run(sig, CounterSynth.events(sig.trueStepTimesMs))
        println("slow shake: ${p.summary()}")
        assertInvariants(p)
        assertEquals(0L, p.summary().verifiedSteps)
    }

    @Test fun legBouncingCountedAsStepsEarnsNothing() {
        val bounce = Synth.legBounce(t0, 120.0)
        val fakeSteps = (0 until 288).map { t0 + it * (1000.0 / 2.4) } // hardware counter fooled by the bounce
        val p = pipeline()
        ScenarioRunner(p).run(bounce, CounterSynth.events(fakeSteps))
        println("leg bounce: ${p.summary()}")
        assertInvariants(p)
        assertEquals(0L, p.summary().verifiedSteps)
    }

    @Test fun vehicleMotionWithCounterStepsEarnsNothing() {
        val veh = Synth.vehicle(t0, 120.0)
        val fakeSteps = (0 until 150).map { t0 + it * 800.0 }
        val p = pipeline()
        ScenarioRunner(p).run(veh, CounterSynth.events(fakeSteps))
        println("vehicle: ${p.summary()}")
        assertInvariants(p)
        assertEquals(0L, p.summary().verifiedSteps)
    }

    @Test fun activityRecognitionVehicleRejectsEvenWalkLikeMotion() {
        val sig = Synth.walk(t0, 90.0, seed = 111)
        val ar = listOf(
            ArEvent((t0 + 0).toLong(), ArType.IN_VEHICLE, 90),
            ArEvent((t0 + 10_000).toLong(), ArType.IN_VEHICLE, 92),
            ArEvent((t0 + 20_000).toLong(), ArType.IN_VEHICLE, 95),
            ArEvent((t0 + 120_000).toLong(), ArType.STILL, 90),
        )
        val p = pipeline()
        ScenarioRunner(p).run(sig, CounterSynth.events(sig.trueStepTimesMs), ar)
        println("AR vehicle: ${p.summary()}")
        assertInvariants(p)
        assertEquals(0L, p.summary().verifiedSteps)
        assertTrue(p.buckets().any { it.reason == "IN_VEHICLE" })
    }

    @Test fun cyclingHintIsReportedAsBicycle() {
        val sig = Synth.walk(t0, 60.0, seed = 112)
        val ar = (0..5).map { ArEvent((t0 + it * 10_000).toLong(), ArType.ON_BICYCLE, 85) }
        val p = pipeline()
        ScenarioRunner(p).run(sig, CounterSynth.events(sig.trueStepTimesMs), ar)
        assertInvariants(p)
        assertEquals(0L, p.summary().verifiedSteps)
        assertTrue(p.buckets().any { it.reason == "ON_BICYCLE" })
    }

    @Test fun arWalkingNeverUpgradesAFakeShake() {
        val sig = Synth.shake(t0, 90.0)
        val ar = (0..8).map { ArEvent((t0 + it * 10_000).toLong(), ArType.WALKING, 99) }
        val p = pipeline()
        ScenarioRunner(p).run(sig, CounterSynth.events(sig.trueStepTimesMs), ar)
        assertEquals(0L, p.summary().verifiedSteps)
    }

    @Test fun counterStepsWithNoPhysicalMotionAreRejectedNoMotionEvidence() {
        val still = Synth.still(t0, 90.0)
        val injected = (0 until 150).map { t0 + 2_000 + it * 500.0 }
        val p = pipeline()
        ScenarioRunner(p).run(still, CounterSynth.events(injected))
        println("injection: ${p.summary()}")
        assertInvariants(p)
        assertEquals(0L, p.summary().verifiedSteps)
        assertTrue(p.buckets().any { it.reason == "NO_MOTION_EVIDENCE" })
    }

    @Test fun missingImuSamplesMakeStepsUnwitnessedNeverVerified() {
        val steps = (0 until 120).map { t0 + it * 550.0 }
        val p = pipeline()
        ScenarioRunner(p).run(null, CounterSynth.events(steps))
        val s = p.summary()
        println("no IMU: $s")
        assertInvariants(p)
        assertEquals("missing evidence must never earn verified steps", 0L, s.verifiedSteps)
        assertTrue(s.unwitnessedSteps > 0)
        assertTrue(p.buckets().all { it.state == LedgerState.UNWITNESSED })
    }

    @Test fun evidenceGapMakesOnlyTheGapUnwitnessed() {
        val a = Synth.walk(t0, 40.0, seed = 121)
        val hole = 30_000.0
        val b = Synth.walk(t0 + 40_000 + hole, 40.0, seed = 122)
        val allSteps = Synth.walk(t0, 110.0, seed = 123).trueStepTimesMs // counter keeps counting through the hole
        val p = pipeline()
        ScenarioRunner(p).run(Synth.concat(a, b), CounterSynth.events(allSteps))
        println("evidence gap: ${p.summary()}")
        assertInvariants(p)
        val s = p.summary()
        assertTrue("steps inside the IMU hole are unwitnessed", s.unwitnessedSteps >= 30)
        assertTrue("steps outside the hole are still earned", s.verifiedSteps > 80)
    }

    // ---- mixed -------------------------------------------------------------------------------------------------
    @Test fun walkThenShakeCreditsOnlyAboutTheWalk() {
        val walk = Synth.walk(t0, 45.0, seed = 131)
        val shake = Synth.shake(t0 + 45_000, 45.0, seed = 132)
        val steps = walk.trueStepTimesMs + shake.trueStepTimesMs
        val p = pipeline()
        ScenarioRunner(p).run(Synth.concat(walk, shake), CounterSynth.events(steps))
        val s = p.summary()
        val genuine = walk.trueStepTimesMs.size
        println("walk then shake: $s genuine=$genuine")
        assertInvariants(p)
        assertTrue("credited ${s.verifiedSteps} must not exceed 1.2x genuine $genuine", s.verifiedSteps <= genuine * 1.2)
        assertTrue("most genuine steps retained", s.verifiedSteps >= genuine * 0.55)
    }

    @Test fun alternatingWalkAndShakeIsBoundedByTheImuCap() {
        var sig = Synth.walk(t0, 6.0, seed = 141)
        val steps = ArrayList(sig.trueStepTimesMs)
        var genuine = sig.trueStepTimesMs.size
        var t = t0 + 6_000
        repeat(8) { i ->
            val sh = Synth.shake(t, 4.0, freqHz = 3.2, seed = 150L + i)
            val w = Synth.walk(t + 4_000, 6.0, seed = 160L + i)
            sig = Synth.concat(sig, sh, w)
            steps += sh.trueStepTimesMs; steps += w.trueStepTimesMs
            genuine += w.trueStepTimesMs.size
            t += 10_000
        }
        val p = pipeline()
        ScenarioRunner(p).run(sig, CounterSynth.events(steps))
        val s = p.summary()
        println("cheat mix: $s genuine=$genuine")
        assertInvariants(p)
        assertTrue("credit ${s.verifiedSteps} vs genuine $genuine must stay <= 1.25x", s.verifiedSteps <= genuine * 1.25)
    }

    @Test fun counterBurstWhileWalkingIsCappedAtImuEstimate() {
        val sig = Synth.walk(t0, 60.0, seed = 171)
        val real = sig.trueStepTimesMs
        // adversary adds 20 extra counter steps into every 10 s bucket on top of real walking
        val extra = ArrayList<Double>()
        var b = t0 + 10_000
        while (b < t0 + 50_000) { for (k in 0 until 20) extra += b + 500 + k * 5.0; b += 10_000 }
        val p = pipeline()
        ScenarioRunner(p).run(sig, CounterSynth.events(real + extra))
        val s = p.summary()
        val imu = p.buckets().filter { it.state == LedgerState.VERIFIED || it.state == LedgerState.PARTIAL }.sumOf { it.imuSteps }
        println("burst: $s imu=$imu")
        assertInvariants(p)
        assertTrue("verified ${s.verifiedSteps} <= 1.15 x imu $imu", s.verifiedSteps <= Math.floor(1.15 * imu) + p.buckets().size)
    }

    // ---- ledger mechanics ---------------------------------------------------------------------------------------
    @Test fun bucketsStayPendingUntilNinetySecondsAfterTheyClose() {
        val p = pipeline()
        val e0 = CounterEvent(1, 1_000_000, 100, 1, 1_000_100)
        p.onCounterEvent(e0)
        p.onCounterEvent(CounterEvent(2, 1_003_000, 109, 1, 1_005_000)) // bucket [1_000_000, 1_010_000)
        p.tick(1_010_000 + 89_999)
        assertEquals(9L, p.summary().pendingSteps)
        p.tick(1_010_000 + 90_000)
        assertEquals(0L, p.summary().pendingSteps)
        assertEquals(9L, p.summary().unwitnessedSteps) // no IMU at all => unwitnessed
    }

    @Test fun eventsOnABucketBoundaryGoToTheCorrectBucket() {
        val p = pipeline()
        p.onCounterEvent(CounterEvent(1, 999_000, 100, 1, 999_100))
        p.onCounterEvent(CounterEvent(2, 1_000_000, 104, 1, 1_000_100)) // exactly on a boundary -> bucket 1_000_000
        p.onCounterEvent(CounterEvent(3, 1_009_999, 107, 1, 1_010_000)) // last ms of the same bucket
        p.onCounterEvent(CounterEvent(4, 1_010_000, 112, 1, 1_010_100)) // first ms of the next bucket
        assertEquals(mapOf(1_000_000L to 7, 1_010_000L to 5), p.pendingBuckets())
    }

    @Test fun lateEventForASettledBucketBecomesOneAppendOnlyAdjustment() {
        val sig = Synth.walk(t0, 60.0, seed = 181)
        val events = CounterSynth.events(sig.trueStepTimesMs)
        val p = pipeline()
        ScenarioRunner(p).run(sig, events)
        val before = p.summary()
        val bucketsBefore = p.buckets()
        val target = bucketsBefore.first { it.state == LedgerState.VERIFIED && it.rawDelta < 20 }
        // A counter event for that bucket arrives long after settlement (e.g. batching + Doze).
        val last = p.counterDeltas().last().cumulative
        val late = CounterEvent(target.startMs * 1_000_000 + 7, target.startMs + 4_321, last + 3, 1, target.startMs + 500_000)
        p.onCounterEvent(late)
        val after = p.summary()
        assertEquals("history is not rewritten", bucketsBefore, p.buckets())
        assertEquals(1, p.adjustmentsList().size)
        assertEquals(3, p.adjustmentsList().single().rawAdded)
        assertEquals(before.rawAll + 3, after.rawAll)
        assertTrue("late steps may be credited only within the IMU cap", after.verifiedSteps - before.verifiedSteps in 0..3)
        assertInvariants(p)
        // The same sensor event delivered again must not be credited twice.
        p.onCounterEvent(late)
        assertEquals(1, p.adjustmentsList().size)
        assertEquals(after, p.summary())
    }

    @Test fun lateEventForARejectedBucketStaysRejected() {
        val sig = Synth.shake(t0, 60.0, seed = 191)
        val p = pipeline()
        ScenarioRunner(p).run(sig, CounterSynth.events(sig.trueStepTimesMs))
        val rej = p.buckets().first { it.state == LedgerState.REJECTED && it.rawDelta in 1..30 }
        val last = p.counterDeltas().last().cumulative
        p.onCounterEvent(CounterEvent(99, rej.startMs + 100, last + 4, 1, rej.startMs + 400_000))
        assertEquals(0L, p.summary().verifiedSteps)
        assertInvariants(p)
    }

    @Test fun lateEventPushingABucketOverThePhysicalCeilingIsDowngraded() {
        val sig = Synth.walk(t0, 60.0, seed = 201)
        val p = pipeline()
        ScenarioRunner(p).run(sig, CounterSynth.events(sig.trueStepTimesMs))
        val target = p.buckets().first { it.state == LedgerState.VERIFIED }
        val last = p.counterDeltas().last().cumulative
        p.onCounterEvent(CounterEvent(98, target.startMs + 1_000, last + 40, 1, target.startMs + 400_000))
        val adj = p.adjustmentsList().single()
        assertEquals(40, adj.rawAdded)
        assertTrue("credit is revoked (negative adjustment)", adj.creditedAdded < 0)
        assertInvariants(p)
    }

    @Test fun serviceRestartKeepsPendingBucketsAndNeverDoubleCounts() {
        val dir = tmp.newFolder()
        val sig = Synth.walk(t0, 60.0, seed = 211)
        val events = CounterSynth.events(sig.trueStepTimesMs)
        val first = events.take(events.size / 2)
        val second = events.drop(events.size / 2)
        val p1 = WitnessPipeline(FileLedgerStore(dir))
        first.forEach { p1.onCounterEvent(it) }
        val rawBefore = p1.rawDeltaTotal()
        // restart
        val p2 = WitnessPipeline(FileLedgerStore(dir))
        assertEquals(rawBefore, p2.rawDeltaTotal())
        assertEquals(p1.summary().pendingSteps, p2.summary().pendingSteps)
        p2.onListenerRegistered()
        second.forEach { p2.onCounterEvent(it) }
        p2.tick(Long.MAX_VALUE / 4)
        val s = p2.summary()
        assertInvariants(p2)
        assertEquals("every delta lands in exactly one ledger bucket", p2.rawDeltaTotal() + p2.gapTotal(), s.rawAll)
    }

    @Test fun rebootMidWalkGivesNoCreditForTheCounterJump() {
        val sig = Synth.walk(t0, 40.0, seed = 221)
        val steps = sig.trueStepTimesMs
        val half = steps.size / 2
        val before = CounterSynth.events(steps.take(half), boot = 1, base = 50_000)
        // after reboot the counter restarts at ~0 with a new boot count
        val after = CounterSynth.events(steps.drop(half), boot = 2, base = 3, baselineAtMs = steps[half].toLong() - 500)
        val p = pipeline()
        ScenarioRunner(p).run(sig, before + after)
        assertInvariants(p)
        val raw = p.rawDeltaTotal()
        assertTrue("raw ($raw) can only contain real increments, never the 50000 -> 3 jump", raw <= steps.size)
        assertTrue(p.counterGaps().isEmpty())
    }

    @Test fun duplicateSensorEventsDoNotChangeAnyTotal() {
        val sig = Synth.walk(t0, 40.0, seed = 231)
        val ev = CounterSynth.events(sig.trueStepTimesMs)
        val p = pipeline()
        ScenarioRunner(p).run(sig, ev + ev) // every event delivered twice
        val q = pipeline()
        ScenarioRunner(q).run(sig, ev)
        assertEquals(q.rawDeltaTotal(), p.rawDeltaTotal())
        assertEquals(q.summary().verifiedSteps, p.summary().verifiedSteps)
    }

    @Test fun resetSessionClearsLedgersAndBaseline() {
        val sig = Synth.walk(t0, 30.0, seed = 241)
        val p = pipeline()
        ScenarioRunner(p).run(sig, CounterSynth.events(sig.trueStepTimesMs))
        assertTrue(p.summary().rawAll > 0)
        p.resetSession()
        assertEquals(0L, p.summary().rawAll)
        assertTrue(p.buckets().isEmpty())
    }

    @Test fun replayingSameDataTwiceIsDeterministic() {
        val sig = Synth.walk(t0, 60.0, seed = 251)
        val ev = CounterSynth.events(sig.trueStepTimesMs)
        val a = pipeline(); ScenarioRunner(a).run(sig, ev)
        val b = pipeline(); ScenarioRunner(b).run(sig, ev)
        assertEquals(a.summary(), b.summary())
        assertEquals(a.buckets(), b.buckets())
    }
}
