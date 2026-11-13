// BucketVerifier.kt
// Reference implementation from docs/StepUp_AntiFraud_Architecture_v2.md §8.1 (L4 Bucket Verifier).
// Kept API-compatible with the spec: do not change the rule without changing the nine golden vectors
// (BucketVerifierGoldenTest). Pure Kotlin (no Android imports) so it can be unit-tested on the JVM and replayed.
package com.stepup.trust

import kotlin.math.floor
import kotlin.math.min

enum class HopLabel { WALK, RUN, SHAKE, VEHICLE, STILL, UNKNOWN }

enum class BucketStatus { VERIFIED, PARTIAL, REJECTED, UNWITNESSED }

/**
 * One TYPE_STEP_COUNTER delta.
 * [tsMs] is the SENSOR timestamp (time of the LAST step in the event) mapped to UTC ms.
 * Never pass the time the event was delivered to your app.
 */
data class CounterDelta(val tsMs: Long, val delta: Int)

/**
 * One 2 s hop of IMU evidence.
 * [imuSteps] = gait peaks counted inside this hop only (hops are counted without overlap).
 */
data class Hop(val startMs: Long, val label: HopLabel, val imuSteps: Double)

data class BucketVerdict(
    val startMs: Long,
    val rawDelta: Int,
    val credited: Int,
    val status: BucketStatus,
    val reason: String?,
)

data class VerifierConfig(
    val bucketMs: Long = 10_000L,
    val hopMs: Long = 2_000L,
    val minCoverage: Double = 0.8,
    val minWalkFraction: Double = 0.5,
    val imuSlack: Double = 1.15,
    val maxStepsPerBucket: Int = 35, // 210 steps/min: physically impossible above this
)

/** Pure Kotlin (no Android imports) so it can be unit-tested on the JVM and replayed offline. */
class BucketVerifier(private val cfg: VerifierConfig = VerifierConfig()) {

    /** Returns null when the bucket contains no counter steps. */
    fun verify(
        startMs: Long,
        deltas: List<CounterDelta>,
        hops: List<Hop>,
        arSaysVehicle: Boolean,
    ): BucketVerdict? {
        val endMs = startMs + cfg.bucketMs
        val raw = deltas.filter { it.tsMs >= startMs && it.tsMs < endMs }.sumOf { it.delta }
        if (raw == 0) return null
        if (raw > cfg.maxStepsPerBucket) return rejected(startMs, raw, "CADENCE_EXCEEDED")

        val inBucket = hops.filter { it.startMs >= startMs && it.startMs < endMs }
        val expectedHops = (cfg.bucketMs / cfg.hopMs).toInt()
        if (inBucket.size.toDouble() / expectedHops < cfg.minCoverage) {
            return BucketVerdict(startMs, raw, 0, BucketStatus.UNWITNESSED, "NO_IMU_EVIDENCE")
        }
        if (arSaysVehicle) return rejected(startMs, raw, "IN_VEHICLE")

        val gait = inBucket.filter { it.label == HopLabel.WALK || it.label == HopLabel.RUN }
        val walkFraction = gait.size.toDouble() / inBucket.size
        if (walkFraction < cfg.minWalkFraction) {
            val dominant = inBucket
                .filter { it.label != HopLabel.WALK && it.label != HopLabel.RUN }
                .groupingBy { it.label }
                .eachCount()
                .maxByOrNull { it.value }
                ?.key
            val reason = when (dominant) {
                HopLabel.SHAKE -> "SHAKE_PATTERN"
                HopLabel.STILL -> "NO_MOTION_EVIDENCE"
                HopLabel.VEHICLE -> "VEHICLE_MOTION"
                else -> "NOT_GAIT"
            }
            return rejected(startMs, raw, reason)
        }

        // Credit can never exceed what the IMU independently counted as gait (plus slack).
        val allowed = floor(cfg.imuSlack * gait.sumOf { it.imuSteps }).toInt()
        val credited = min(raw, allowed)
        return when {
            credited == raw -> BucketVerdict(startMs, raw, credited, BucketStatus.VERIFIED, null)
            credited > 0 -> BucketVerdict(startMs, raw, credited, BucketStatus.PARTIAL, "EXCESS_OVER_IMU")
            else -> rejected(startMs, raw, "NO_GAIT_STEPS")
        }
    }

    private fun rejected(startMs: Long, raw: Int, reason: String) =
        BucketVerdict(startMs, raw, 0, BucketStatus.REJECTED, reason)
}
