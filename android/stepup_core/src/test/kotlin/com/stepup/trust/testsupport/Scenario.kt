package com.stepup.trust.testsupport

import com.stepup.trust.counter.CounterEvent
import com.stepup.trust.witness.ArEvent
import com.stepup.trust.witness.WitnessPipeline

/**
 * Synthetic step-counter + delivery simulator (TEST ONLY). Mimics what AOSP documents: the event timestamp is the
 * LAST step in the event, events group several steps (bigger lump at the start of a bout) and are delivered up to
 * ~10 s late. IMU frames may arrive in batches. None of this exists in `src/main`.
 */
object CounterSynth {
    /** Groups [stepTimesMs] into counter events. [base] = cumulative at the baseline event (placed 1 s before). */
    fun events(
        stepTimesMs: List<Double>, seed: Long = 9, base: Long = 10_000, boot: Int = 1,
        maxLagMs: Double = 10_000.0, baseline: Boolean = true, baselineAtMs: Long? = null,
    ): List<CounterEvent> {
        val rnd = java.util.Random(seed)
        val out = ArrayList<CounterEvent>()
        val sorted = stepTimesMs.sorted()
        var cum = base
        if (baseline && sorted.isNotEmpty()) {
            val t = baselineAtMs ?: (sorted.first().toLong() - 1_000)
            out += CounterEvent(t * 1_000_000L, t, cum, boot, t + 100)
        }
        var i = 0
        var prevTs = Double.NEGATIVE_INFINITY
        var lastDelivery = 0.0
        while (i < sorted.size) {
            val bout = sorted[i] - prevTs > 4_000
            val k = if (bout) 6 + rnd.nextInt(3) else 2 + rnd.nextInt(4)
            val group = sorted.subList(i, minOf(sorted.size, i + k))
            i += group.size
            val ts = group.last()
            prevTs = ts
            cum += group.size
            val delivery = maxOf(ts + rnd.nextDouble() * maxLagMs, lastDelivery)
            lastDelivery = delivery
            out += CounterEvent(ts.toLong() * 1_000_000L, ts.toLong(), cum, boot, delivery.toLong())
        }
        return out
    }
}

/** Feeds IMU frames + counter events + AR events to a pipeline in DELIVERY order, ticking the clock. */
class ScenarioRunner(val pipeline: WitnessPipeline) {
    private class Item(val deliverAt: Double, val order: Int, val run: () -> Unit)

    fun run(
        imu: Synth.Signal?,
        counter: List<CounterEvent>,
        ar: List<ArEvent> = emptyList(),
        imuBatchMs: Double = 30_000.0,
        finish: Boolean = true,
    ) {
        val items = ArrayList<Item>()
        var n = 0
        imu?.frames?.forEach { f ->
            val deliverAt = if (imuBatchMs <= 0) f.tMs else (Math.floor(f.tMs / imuBatchMs) + 1) * imuBatchMs
            items += Item(deliverAt, n++) {
                pipeline.onAccel(f.tMs, f.a[0], f.a[1], f.a[2])
                f.g?.let { pipeline.onGyro(f.tMs, it[0], it[1], it[2]) }
            }
        }
        counter.forEach { e -> items += Item(e.deliveredAtMs.toDouble(), n++) { pipeline.onCounterEvent(e) } }
        ar.forEach { e -> items += Item(e.tsMs + 20_000.0, n++) { pipeline.onActivity(e) } }
        items.sortWith(compareBy<Item> { it.deliverAt }.thenBy { it.order })
        var lastTick = 0.0
        for (it in items) {
            it.run()
            if (it.deliverAt - lastTick >= 2_000) { pipeline.tick(it.deliverAt.toLong()); lastTick = it.deliverAt }
        }
        if (finish) pipeline.finishAndSettleAll()
    }
}
