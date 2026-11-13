package com.stepup.trust.witness

import com.stepup.trust.BucketStatus
import com.stepup.trust.BucketVerdict
import com.stepup.trust.BucketVerifier
import com.stepup.trust.CounterDelta
import com.stepup.trust.Hop
import com.stepup.trust.HopLabel
import com.stepup.trust.VerifierConfig
import com.stepup.trust.classify.CarryMode
import com.stepup.trust.classify.CarryModeEstimator
import com.stepup.trust.classify.ClassifierConfig
import com.stepup.trust.classify.ClassifyContext
import com.stepup.trust.classify.HopClassifier
import com.stepup.trust.classify.HopFeatures
import com.stepup.trust.classify.ImuHopProcessor
import com.stepup.trust.counter.CounterEvent
import com.stepup.trust.counter.CounterResult
import com.stepup.trust.counter.CounterTracker
import com.stepup.trust.counter.GapRecord
import com.stepup.trust.counter.StoredDelta
import com.stepup.trust.ledger.Adjustment
import com.stepup.trust.ledger.BucketRecord
import com.stepup.trust.ledger.LedgerState
import com.stepup.trust.ledger.LedgerSummary
import com.stepup.trust.store.LedgerStore
import java.util.TreeMap

/** Every tunable of the pipeline. Defaults = v2 parameter register (§13); all `[CAL]` unless noted. */
data class PipelineConfig(
    val classifier: ClassifierConfig = ClassifierConfig(),
    val verifier: VerifierConfig = VerifierConfig(),
    /** A bucket is final this long after it closes (v2: 10 s counter latency + 30 s batch + margin = 90 s). */
    val settleMs: Long = 90_000L,
    /** Counter-cadence window centred on a hop, used for the "cadence agreement" feature. */
    val counterCadenceWindowMs: Long = 12_000L,
    val arMinConfidence: Int = 65,
    val arConsecutive: Int = 2,
    val arMarginMs: Long = 45_000L,
    val arRejectBicycle: Boolean = true,
    /** Persisted hop records older than this are compacted away (a settled bucket keeps its own hop evidence). */
    val hopRetentionMs: Long = 48L * 3_600_000L,
    /** At most one compaction per this interval while running (plus one at startup). */
    val hopPruneIntervalMs: Long = 3_600_000L,
)

/** The newest IMU-only classification, for the UI's "current activity". Provisional (no counter context yet). */
data class LiveClassification(val hopStartMs: Long, val label: HopLabel, val trace: String)

data class PipelineSnapshot(
    val summary: LedgerSummary,
    val live: LiveClassification?,
    val carryMode: CarryMode,
    val lastRejection: String?,
    val hopsEmitted: Long,
    val hopsSkippedNoEvidence: Long,
    val accelSamples: Long,
    val gyroSamples: Long,
)

/**
 * The Sensor Witness brain (pure Kotlin): counter ledger (L2) + IMU hop processor (L3) + bucket verifier (L4) +
 * ledgers (L5). The live service and the offline replay harness drive exactly this class, so what is replayed is
 * what runs on the phone.
 *
 * Time: every timestamp passed in is a SENSOR timestamp mapped to UTC ms. `tick(nowMs)` takes the current time on
 * the same scale and settles buckets 90 s after they close.
 *
 * Safety invariants (tested): verified <= raw; steps without IMU evidence are never verified; a counter event can
 * never be credited twice; a late event is re-verified against the bucket's stored evidence.
 *
 * Thread-safety: all public methods are synchronized.
 */
