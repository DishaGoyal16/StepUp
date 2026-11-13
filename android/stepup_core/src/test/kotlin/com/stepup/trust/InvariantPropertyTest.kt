package com.stepup.trust

import com.stepup.trust.counter.CounterEvent
import com.stepup.trust.store.InMemoryLedgerStore
import com.stepup.trust.witness.WitnessPipeline
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Randomised (seeded, deterministic) checks of the safety invariants the task demands:
 *  - verified never exceeds raw,
 *  - missing evidence never earns verified steps,
 *  - the same sensor event can never be credited twice,
 *  - production sources contain no step-faking / random / Health Connect code.
 * Randomness lives ONLY in this test source set.
 */
class InvariantPropertyTest {
    private val labels = HopLabel.values()

    @Test fun verifierNeverCreditsMoreThanRawOrMoreThanTheImuCap() {
        val rnd = java.util.Random(12345)
        val v = BucketVerifier()
        repeat(20_000) {
            val raw1 = rnd.nextInt(30); val raw2 = rnd.nextInt(30)
            val deltas = listOf(CounterDelta(rnd.nextInt(10_000).toLong(), raw1), CounterDelta(rnd.nextInt(10_000).toLong(), raw2))
            val n = rnd.nextInt(7)
            val hops = (0 until n).map { Hop(it * 2_000L, labels[rnd.nextInt(labels.size)], rnd.nextDouble() * 6) }
            val r = v.verify(0, deltas, hops, rnd.nextInt(10) == 0)
            if (r != null) {
                assertTrue("credited ${r.credited} > raw ${r.rawDelta}", r.credited <= r.rawDelta)
                assertTrue(r.credited >= 0)
                val gait = hops.filter { it.label == HopLabel.WALK || it.label == HopLabel.RUN }
                assertTrue(r.credited <= Math.floor(1.15 * gait.sumOf { it.imuSteps }).toInt() || r.credited == 0)
                if (n < 4) assertEquals("coverage < 80% => nothing verified", 0, r.credited)
                if (gait.isEmpty()) assertEquals(0, r.credited)
                if (r.status == BucketStatus.UNWITNESSED || r.status == BucketStatus.REJECTED) assertEquals(0, r.credited)
            }
        }
    }

    @Test fun counterStreamWithoutAnyImuNeverProducesVerifiedSteps() {
        val rnd = java.util.Random(777)
        repeat(30) { run ->
            val p = WitnessPipeline(InMemoryLedgerStore())
            var cum = 1_000L + run
            var t = 5_000_000L
            p.onCounterEvent(CounterEvent(t * 1_000_000, t, cum, 1, t))
            repeat(400) {
                t += 200L + rnd.nextInt(3_000)
                cum += 1 + rnd.nextInt(6)
                // Occasionally replay an old event, jump the boot count, or reset the counter.
                val e = when (rnd.nextInt(25)) {
                    0 -> CounterEvent((t - 5_000) * 1_000_000, t - 5_000, cum - 3, 1, t)
                    1 -> CounterEvent(t * 1_000_000, t, 5, 2, t)
                    else -> CounterEvent(t * 1_000_000, t, cum, 1, t + rnd.nextInt(10_000))
                }
                p.onCounterEvent(e)
                p.onCounterEvent(e) // duplicate delivery of the same sensor event
                p.tick(t + rnd.nextInt(200_000))
            }
            p.tick(Long.MAX_VALUE / 4)
            val s = p.summary()
            assertEquals("no IMU evidence => nothing verified", 0L, s.verifiedSteps)
            assertTrue(s.reconciles())
            assertTrue(s.verifiedNeverExceedsRaw())
            assertEquals(0L, s.pendingSteps)
        }
    }

    @Test fun anEventIsCreditedAtMostOnceNoMatterHowOftenItIsDelivered() {
        val a = WitnessPipeline(InMemoryLedgerStore())
        val b = WitnessPipeline(InMemoryLedgerStore())
        val evs = listOf(
            CounterEvent(1, 1_000, 100, 1, 1_000), CounterEvent(2, 3_000, 106, 1, 4_000),
            CounterEvent(3, 5_000, 111, 1, 8_000), CounterEvent(4, 9_000, 120, 1, 12_000),
        )
        evs.forEach { a.onCounterEvent(it) }
        repeat(5) { evs.forEach { b.onCounterEvent(it) } }
        assertEquals(a.rawDeltaTotal(), b.rawDeltaTotal())
        assertEquals(20L, b.rawDeltaTotal())
    }

    // ---- production sources must stay clean ---------------------------------------------------------------------
    @Test fun productionSourcesContainNoRandomStepGenerationOrHealthConnect() {
        val roots = listOf(File("src/main"), File("../app/src/main")).filter { it.isDirectory }
        assertTrue("cannot find production sources from ${File(".").absolutePath}", roots.isNotEmpty())
        val forbidden = listOf(
            "java.util.Random", "kotlin.random", "Math.random", "nextGaussian", "ThreadLocalRandom",
            "androidx.health", "HealthConnect", "StepsRecord",
        )
        val offenders = ArrayList<String>()
        for (root in roots) root.walkTopDown().filter { it.isFile && (it.extension == "kt" || it.extension == "xml" || it.extension == "kts") }.forEach { f ->
            val text = f.readText()
            for (token in forbidden) if (text.contains(token)) {
                // The manifest/docs may MENTION that Health Connect is not used; code may not import/use it.
                if (f.extension == "xml" && !text.contains("androidx.health")) continue
                if (text.lineSequence().any { it.contains(token) && !it.trimStart().startsWith("//") && !it.trimStart().startsWith("*") && !it.trimStart().startsWith("/*") }) {
                    offenders += "${f.path}: $token"
                }
            }
        }
        assertTrue("forbidden tokens in production code: $offenders", offenders.isEmpty())
        assertFalse(offenders.isNotEmpty())
    }
}
