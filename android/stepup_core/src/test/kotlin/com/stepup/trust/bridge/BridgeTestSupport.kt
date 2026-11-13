package com.stepup.trust.bridge

import com.stepup.trust.Hop
import com.stepup.trust.HopLabel
import com.stepup.trust.ledger.Adjustment
import com.stepup.trust.ledger.BucketRecord
import com.stepup.trust.ledger.LedgerState

/** Builds settled-bucket rows for the bridge tests (TEST ONLY; never used in production code). */
internal fun rec(
    start: Long,
    raw: Int,
    credited: Int,
    state: LedgerState,
    reason: String? = null,
    hops: List<Hop> = emptyList(),
) = BucketRecord(
    startMs = start, bootCount = 7, rawDelta = raw, credited = credited, state = state, reason = reason,
    walkFraction = 0.8, imuSteps = hops.sumOf { it.imuSteps }, carryMode = "HAND", evidenceMode = "E1",
    hops = BucketRecord.encodeHops(start, hops), coverage = hops.size / 5.0, arFlag = null, settledAtMs = start + 100_000,
)

internal fun walkHops(start: Long, n: Int = 5, steps: Double = 2.0) =
    (0 until n).map { Hop(start + it * 2_000L, HopLabel.WALK, steps) }

internal fun adj(start: Long, rawAdded: Int, creditedAdded: Int) =
    Adjustment(start, rawAdded, creditedAdded, "LATE_EVENT", start + 200_000)
