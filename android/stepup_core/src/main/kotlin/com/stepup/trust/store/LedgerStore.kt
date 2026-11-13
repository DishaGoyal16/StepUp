package com.stepup.trust.store

import com.stepup.trust.classify.CarryMode
import com.stepup.trust.classify.HopFeatures
import com.stepup.trust.ledger.Adjustment
import com.stepup.trust.ledger.BucketRecord
import com.stepup.trust.witness.ArEvent
import com.stepup.trust.witness.ArType
import java.io.File

/**
 * Everything the Witness persists. Append-only logs (no Room/SQLite, documented deviation) so the whole
 * persistence layer is plain JVM and unit-testable. Settled bucket rows are immutable; corrections are
 * [Adjustment] rows.
 */
interface LedgerStore : CounterStore {
    fun appendHop(h: HopFeatures, carry: CarryMode)
    fun loadHops(): List<Pair<HopFeatures, CarryMode>>
    fun appendAr(e: ArEvent)
    fun loadAr(): List<ArEvent>
    fun saveBucket(b: BucketRecord)
    fun loadBuckets(): List<BucketRecord>
    fun appendAdjustment(a: Adjustment)
    fun loadAdjustments(): List<Adjustment>

    /**
     * Drops persisted hop records whose `startMs < beforeStartMs` (hops are only needed while a bucket is unsettled;
     * a settled bucket keeps its own compact hop evidence). @return how many records were removed.
     */
    fun pruneHops(beforeStartMs: Long): Int = 0
}

class InMemoryLedgerStore : LedgerStore, CounterStore by InMemoryCounterStore() {
    private val hops = mutableListOf<Pair<HopFeatures, CarryMode>>()
    private val ar = mutableListOf<ArEvent>()
    private val buckets = mutableListOf<BucketRecord>()
    private val adj = mutableListOf<Adjustment>()
    override fun appendHop(h: HopFeatures, carry: CarryMode) { hops += h to carry }
    override fun loadHops() = hops.toList()
    override fun pruneHops(beforeStartMs: Long): Int {
        val n = hops.size
        hops.removeAll { it.first.startMs < beforeStartMs }
        return n - hops.size
    }
    override fun appendAr(e: ArEvent) { ar += e }
    override fun loadAr() = ar.toList()
    override fun saveBucket(b: BucketRecord) { buckets += b }
    override fun loadBuckets() = buckets.toList()
    override fun appendAdjustment(a: Adjustment) { adj += a }
    override fun loadAdjustments() = adj.toList()
}

class FileLedgerStore(
    dir: File,
    private val counter: FileCounterStore = FileCounterStore(dir),
) : LedgerStore, CounterStore by counter {
    private val hopLog = AppendLog(File(dir, "hops.tsv"))
    private val arLog = AppendLog(File(dir, "ar.tsv"))
    private val bucketLog = AppendLog(File(dir, "buckets.tsv"))
    private val adjLog = AppendLog(File(dir, "adjustments.tsv"))

    override fun appendHop(h: HopFeatures, carry: CarryMode) =
        hopLog.append(*(h.serialize() + carry.name).toTypedArray())

    override fun loadHops(): List<Pair<HopFeatures, CarryMode>> = hopLog.readAll().mapNotNull {
        try { HopFeatures.deserialize(it.dropLast(1)) to CarryMode.valueOf(it.last()) } catch (_: Exception) { null }
    }

    override fun pruneHops(beforeStartMs: Long): Int {
        val rows = hopLog.readAll()
        // A row whose first field is unreadable is kept (never destroy data we cannot interpret).
        val kept = rows.filter { (it.firstOrNull()?.toLongOrNull() ?: Long.MAX_VALUE) >= beforeStartMs }
        if (kept.size == rows.size) return 0
        hopLog.rewrite(kept)
        return rows.size - kept.size
    }

    override fun appendAr(e: ArEvent) = arLog.append(e.tsMs, e.type.name, e.confidence)

    override fun loadAr(): List<ArEvent> = arLog.readAll().mapNotNull {
        try { ArEvent(it[0].toLong(), ArType.valueOf(it[1]), it[2].toInt()) } catch (_: Exception) { null }
    }

    override fun saveBucket(b: BucketRecord) = bucketLog.append(*b.serialize().toTypedArray())

    override fun loadBuckets(): List<BucketRecord> = bucketLog.readAll().mapNotNull {
        try { BucketRecord.deserialize(it) } catch (_: Exception) { null }
    }

    override fun appendAdjustment(a: Adjustment) = adjLog.append(*a.serialize().toTypedArray())

    override fun loadAdjustments(): List<Adjustment> = adjLog.readAll().mapNotNull {
        try { Adjustment.deserialize(it) } catch (_: Exception) { null }
    }

    override fun clear() {
        counter.clear(); hopLog.delete(); arLog.delete(); bucketLog.delete(); adjLog.delete()
    }
}
