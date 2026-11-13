package com.stepup.trust.bridge

import com.stepup.trust.ledger.Adjustment
import com.stepup.trust.ledger.BucketRecord
import com.stepup.trust.ledger.LedgerState

/**
 * One settled bucket as handed to Dart for `syncStepBuckets` (channel contract `getBucketsForSync`).
 *
 * [rawDelta] and [credited] are the CURRENT totals of the bucket INCLUDING late-event adjustments, so a server that
 * re-verifies them against [hops] sees a self-consistent bucket. [lateRawAdded] / [lateCreditedAdded] are the
 * cumulative parts of those totals that came from counter events delivered after the bucket settled; a non-zero
 * [lateRawAdded] is the "re-send" flag (the bucket may already have been acknowledged with smaller totals).
 */
data class SyncItem(
    val startMs: Long,
    val bootCount: Int,
    val rawDelta: Int,
    val credited: Int,
    val state: String,
    val reason: String?,
    val walkFraction: Double,
    val evidenceMode: String,
    val carryMode: String,
    val hops: List<SyncHop>,
    val lateRawAdded: Int,
    val lateCreditedAdded: Int,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "startMs" to startMs, "bootCount" to bootCount, "rawDelta" to rawDelta, "credited" to credited,
        "state" to state, "reason" to reason, "walkFraction" to walkFraction, "evidenceMode" to evidenceMode,
        "carryMode" to carryMode, "hops" to hops.map { it.toMap() },
        "lateRawAdded" to lateRawAdded, "lateCreditedAdded" to lateCreditedAdded,
    )
}

/** One 2 s hop of evidence: label is `HopLabel.name` (WALK, RUN, SHAKE, VEHICLE, STILL, UNKNOWN). */
data class SyncHop(val label: String, val imuSteps: Double) {
    fun toMap(): Map<String, Any> = mapOf("label" to label, "imuSteps" to imuSteps)
}

object SyncExportMapper {
    /** Settled states that may be synced. PENDING and GAP are never exported. */
    val SYNCABLE: Set<LedgerState> =
        setOf(LedgerState.VERIFIED, LedgerState.PARTIAL, LedgerState.REJECTED, LedgerState.UNWITNESSED)

    fun isSyncable(b: BucketRecord) = b.state in SYNCABLE

    /**
     * Only hops that actually exist are listed (at most 5 per 10 s bucket, in time order). A bucket with fewer than
     * 4 hops has coverage < 0.8 and was settled UNWITNESSED; the server derives coverage from the list length.
     * Decoded from the compact hop string persisted with the settled bucket: no verification logic is involved.
     */
    fun hopsOf(b: BucketRecord): List<SyncHop> = b.decodeHops().map { SyncHop(it.label.name, it.imuSteps) }

    fun toItem(b: BucketRecord, adjustments: List<Adjustment>?): SyncItem {
        val (rawB, credB) = StepSummaryAggregator.totals(b, adjustments)
        return SyncItem(
            startMs = b.startMs, bootCount = b.bootCount, rawDelta = rawB.toInt(), credited = credB.toInt(),
            state = b.state.name, reason = b.reason, walkFraction = b.walkFraction,
            evidenceMode = b.evidenceMode, carryMode = b.carryMode, hops = hopsOf(b),
            lateRawAdded = adjustments?.sumOf { it.rawAdded } ?: 0,
            lateCreditedAdded = adjustments?.sumOf { it.creditedAdded } ?: 0,
        )
    }
}
