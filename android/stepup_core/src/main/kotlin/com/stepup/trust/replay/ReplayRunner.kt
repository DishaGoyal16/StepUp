package com.stepup.trust.replay

import com.stepup.trust.HopLabel
import com.stepup.trust.VerifierConfig
import com.stepup.trust.classify.ClassifierConfig
import com.stepup.trust.export.ResultsCsv
import com.stepup.trust.ledger.LedgerSummary
import com.stepup.trust.session.TestMetrics
import com.stepup.trust.session.TestResult
import com.stepup.trust.session.TestScenario
import com.stepup.trust.store.InMemoryLedgerStore
import com.stepup.trust.witness.PipelineConfig
import com.stepup.trust.witness.WitnessPipeline

/** Result of re-running a recording through L3+L4+L5. ALWAYS labelled REPLAY. */
class ReplayReport(
    val source: String,
    val config: PipelineConfig,
    val summary: LedgerSummary,
    val tests: List<TestResult>,
    /** scenario -> (hop label -> count), counted over each test window. */
    val hopConfusion: Map<TestScenario, Map<HopLabel, Int>>,
    val pipeline: WitnessPipeline,
) {
    fun toText(): String {
        val sb = StringBuilder()
        sb.appendLine("=== $source : offline replay (NOT live data; thresholds may differ from the phone) ===")
        sb.appendLine("ledger: $summary")
        sb.appendLine("reconciles=${summary.reconciles()} verified<=raw=${summary.verifiedNeverExceedsRaw()}")
        sb.appendLine()
        sb.appendLine("%-3s %-28s %6s %6s %6s %6s %6s %6s %7s %7s %7s".format("id", "scenario", "truth", "raw", "verif", "rej", "unwit", "pend", "retent", "leak", "ratio"))
        for (r in tests) {
            fun f(d: Double?) = d?.let { "%.2f".format(it) } ?: "-"
            sb.appendLine(
                "%-3d %-28s %6s %6d %6d %6d %6d %6d %7s %7s %7s".format(
                    r.test.id, r.test.scenario.title, r.test.groundTruthSteps?.toString() ?: "-", r.rawSteps,
                    r.verifiedSteps, r.rejectedSteps, r.unwitnessedSteps, r.pendingSteps, f(r.retention), f(r.leakage), f(r.creditRatio),
                ),
            )
        }
        sb.appendLine()
        sb.appendLine("Hop-label confusion (rows = what the tester was doing, columns = classifier label):")
        sb.appendLine("%-28s %s".format("scenario", HopLabel.values().joinToString(" ") { it.name.padStart(8) }))
        for ((sc, m) in hopConfusion) {
            sb.appendLine("%-28s %s".format(sc.title, HopLabel.values().joinToString(" ") { (m[it] ?: 0).toString().padStart(8) }))
        }
        return sb.toString()
    }
}

/**
 * Feeds a [RawRecording] through the SAME [WitnessPipeline] code the phone runs, in original DELIVERY order, so
 * thresholds can be changed and re-scored without re-walking (v2 §9.3). Nothing is simulated: the inputs are the
 * recorded real sensor values.
 */
object ReplayRunner {
    private class Item(val deliverAt: Long, val order: Int, val run: (WitnessPipeline) -> Unit)

    fun run(
        rec: RawRecording,
        classifier: ClassifierConfig = ClassifierConfig(),
        verifier: VerifierConfig = VerifierConfig(),
    ): ReplayReport {
        val cfg = PipelineConfig(classifier = classifier, verifier = verifier)
        val p = WitnessPipeline(InMemoryLedgerStore(), cfg)
        val items = ArrayList<Item>(rec.imu.size + rec.counter.size + rec.ar.size)
        var n = 0
        for (s in rec.imu) items += Item(s.deliveredAtMs, n++) {
            if (s.sensor == 'A') it.onAccel(s.tMs, s.x, s.y, s.z) else it.onGyro(s.tMs, s.x, s.y, s.z)
        }
        for (e in rec.counter) items += Item(e.deliveredAtMs, n++) { it.onCounterEvent(e) }
        for (e in rec.ar) items += Item(e.tsMs + 20_000L, n++) { it.onActivity(e) }
        items.sortWith(compareBy<Item> { it.deliverAt }.thenBy { it.order })
        var lastTick = Long.MIN_VALUE
        for (i in items) {
            i.run(p)
            if (lastTick == Long.MIN_VALUE || i.deliverAt - lastTick >= 2_000) { p.tick(i.deliverAt); lastTick = i.deliverAt }
        }
        p.finishAndSettleAll()
        val nowMs = (items.lastOrNull()?.deliverAt ?: 0L) + 1
        val results = rec.tests.map { TestMetrics.compute(it, p, nowMs) }
        val hops = p.classifiedHopHistory()
        val confusion = LinkedHashMap<TestScenario, MutableMap<HopLabel, Int>>()
        for (t in rec.tests) {
            val end = t.endMs ?: nowMs
            val m = confusion.getOrPut(t.scenario) { LinkedHashMap() }
            for (h in hops) if (h.startMs >= t.startMs && h.startMs < end) m.merge(h.label, 1, Int::plus)
        }
        return ReplayReport(rec.meta["source"] ?: "REPLAY", cfg, p.summary(), results, confusion, p)
    }

    /** Writes the standard CSV set for a replay into [outDir] (every file has source=REPLAY). */
    fun writeCsv(report: ReplayReport, rec: RawRecording, outDir: java.io.File) {
        outDir.mkdirs()
        val src = "REPLAY"
        java.io.File(outDir, "replay_tests.csv").writeText(ResultsCsv.testsCsv(report.tests, src))
        java.io.File(outDir, "replay_buckets.csv").writeText(ResultsCsv.bucketsCsv(report.pipeline.buckets(), report.pipeline.adjustmentsList(), rec.tests, src))
        java.io.File(outDir, "replay_hops.csv").writeText(ResultsCsv.hopsCsv(report.pipeline.classifiedHopHistory(), src))
        java.io.File(outDir, "replay_summary.csv").writeText(ResultsCsv.summaryCsv(report.summary, src))
        java.io.File(outDir, "replay_report.txt").writeText(report.toText())
    }
}
