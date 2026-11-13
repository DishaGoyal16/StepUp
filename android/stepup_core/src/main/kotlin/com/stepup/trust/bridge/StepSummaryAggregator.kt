package com.stepup.trust.bridge

import com.stepup.trust.counter.GapRecord
import com.stepup.trust.ledger.Adjustment
import com.stepup.trust.ledger.BucketRecord
import com.stepup.trust.ledger.LedgerState

/**
 * Per-day totals handed to the Flutter UI (`getTodaySummary` and the 2 s event stream).
 *
 *  * [raw]         every counter step whose bucket starts in the range: settled + pending + GAP
 *  * [verified]    credited steps of VERIFIED / PARTIAL buckets (the only reward-eligible number)
 *  * [pending]     raw steps of buckets that have not settled yet
 *  * [rejected]    raw steps of REJECTED buckets + the un-credited excess of PARTIAL buckets
 *  * [suspicious]  the part of [rejected] whose bucket reason is in [StepSummaryAggregator.SUSPICIOUS_REASONS]
 *                  (a SUBSET of [rejected]: it is reported separately AND included in [rejected])
 *  * [unwitnessed] raw steps of buckets without IMU evidence (display-only)
 *  * [gap]         steps counted by the hardware while the service was not listening (display-only)
 *
 * Reconciliation: raw = verified + pending + rejected + unwitnessed + gap (same identity as `LedgerSummary`).
 */
data class DaySummary(
    val raw: Long,
    val verified: Long,
    val pending: Long,
    val rejected: Long,
    val suspicious: Long,
    val unwitnessed: Long,
    val gap: Long,
) {
    fun reconciles(): Boolean = raw == verified + pending + rejected + unwitnessed + gap && suspicious <= rejected

    /** Plain map (StandardMethodCodec-safe: only String keys and Long values). */
    fun toMap(): Map<String, Any> = mapOf(
        "raw" to raw, "verified" to verified, "pending" to pending, "rejected" to rejected,
        "suspicious" to suspicious, "unwitnessed" to unwitnessed, "gap" to gap,
    )
}

object StepSummaryAggregator {
    /** Rejection reasons that point at deliberate or non-walking motion (DATABASE_SCHEMA channel contract). */
    val SUSPICIOUS_REASONS: Set<String> =
        setOf("SHAKE_PATTERN", "CADENCE_EXCEEDED", "VEHICLE_MOTION", "IN_VEHICLE", "ON_BICYCLE")

    /**
     * Buckets (and GAP records) whose start/timestamp is in `[dayStartMs, dayEndMs)` are counted, but never anything
     * before [sinceMs] (the user-binding boundary: steps of a previously signed-in account are excluded, not deleted).
     */
    fun aggregate(
        buckets: Collection<BucketRecord>,
        adjustments: Collection<Adjustment>,
        pendingByBucket: Map<Long, Int>,
        gaps: Collection<GapRecord>,
        dayStartMs: Long,
        dayEndMs: Long,
        sinceMs: Long = 0L,
    ): DaySummary {
        val from = maxOf(dayStartMs, sinceMs)
        val adjByBucket = HashMap<Long, MutableList<Adjustment>>()
        for (a in adjustments) adjByBucket.getOrPut(a.bucketStartMs) { ArrayList() }.add(a)

        var raw = 0L; var verified = 0L; var pending = 0L; var rejected = 0L
        var suspicious = 0L; var unwit = 0L; var gap = 0L

        for (b in buckets) {
            if (b.startMs < from || b.startMs >= dayEndMs) continue
            val adj = adjByBucket[b.startMs]
            val (rawB, credB) = totals(b, adj)
            raw += rawB
            when (b.state) {
                LedgerState.VERIFIED, LedgerState.PARTIAL -> {
                    verified += credB
                    rejected += rawB - credB // un-credited excess (never reward-eligible)
                }
                LedgerState.REJECTED -> {
                    rejected += rawB
                    if (b.reason in SUSPICIOUS_REASONS) suspicious += rawB
                }
                LedgerState.UNWITNESSED -> unwit += rawB
                LedgerState.PENDING, LedgerState.GAP -> {} // never stored as a settled bucket row
            }
        }
        for ((start, steps) in pendingByBucket) {
            if (start in from until dayEndMs) pending += steps
        }
        for (g in gaps) {
            if (g.tsMs in from until dayEndMs) gap += g.steps
        }
        raw += pending + gap
        return DaySummary(raw, verified, pending, rejected, suspicious, unwit, gap)
    }

    /**
     * Current (raw, credited) of a settled bucket INCLUDING late-event adjustments, exactly like
     * `LedgerSummary.compute`: credited is clamped to [0, raw] because an adjustment's creditedAdded may be negative.
     */
    fun totals(b: BucketRecord, adjustments: List<Adjustment>?): Pair<Long, Long> {
        val adjRaw = adjustments?.sumOf { it.rawAdded } ?: 0
        val adjCred = adjustments?.sumOf { it.creditedAdded } ?: 0
        val rawB = (b.rawDelta + adjRaw).toLong()
        val credB = (b.credited + adjCred).coerceIn(0, rawB.toInt()).toLong()
        return rawB to credB
    }
}
