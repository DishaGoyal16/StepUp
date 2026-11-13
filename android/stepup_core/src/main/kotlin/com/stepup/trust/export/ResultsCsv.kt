package com.stepup.trust.export

import com.stepup.trust.classify.WindowFeatures
import com.stepup.trust.counter.GapRecord
import com.stepup.trust.counter.StoredDelta
import com.stepup.trust.ledger.Adjustment
import com.stepup.trust.ledger.BucketRecord
import com.stepup.trust.ledger.LedgerSummary
import com.stepup.trust.session.TestResult
import com.stepup.trust.witness.WitnessPipeline

/**
 * CSV builders. Every file carries a `source` column: LIVE (recorded on a phone) or REPLAY (re-computed offline
 * from a recording with possibly different thresholds). Replay numbers must never be presented as live results.
 */
object ResultsCsv {
    fun testsCsv(results: List<TestResult>, source: String): String {
        val sb = StringBuilder()
        sb.appendLine(
            Csv.row(
                "source", "test_id", "scenario", "kind", "start_utc_ms", "end_utc_ms", "duration_s",
                "ground_truth_genuine_steps", "raw_steps", "verified_steps", "partial_excess_steps", "rejected_steps",
                "unwitnessed_steps", "pending_steps", "gap_steps", "sensor_coverage", "hops_present", "hops_expected",
                "retention", "leakage", "credit_ratio", "mape_percent", "hop_label_counts", "bucket_reason_codes", "note",
            ),
        )
        for (r in results) {
            sb.appendLine(
                Csv.row(
                    source, r.test.id, r.test.scenario.name, r.test.scenario.kind.name, r.test.startMs, r.test.endMs ?: "",
                    r.durationS, r.test.groundTruthSteps, r.rawSteps, r.verifiedSteps, r.partialExcessSteps,
                    r.rejectedSteps, r.unwitnessedSteps, r.pendingSteps, r.gapSteps, r.sensorCoverage, r.hopsPresent,
                    r.hopsExpected, r.retention, r.leakage, r.creditRatio, r.mapePercent,
                    r.labelCounts.entries.sortedBy { it.key.name }.joinToString("|") { "${it.key}:${it.value}" },
                    r.reasonCounts.entries.sortedBy { it.key }.joinToString("|") { "${it.key}:${it.value}" },
                    r.note,
                ),
            )
        }
        return sb.toString()
    }

    fun bucketsCsv(buckets: List<BucketRecord>, adjustments: List<Adjustment>, tests: List<com.stepup.trust.session.LabeledTest>, source: String): String {
        val sb = StringBuilder()
        sb.appendLine(
            Csv.row(
                "source", "bucket_start_utc_ms", "boot_count", "raw_delta", "credited", "state", "reason", "walk_fraction",
                "imu_gait_steps", "carry_mode", "evidence_mode", "imu_hop_coverage", "ar_flag", "hops(idx:label:imuSteps)",
                "settled_at_ms", "late_adjust_raw", "late_adjust_credited", "test_ids",
            ),
        )
        val adj = adjustments.groupBy { it.bucketStartMs }
        for (b in buckets) {
            val ids = tests.filter { b.startMs + 10_000 > it.startMs && b.startMs < (it.endMs ?: Long.MAX_VALUE) }
                .joinToString("|") { it.id.toString() }
            sb.appendLine(
                Csv.row(
                    source, b.startMs, b.bootCount, b.rawDelta, b.credited, b.state, b.reason, b.walkFraction, b.imuSteps,
                    b.carryMode, b.evidenceMode, b.coverage, b.arFlag, b.hops, b.settledAtMs,
                    adj[b.startMs]?.sumOf { it.rawAdded } ?: 0, adj[b.startMs]?.sumOf { it.creditedAdded } ?: 0, ids,
                ),
            )
        }
        return sb.toString()
    }

    fun hopsCsv(hops: List<WitnessPipeline.ClassifiedHop>, source: String): String {
        val sb = StringBuilder()
        sb.appendLine(
            Csv.row(listOf("source", "hop_start_utc_ms", "label", "imu_steps", "counter_cadence_spm", "carry_mode", "has_gyro") +
                WindowFeatures.NAMES + "evidence_trace"),
        )
        for (h in hops) {
            val f = h.features?.toList() ?: List(WindowFeatures.NAMES.size) { Double.NaN }
            sb.appendLine(
                Csv.row(listOf(source, h.startMs, h.label, h.imuSteps, h.counterCadenceSpm, h.carry, h.hasGyro) + f + h.trace),
            )
        }
        return sb.toString()
    }

    fun countersCsv(deltas: List<StoredDelta>, gaps: List<GapRecord>, source: String): String {
        val sb = StringBuilder()
        sb.appendLine(Csv.row("source", "kind", "sensor_ts_utc_ms", "steps", "boot_count", "cumulative", "sensor_ts_ns", "delivered_at_ms", "lag_ms_delivery_minus_sensor", "reason"))
        for (d in deltas) sb.appendLine(Csv.row(source, "DELTA", d.tsMs, d.delta, d.bootCount, d.cumulative, d.sensorTsNs, d.deliveredAtMs, d.deliveredAtMs - d.tsMs, ""))
        for (g in gaps) sb.appendLine(Csv.row(source, "GAP", g.tsMs, g.steps, "", "", "", "", "", g.reason))
        return sb.toString()
    }

    fun summaryCsv(s: LedgerSummary, source: String): String =
        Csv.row("source", "raw_all", "raw_display", "verified", "pending", "partial_excess", "rejected", "implausible_excluded_from_display", "unwitnessed", "gap", "reconciles", "verified_le_raw") + "\n" +
            Csv.row(source, s.rawAll, s.displaySteps, s.verifiedSteps, s.pendingSteps, s.partialExcessSteps, s.rejectedSteps, s.implausibleSteps, s.unwitnessedSteps, s.gapSteps, s.reconciles(), s.verifiedNeverExceedsRaw()) + "\n"
}
