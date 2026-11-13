package com.stepup.trust.ledger

import com.stepup.trust.BucketStatus
import com.stepup.trust.Hop
import com.stepup.trust.HopLabel

/** The six bucket states of v2 §L5.2. Rewards use only VERIFIED and the credited part of PARTIAL. */
enum class LedgerState { PENDING, VERIFIED, PARTIAL, REJECTED, UNWITNESSED, GAP;

    companion object {
        fun from(s: BucketStatus) = when (s) {
            BucketStatus.VERIFIED -> VERIFIED
            BucketStatus.PARTIAL -> PARTIAL
            BucketStatus.REJECTED -> REJECTED
            BucketStatus.UNWITNESSED -> UNWITNESSED
        }
    }
}

/**
 * Immutable per-bucket row (v2 §7 `step_bucket`), written when a bucket settles. `hops` is the compact hop
 * evidence (`idx:L:imuSteps|...`) kept so a late counter event can be re-verified with the SAME evidence.
 */
data class BucketRecord(
    val startMs: Long,
    val bootCount: Int,
    val rawDelta: Int,
    val credited: Int,
    val state: LedgerState,
    val reason: String?,
    val walkFraction: Double,
    val imuSteps: Double,
    val carryMode: String,
    val evidenceMode: String,
    val hops: String,
    val coverage: Double,
    val arFlag: String?,
    val settledAtMs: Long,
) {
    fun decodeHops(): List<Hop> = decodeHops(startMs, hops)

    fun serialize(): List<Any?> = listOf(
        startMs, bootCount, rawDelta, credited, state.name, reason ?: "", walkFraction, imuSteps, carryMode,
        evidenceMode, hops, coverage, arFlag ?: "", settledAtMs,
    )

    companion object {
        fun deserialize(c: List<String>) = BucketRecord(
            startMs = c[0].toLong(), bootCount = c[1].toInt(), rawDelta = c[2].toInt(), credited = c[3].toInt(),
            state = LedgerState.valueOf(c[4]), reason = c[5].ifEmpty { null }, walkFraction = c[6].toDouble(),
            imuSteps = c[7].toDouble(), carryMode = c[8], evidenceMode = c[9], hops = c[10],
            coverage = c[11].toDouble(), arFlag = c[12].ifEmpty { null }, settledAtMs = c[13].toLong(),
        )

        private fun ch(l: HopLabel) = when (l) {
            HopLabel.WALK -> 'W'; HopLabel.RUN -> 'R'; HopLabel.SHAKE -> 'K'
            HopLabel.VEHICLE -> 'V'; HopLabel.STILL -> 'T'; HopLabel.UNKNOWN -> 'U'
        }

        private fun label(c: Char) = when (c) {
            'W' -> HopLabel.WALK; 'R' -> HopLabel.RUN; 'K' -> HopLabel.SHAKE
            'V' -> HopLabel.VEHICLE; 'T' -> HopLabel.STILL; else -> HopLabel.UNKNOWN
        }

        fun encodeHops(bucketStartMs: Long, hops: List<Hop>): String =
            hops.joinToString("|") { "${(it.startMs - bucketStartMs) / 2000}:${ch(it.label)}:${"%.2f".format(java.util.Locale.ROOT, it.imuSteps)}" }

        fun decodeHops(bucketStartMs: Long, enc: String): List<Hop> =
            if (enc.isEmpty()) emptyList() else enc.split("|").map {
                val p = it.split(":")
                Hop(bucketStartMs + p[0].toLong() * 2000, label(p[1][0]), p[2].toDouble())
            }
    }
}

/**
 * Append-only correction row for a counter event that arrived AFTER its bucket settled. Computed by re-running
 * the verifier with the bucket's stored hop evidence, so a late event can never bypass the IMU cap.
 * [creditedAdded] may be negative (e.g. the late steps push the bucket over the physical 35-step ceiling).
 */
