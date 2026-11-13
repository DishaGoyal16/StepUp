package com.stepup.trust.session

import com.stepup.trust.HopLabel
import com.stepup.trust.ledger.BucketRecord
import com.stepup.trust.ledger.LedgerState
import com.stepup.trust.store.AppendLog
import com.stepup.trust.witness.WitnessPipeline
import java.io.File
import kotlin.math.abs

/** What the tester is physically doing during a labeled test (the ten scenarios of the task brief). */
enum class TestScenario(val title: String, val kind: Kind) {
    NORMAL_WALK("Normal walking", Kind.GENUINE),
    SLOW_WALK("Slow walking", Kind.GENUINE),
    FAST_WALK("Fast walking", Kind.GENUINE),
    FAST_SHAKE("Fast phone shaking", Kind.FAKE),
    SLOW_SHAKE("Slow rhythmic shaking", Kind.FAKE),
    SITTING_STILL("Sitting still", Kind.FAKE),
    LEG_BOUNCE("Leg bouncing", Kind.FAKE),
    VEHICLE("Vehicle travel", Kind.FAKE),
    WALK_THEN_SHAKE("Walking followed by shaking", Kind.MIXED),
    MIXED_WALK_SHAKE("Mixed walking and shaking", Kind.MIXED);

    enum class Kind { GENUINE, FAKE, MIXED }
}

/**
 * One labeled test window. [groundTruthSteps] = steps the tester counted by hand that were GENUINE walking steps
 * (null until entered). For FAKE scenarios the truth is 0 genuine steps by definition.
 */
data class LabeledTest(
    val id: Int,
    val scenario: TestScenario,
    val startMs: Long,
    val endMs: Long?, // null while running
    val groundTruthSteps: Int?,
    val notes: String = "",
) {
    val running: Boolean get() = endMs == null
}

/** Persists the labeled tests (small file, rewritten atomically on each change). */
class LabeledTestStore(dir: File) {
    private val log = AppendLog(File(dir, "labeled_tests.tsv"))
    private val tests = LinkedHashMap<Int, LabeledTest>()

    init {
        for (r in log.readAll()) try {
            val t = LabeledTest(
                r[0].toInt(), TestScenario.valueOf(r[1]), r[2].toLong(),
                r[3].toLong().takeIf { it > 0 }, r[4].toInt().takeIf { it >= 0 }, r.getOrElse(5) { "" },
            )
            tests[t.id] = t
        } catch (_: Exception) { }
    }

    @Synchronized fun all(): List<LabeledTest> = tests.values.toList()
    @Synchronized fun running(): LabeledTest? = tests.values.lastOrNull { it.running }
    @Synchronized fun last(): LabeledTest? = tests.values.lastOrNull()

    @Synchronized
    fun start(scenario: TestScenario, nowMs: Long): LabeledTest {
        running()?.let { stop(it.id, nowMs) }
        val t = LabeledTest((tests.keys.maxOrNull() ?: 0) + 1, scenario, nowMs, null, null)
        tests[t.id] = t
        persist()
        return t
    }

    @Synchronized
    fun stop(id: Int, nowMs: Long, groundTruth: Int? = null): LabeledTest? {
        val t = tests[id] ?: return null
        val u = t.copy(endMs = t.endMs ?: nowMs, groundTruthSteps = groundTruth ?: t.groundTruthSteps)
        tests[id] = u
        persist()
        return u
    }

    @Synchronized
    fun setGroundTruth(id: Int, steps: Int?): LabeledTest? {
        val t = tests[id] ?: return null
        val u = t.copy(groundTruthSteps = steps)
        tests[id] = u
        persist()
        return u
    }

    @Synchronized fun clear() { tests.clear(); log.delete() }

    private fun persist() = log.rewrite(
        tests.values.map { listOf(it.id, it.scenario.name, it.startMs, it.endMs ?: 0L, it.groundTruthSteps ?: -1, it.notes) },
    )
}

