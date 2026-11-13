package com.stepup.trust.store

import com.stepup.trust.counter.CounterState
import com.stepup.trust.counter.GapRecord
import com.stepup.trust.counter.StoredDelta
import java.io.File

/** Persistence for the counter ledger (v2 §7 `counter_state`, plus the delta and gap logs). */
interface CounterStore {
    fun loadState(): CounterState?
    fun saveState(s: CounterState)
    fun appendDelta(d: StoredDelta)
    fun appendGap(g: GapRecord)
    fun loadDeltas(): List<StoredDelta>
    fun loadGaps(): List<GapRecord>
    fun clear()
}

class InMemoryCounterStore : CounterStore {
    private var state: CounterState? = null
    private val deltas = mutableListOf<StoredDelta>()
    private val gaps = mutableListOf<GapRecord>()
    override fun loadState() = state
    override fun saveState(s: CounterState) { state = s }
    override fun appendDelta(d: StoredDelta) { deltas += d }
    override fun appendGap(g: GapRecord) { gaps += g }
    override fun loadDeltas() = deltas.toList()
    override fun loadGaps() = gaps.toList()
    override fun clear() { state = null; deltas.clear(); gaps.clear() }
}

class FileCounterStore(private val dir: File) : CounterStore {
    private val stateLog = AppendLog(File(dir, "counter_state.tsv"))
    private val deltaLog = AppendLog(File(dir, "deltas.tsv"))
    private val gapLog = AppendLog(File(dir, "gaps.tsv"))

    override fun loadState(): CounterState? {
        val r = stateLog.readAll().lastOrNull() ?: return null
        return try {
            CounterState(r[0].toInt(), r[1].toLong(), r[2].toLong(), r[3].toLong())
        } catch (_: Exception) {
            null // corrupt/truncated state => treat as no state => next event is a fresh baseline (safe)
        }
    }

    override fun saveState(s: CounterState) =
        stateLog.rewrite(listOf(listOf(s.bootCount, s.lastCumulative, s.lastTsMs, s.lastSensorTsNs)))

    override fun appendDelta(d: StoredDelta) =
        deltaLog.append(d.tsMs, d.delta, d.bootCount, d.cumulative, d.sensorTsNs, d.deliveredAtMs)

    override fun appendGap(g: GapRecord) = gapLog.append(g.tsMs, g.steps, g.reason)

    override fun loadDeltas(): List<StoredDelta> = deltaLog.readAll().mapNotNull {
        try {
            StoredDelta(it[0].toLong(), it[1].toInt(), it[2].toInt(), it[3].toLong(), it[4].toLong(), it[5].toLong())
        } catch (_: Exception) { null }
    }

    override fun loadGaps(): List<GapRecord> = gapLog.readAll().mapNotNull {
        try { GapRecord(it[0].toLong(), it[1].toInt(), it[2]) } catch (_: Exception) { null }
    }

    override fun clear() {
        stateLog.delete(); deltaLog.delete(); gapLog.delete()
    }
}