data class Adjustment(
    val bucketStartMs: Long,
    val rawAdded: Int,
    val creditedAdded: Int,
    val reason: String,
    val atMs: Long,
) {
    fun serialize(): List<Any?> = listOf(bucketStartMs, rawAdded, creditedAdded, reason, atMs)

    companion object {
        fun deserialize(c: List<String>) = Adjustment(c[0].toLong(), c[1].toInt(), c[2].toInt(), c[3], c[4].toLong())
    }
}

/**
 * The two ledgers (v2 §L5.1) as numbers.
 *
 *  * DISPLAY / RAW   = every plausible counter step + GAP steps  ([displaySteps])
 *  * REWARD / VERIFIED = VERIFIED + credited part of PARTIAL      ([verifiedSteps])
 *
 * Reconciliation identity (checked by [reconciles]):
 *   rawAll = verified + pending + partialExcess + rejected + unwitnessed + gap
 *   display = rawAll - implausible     (implausible = REJECTED/CADENCE_EXCEEDED buckets, excluded from display)
 */
data class LedgerSummary(
    val rawAll: Long,
    val displaySteps: Long,
    val verifiedSteps: Long,
    val pendingSteps: Long,
    val partialExcessSteps: Long,
    val rejectedSteps: Long,
    val implausibleSteps: Long,
    val unwitnessedSteps: Long,
    val gapSteps: Long,
    val bucketsPending: Int,
    val bucketsVerified: Int,
    val bucketsPartial: Int,
    val bucketsRejected: Int,
    val bucketsUnwitnessed: Int,
) {
    fun reconciles(): Boolean =
        rawAll == verifiedSteps + pendingSteps + partialExcessSteps + rejectedSteps + unwitnessedSteps + gapSteps &&
            verifiedSteps <= displaySteps + implausibleSteps && verifiedSteps >= 0

    /** Invariant required by the spec: verified steps never exceed raw (display) steps. */
    fun verifiedNeverExceedsRaw(): Boolean = verifiedSteps <= rawAll

    companion object {
        fun compute(
            finalBuckets: Collection<BucketRecord>,
            adjustments: Collection<Adjustment>,
            pendingRawByBucket: Map<Long, Int>,
            gapSteps: Long,
        ): LedgerSummary {
            var verified = 0L; var partialExcess = 0L; var rejected = 0L; var implausible = 0L; var unwit = 0L
            var raw = 0L
            var nV = 0; var nP = 0; var nR = 0; var nU = 0
            val adjByBucket = adjustments.groupBy { it.bucketStartMs }
            for (b in finalBuckets) {
                val adjRaw = adjByBucket[b.startMs]?.sumOf { it.rawAdded } ?: 0
                val adjCred = adjByBucket[b.startMs]?.sumOf { it.creditedAdded } ?: 0
                val rawB = (b.rawDelta + adjRaw).toLong()
                val credB = (b.credited + adjCred).coerceIn(0, rawB.toInt()).toLong()
                raw += rawB
                when (b.state) {
                    LedgerState.VERIFIED, LedgerState.PARTIAL -> {
                        verified += credB; partialExcess += rawB - credB
                        if (b.state == LedgerState.VERIFIED) nV++ else nP++
                    }
                    LedgerState.REJECTED -> {
                        rejected += rawB; nR++
                        if (b.reason == "CADENCE_EXCEEDED") implausible += rawB
                    }
                    LedgerState.UNWITNESSED -> { unwit += rawB; nU++ }
                    else -> {}
                }
            }
            var pending = 0L
            for (v in pendingRawByBucket.values) pending += v
            raw += pending + gapSteps
            val display = raw - implausible
            return LedgerSummary(
                rawAll = raw, displaySteps = display, verifiedSteps = verified, pendingSteps = pending,
                partialExcessSteps = partialExcess, rejectedSteps = rejected, implausibleSteps = implausible,
                unwitnessedSteps = unwit, gapSteps = gapSteps, bucketsPending = pendingRawByBucket.size,
                bucketsVerified = nV, bucketsPartial = nP, bucketsRejected = nR, bucketsUnwitnessed = nU,
            )
        }
    }
}