/** Everything measured for one labeled test, computed from the ledgers (never from guesses). */
data class TestResult(
    val test: LabeledTest,
    val durationS: Double,
    /** Counter steps whose SENSOR timestamp lies in [start, end). */
    val rawSteps: Int,
    val verifiedSteps: Int,
    val partialExcessSteps: Int,
    val rejectedSteps: Int,
    val unwitnessedSteps: Int,
    val pendingSteps: Int,
    val gapSteps: Int,
    val buckets: List<BucketRecord>,
    val labelCounts: Map<HopLabel, Int>,
    val reasonCounts: Map<String, Int>,
    val hopsPresent: Int,
    val hopsExpected: Int,
    /** Fraction of the test window that has IMU hop evidence (not the same as per-bucket verifier coverage). */
    val sensorCoverage: Double,
    /** verified/truth (capped at 1) for GENUINE tests; null if undefined. */
    val retention: Double?,
    /** verified/raw for FAKE tests (0/0 -> null); null otherwise. */
    val leakage: Double?,
    /** verified/truth (can exceed 1.0 = inflation). */
    val creditRatio: Double?,
    /** |truth - verified| / truth * 100 for GENUINE tests. */
    val mapePercent: Double?,
    val note: String,
)

object TestMetrics {
    /**
     * Bucket-based accounting: a bucket belongs to the test when it overlaps [start, end). Boundary buckets can
     * therefore include a few steps of the neighbouring activity (+-10 s); leave a pause between tests.
     * Retention / leakage / credit ratio follow v2 §9.5, and are only produced when the needed labels exist.
     */
    fun compute(test: LabeledTest, pipeline: WitnessPipeline, nowMs: Long, bucketMs: Long = 10_000L): TestResult {
        val end = test.endMs ?: nowMs
        val inWindow = { s: Long -> s + bucketMs > test.startMs && s < end }
        val adjByBucket = pipeline.adjustmentsList().groupBy { it.bucketStartMs }
        val buckets = pipeline.buckets().filter { inWindow(it.startMs) }
        var verified = 0; var excess = 0; var rejected = 0; var unwit = 0
        for (b in buckets) {
            val rawB = b.rawDelta + (adjByBucket[b.startMs]?.sumOf { it.rawAdded } ?: 0)
            val credB = (b.credited + (adjByBucket[b.startMs]?.sumOf { it.creditedAdded } ?: 0)).coerceIn(0, rawB)
            when (b.state) {
                LedgerState.VERIFIED, LedgerState.PARTIAL -> { verified += credB; excess += rawB - credB }
                LedgerState.REJECTED -> rejected += rawB
                LedgerState.UNWITNESSED -> unwit += rawB
                else -> {}
            }
        }
        val pending = pipeline.pendingBuckets().filterKeys(inWindow).values.sum()
        val raw = pipeline.counterDeltas().filter { it.tsMs >= test.startMs && it.tsMs < end }.sumOf { it.delta }
        val gap = pipeline.counterGaps().filter { it.tsMs >= test.startMs && it.tsMs < end }.sumOf { it.steps }

        val hops = pipeline.classifiedHops(test.startMs, end)
        val labels = hops.groupingBy { it.label }.eachCount()
        val reasons = HashMap<String, Int>()
        for (b in buckets) reasons.merge(b.reason ?: b.state.name, 1, Int::plus)
        val expectedHops = ((end - test.startMs) / 2_000L).toInt().coerceAtLeast(0)
        val coverage = if (expectedHops == 0) 0.0 else (hops.size.toDouble() / expectedHops).coerceAtMost(1.0)

        val truth = when (test.scenario.kind) {
            TestScenario.Kind.FAKE -> 0
            else -> test.groundTruthSteps
        }
        var retention: Double? = null
        var leakage: Double? = null
        var creditRatio: Double? = null
        var mape: Double? = null
        var note = ""
        when (test.scenario.kind) {
            TestScenario.Kind.GENUINE -> if (truth != null && truth > 0) {
                retention = minOf(verified, truth).toDouble() / truth
                creditRatio = verified.toDouble() / truth
                mape = abs(truth - verified).toDouble() / truth * 100.0
            } else note = "enter manually counted steps to compute retention / credit ratio / MAPE"
            TestScenario.Kind.FAKE -> {
                if (raw > 0) leakage = verified.toDouble() / raw else note = "no counter steps (nothing to leak)"
            }
            TestScenario.Kind.MIXED -> if (truth != null && truth > 0) {
                creditRatio = verified.toDouble() / truth
                note = "mixed: credit ratio only; retention/leakage need per-segment labels"
            } else note = "enter manually counted GENUINE steps to compute the credit ratio"
        }
        return TestResult(
            test, (end - test.startMs) / 1000.0, raw, verified, excess, rejected, unwit, pending, gap, buckets,
            labels, reasons, hops.size, expectedHops, coverage, retention, leakage, creditRatio, mape, note,
        )
    }
}