class WitnessPipeline(
    private val store: LedgerStore,
    val config: PipelineConfig = PipelineConfig(),
    /**
     * Wall clock (UTC ms, same scale as sensor timestamps) used ONLY for the startup hop compaction. When null the
     * newest persisted hop is the reference, so synthetic/replay timelines are never pruned against the real date.
     */
    private val clock: (() -> Long)? = null,
) {
    private val bucketMs = config.verifier.bucketMs
    private val hopMs = config.verifier.hopMs

    private val tracker = CounterTracker(store.loadState())
    private val deltas = ArrayList<StoredDelta>(store.loadDeltas())
    private val gaps = ArrayList<GapRecord>(store.loadGaps())
    private val deltasByBucket = HashMap<Long, MutableList<StoredDelta>>()
    private val deltaIndex = TreeMap<Long, Int>() // sensor ts -> steps (for counter cadence)
    private val pendingRaw = TreeMap<Long, Int>() // bucketStart -> raw steps, buckets not yet settled
    private val finalBuckets = TreeMap<Long, BucketRecord>()
    private val adjustments = ArrayList<Adjustment>(store.loadAdjustments())
    private val hops = TreeMap<Long, Pair<HopFeatures, CarryMode>>() // working set for settlement (pruned)
    private val allHops = TreeMap<Long, Pair<HopFeatures, CarryMode>>() // full history for export / metrics

    private val carry = CarryModeEstimator(
        windowHops = config.classifier.carryWindowHops,
        minHops = config.classifier.carryMinHops,
        switchAfter = config.classifier.carrySwitchAfter,
    )
    private val classifier = HopClassifier(config.classifier)
    private val verifier = BucketVerifier(config.verifier)
    private val arTracker = ArVehicleTracker(config.arMinConfidence, config.arConsecutive, config.arMarginMs, config.arRejectBicycle)
    private var processor = newProcessor()

    @Volatile var evidenceMode: EvidenceMode = EvidenceMode.E3
    private var live: LiveClassification? = null
    private var lastRejection: String? = null
    private var lastNowMs = 0L

    private var lastHopPruneMs = Long.MIN_VALUE
    /** Number of hop-compaction attempts (startup excluded). Exposed for tests of the "at most once per hour" rule. */
    @Volatile var hopPruneRuns = 0; private set

    init {
        for (b in store.loadBuckets()) finalBuckets[b.startMs] = b
        for (d in deltas) indexDelta(d)
        for (e in store.loadAr()) arTracker.onEvent(e)
        for ((start, list) in deltasByBucket) {
            if (start !in finalBuckets) pendingRaw[start] = list.sumOf { it.delta }
        }
        // Hops are loaded LAST because startup compaction needs to know the oldest unsettled bucket.
        val loaded = store.loadHops()
        val newest = loaded.maxOfOrNull { it.first.startMs }
        val cutoff = if (newest == null) null else hopCutoff((clock?.invoke() ?: newest))
        val kept = if (cutoff == null) loaded else loaded.filter { it.first.startMs >= cutoff }
        if (cutoff != null && kept.size < loaded.size) store.pruneHops(cutoff)
        for ((h, c) in kept) { hops[h.startMs] = h to c; allHops[h.startMs] = h to c; carry.onHop(h.features) }
    }

    /**
     * Hops before this are dispensable: older than the retention AND not needed by a bucket that is still unsettled
     * (same 20 s margin as the working-set pruning in [tick]: hop window + counter-cadence window).
     */
    private fun hopCutoff(refMs: Long): Long {
        var cutoff = refMs - config.hopRetentionMs
        if (pendingRaw.isNotEmpty()) cutoff = minOf(cutoff, pendingRaw.firstKey() - 20_000L)
        return cutoff
    }

    private fun pruneHops(nowMs: Long) {
        hopPruneRuns++
        lastHopPruneMs = nowMs
        val cutoff = hopCutoff(nowMs)
        val before = allHops.size
        allHops.headMap(cutoff).clear()
        hops.headMap(cutoff).clear()
        if (allHops.size < before) store.pruneHops(cutoff)
    }

    private fun newProcessor() = ImuHopProcessor(config.classifier) { onHop(it) }

    private fun bucketStart(tsMs: Long) = Math.floorDiv(tsMs, bucketMs) * bucketMs

    private fun indexDelta(d: StoredDelta) {
        deltasByBucket.getOrPut(bucketStart(d.tsMs)) { ArrayList() }.add(d)
        deltaIndex.merge(d.tsMs, d.delta, Int::plus)
    }

    // ---- L2: step counter ---------------------------------------------------------------------------------------

    @Synchronized fun onListenerRegistered() = tracker.markRegistered()

    /**
     * Handles one counter event: updates the baseline, persists state BEFORE returning (so a crash right after
     * cannot lose it), and records the delta / gap. A delta whose bucket already settled becomes a late-event
     * adjustment instead of silently changing history.
     */
    @Synchronized
    fun onCounterEvent(e: CounterEvent): CounterResult {
        lastNowMs = maxOf(lastNowMs, e.deliveredAtMs)
        val r = tracker.onEvent(e)
        store.saveState(r.state)
        r.gap?.let { store.appendGap(it); gaps += it }
        r.delta?.let { d ->
            store.appendDelta(d)
            deltas += d
            indexDelta(d)
            val start = bucketStart(d.tsMs)
            if (start in finalBuckets) applyLateEvent(start, d) else pendingRaw.merge(start, d.delta, Int::plus)
        }
        return r
    }

    // ---- L3: IMU ------------------------------------------------------------------------------------------------

    @Synchronized fun onAccel(tMs: Double, x: Double, y: Double, z: Double) = processor.onAccel(tMs, x, y, z)
    @Synchronized fun onGyro(tMs: Double, x: Double, y: Double, z: Double) = processor.onGyro(tMs, x, y, z)

    @Synchronized
    fun onActivity(e: ArEvent) {
        store.appendAr(e)
        arTracker.onEvent(e)
    }

    private fun onHop(h: HopFeatures) {
        carry.onHop(h.features)
        val c = carry.mode
        hops[h.startMs] = h to c
        allHops[h.startMs] = h to c
        store.appendHop(h, c)
        val ar = arTracker.reasonFor(h.startMs, h.startMs + hopMs) != null
        val v = classifier.classify(h, ClassifyContext(carry = c, arVehicle = ar))
        live = LiveClassification(h.startMs, v.label, v.trace)
    }

    // ---- L4: settlement -----------------------------------------------------------------------------------------

    /** Settles every bucket whose 90 s settlement period has elapsed at [nowMs]. */
    @Synchronized
    fun tick(nowMs: Long) {
        lastNowMs = maxOf(lastNowMs, nowMs)
        while (pendingRaw.isNotEmpty()) {
            val start = pendingRaw.firstKey()
            if (start + bucketMs + config.settleMs > nowMs) break
            finalizeBucket(start, nowMs)
        }
        val oldestPending = if (pendingRaw.isEmpty()) Long.MAX_VALUE else pendingRaw.firstKey()
        val keepFrom = minOf(oldestPending - 20_000L, nowMs - 600_000L)
        hops.headMap(keepFrom).clear()
        if (lastHopPruneMs == Long.MIN_VALUE) lastHopPruneMs = nowMs // startup compaction already ran
        else if (nowMs - lastHopPruneMs >= config.hopPruneIntervalMs) pruneHops(nowMs)
    }

    /** End of a recording / replay: flush the IMU stream and settle EVERYTHING (as if far in the future). */
    @Synchronized
    fun finishAndSettleAll() {
        processor.finish()
        val far = (pendingRaw.lastEntry()?.key ?: 0L) + bucketMs + config.settleMs + 1
        while (pendingRaw.isNotEmpty()) finalizeBucket(pendingRaw.firstKey(), far)
    }

    private fun counterCadenceSpm(hopStartMs: Long): Double {
        val half = config.counterCadenceWindowMs / 2
        val centre = hopStartMs + hopMs / 2
        var steps = 0
        for (v in deltaIndex.subMap(centre - half, true, centre + half, false).values) steps += v
        if (steps < config.classifier.cadenceMinCounterSteps) return Double.NaN
        return steps * 60_000.0 / config.counterCadenceWindowMs
    }

    private fun classifyHops(start: Long, arReason: String?): Pair<List<Hop>, CarryMode> {
        val end = start + bucketMs
        val out = ArrayList<Hop>()
        var carryMode = CarryMode.UNKNOWN
        for ((_, entry) in hops.subMap(start, true, end, false)) {
            val (h, c) = entry
            carryMode = c
            val ctx = ClassifyContext(counterCadenceSpm = counterCadenceSpm(h.startMs), carry = c, arVehicle = arReason != null)
            out += Hop(h.startMs, classifier.classify(h, ctx).label, h.imuSteps)
        }
        return out to carryMode
    }

    /** One hop with its final label and the evidence trace, for CSV export and the replay confusion matrix. */
    data class ClassifiedHop(
        val startMs: Long,
        val label: HopLabel,
        val trace: String,
        val imuSteps: Double,
        val carry: CarryMode,
        val counterCadenceSpm: Double,
        val hasGyro: Boolean,
        val features: com.stepup.trust.classify.WindowFeatures?,
    )

    /**
     * Re-classifies EVERY persisted hop with the same context the settlement uses (counter cadence, carry mode,
     * AR hint). Used for exports and replay; does not change any ledger.
     */
    @Synchronized
    fun classifiedHopHistory(): List<ClassifiedHop> = classifiedHops(Long.MIN_VALUE, Long.MAX_VALUE)

    /** Hops whose start lies in [fromMs, toMs) with their final labels (bounded, cheap enough for the UI). */
    @Synchronized
    fun classifiedHops(fromMs: Long, toMs: Long): List<ClassifiedHop> {
        if (fromMs >= toMs) return emptyList()
        val out = ArrayList<ClassifiedHop>()
        for ((_, entry) in allHops.subMap(fromMs, true, toMs, false)) {
            val (h, c) = entry
            val ar = arTracker.reasonFor(h.startMs, h.startMs + hopMs)
            val cad = counterCadenceSpm(h.startMs)
            val v = classifier.classify(h, ClassifyContext(counterCadenceSpm = cad, carry = c, arVehicle = ar != null))
            out += ClassifiedHop(h.startMs, v.label, v.trace, h.imuSteps, c, cad, h.hasGyro, h.features)
        }
        return out
    }

    private fun finalizeBucket(start: Long, nowMs: Long) {
        val list = deltasByBucket[start] ?: emptyList()
        val arReason = arTracker.reasonFor(start, start + bucketMs)
        val (hopList, carryMode) = classifyHops(start, arReason)
        val verdict = verifier.verify(start, list.map { CounterDelta(it.tsMs, it.delta) }, hopList, arReason != null)
        pendingRaw.remove(start)
        if (verdict == null) return
        val gait = hopList.filter { it.label == HopLabel.WALK || it.label == HopLabel.RUN }
        val reason = if (verdict.reason == "IN_VEHICLE" && arReason == "ON_BICYCLE") "ON_BICYCLE" else verdict.reason
        val rec = BucketRecord(
            startMs = start,
            bootCount = list.firstOrNull()?.bootCount ?: -1,
            rawDelta = verdict.rawDelta,
            credited = verdict.credited,
            state = LedgerState.from(verdict.status),
            reason = reason,
            walkFraction = if (hopList.isEmpty()) 0.0 else gait.size.toDouble() / hopList.size,
            imuSteps = gait.sumOf { it.imuSteps },
            carryMode = carryMode.name,
            evidenceMode = evidenceMode.name,
            hops = BucketRecord.encodeHops(start, hopList),
            coverage = hopList.size.toDouble() / (bucketMs / hopMs),
            arFlag = arReason,
            settledAtMs = nowMs,
        )
        finalBuckets[start] = rec
        store.saveBucket(rec)
        noteRejection(rec)
    }

    private fun noteRejection(rec: BucketRecord) {
        if (rec.state == LedgerState.VERIFIED) return
        lastRejection = "${rec.reason ?: rec.state.name} (${rec.state.name}, ${rec.rawDelta - rec.credited} of ${rec.rawDelta} steps, bucket @${rec.startMs})"
    }

    /**
     * A counter event arrived for a bucket that already settled (e.g. delivered > 90 s late). Re-run the verifier
     * with the bucket's STORED hop evidence and record the difference as an append-only adjustment. The stored
     * evidence still applies, so a late event cannot bypass the IMU cap and cannot be credited twice.
     */
    private fun applyLateEvent(start: Long, d: StoredDelta) {
        val rec = finalBuckets.getValue(start)
        val all = deltasByBucket.getValue(start)
        val verdict: BucketVerdict? = verifier.verify(
            start, all.map { CounterDelta(it.tsMs, it.delta) }, rec.decodeHops(), rec.arFlag != null,
        )
        val alreadyCredited = rec.credited + adjustments.filter { it.bucketStartMs == start }.sumOf { it.creditedAdded }
        val newCredited = verdict?.credited ?: 0
        val adj = Adjustment(
            bucketStartMs = start,
            rawAdded = d.delta,
            creditedAdded = newCredited - alreadyCredited,
            reason = verdict?.reason ?: "LATE_EVENT",
            atMs = maxOf(lastNowMs, d.deliveredAtMs),
        )
        adjustments += adj
        store.appendAdjustment(adj)
        if (verdict != null && verdict.status != BucketStatus.VERIFIED) {
            lastRejection = "LATE_EVENT ${verdict.reason ?: verdict.status.name} (+${d.delta} raw, ${adj.creditedAdded} credited, bucket @$start)"
        }
    }

    // ---- views --------------------------------------------------------------------------------------------------

    @Synchronized fun summary(): LedgerSummary =
        LedgerSummary.compute(finalBuckets.values, adjustments, pendingRaw, gaps.sumOf { it.steps.toLong() })

    @Synchronized fun snapshot() = PipelineSnapshot(
        summary(), live, carry.mode, lastRejection, processor.hopsEmitted, processor.hopsSkippedNoEvidence,
        processor.accelRawSamples, processor.gyroRawSamples,
    )

    @Synchronized fun buckets(): List<BucketRecord> = finalBuckets.values.toList()
    @Synchronized fun adjustmentsList(): List<Adjustment> = adjustments.toList()
    @Synchronized fun pendingBuckets(): Map<Long, Int> = pendingRaw.toMap()
    @Synchronized fun counterDeltas(): List<StoredDelta> = deltas.toList()
    @Synchronized fun counterGaps(): List<GapRecord> = gaps.toList()
    @Synchronized fun rawDeltaTotal(): Long = deltas.sumOf { it.delta.toLong() }
    @Synchronized fun gapTotal(): Long = gaps.sumOf { it.steps.toLong() }
    @Synchronized fun carryMode(): CarryMode = carry.mode

    /** Reset Test Session: forget baseline, deltas, gaps, hops, buckets. The next counter event is a fresh baseline. */
    @Synchronized
    fun resetSession() {
        store.clear()
        tracker.reset()
        deltas.clear(); gaps.clear(); deltasByBucket.clear(); deltaIndex.clear(); pendingRaw.clear()
        finalBuckets.clear(); adjustments.clear(); hops.clear(); allHops.clear()
        carry.reset(); arTracker.reset()
        processor = newProcessor()
        live = null; lastRejection = null
    }
}
