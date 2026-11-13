package com.stepup.trust.bridge

import com.stepup.trust.ledger.Adjustment
import com.stepup.trust.ledger.BucketRecord
import com.stepup.trust.store.AppendLog
import java.io.File

/**
 * Native bookkeeping for "which settled buckets has Dart already synced and acknowledged".
 *
 * Persistence: an append-only TSV (`startMs, ackedVersion, ackedAtMs`), fsynced per ack, last/max row wins,
 * pruned to [retentionMs] (14 days) when the file is loaded and whenever an ack is written. Survives process death
 * and reboot (plain file in private storage).
 *
 * Versioning (late adjustments): the "version" of a bucket is the number of late-event [Adjustment] rows that exist
 * for it. An ack records the version that was OFFERED to Dart (remembered in memory when [pending] returned the item).
 * If a late adjustment arrives afterwards, version > ackedVersion, so the bucket is offered AGAIN (with the updated
 * totals and `lateRawAdded > 0`) until Dart acknowledges that newer version. If the offered-version memory is lost
 * (process death between sync and ack) the ack falls back to version 0, which can only cause one extra re-offer of a
 * bucket that has adjustments, never a lost one (at-least-once; server IDs are deterministic).
 *
 * Buckets older than [offerWindowMs] (72 h, the server's acceptance window) are not offered: the server would reject
 * them anyway, and not offering them stops ancient rejects from starving newer buckets under the `limit`.
 * [offerWindowMs] <= [retentionMs] guarantees a pruned ack entry can never make an old bucket look un-acked.
 */
class SyncLedger(
    file: File,
    private val retentionMs: Long = 14L * DAY_MS,
    private val offerWindowMs: Long = 72L * HOUR_MS,
    nowMs: Long = System.currentTimeMillis(),
) {
    private val log = AppendLog(file)
    private val acked = HashMap<Long, Int>()          // startMs -> highest acknowledged version
    private val offered = HashMap<Long, Int>()        // startMs -> version last returned by pending()

    init {
        require(offerWindowMs <= retentionMs) { "offer window must not exceed ack retention" }
        for (r in log.readAll()) {
            try {
                val start = r[0].toLong(); val v = r[1].toInt()
                if (v > (acked[start] ?: -1)) acked[start] = v
            } catch (_: Exception) { /* torn last line: ignore, worst case one bucket is offered again */ }
        }
        prune(nowMs)
    }

    /** Settled, not-yet-acknowledged (or acknowledged-but-since-adjusted) buckets, oldest first. */
    @Synchronized
    fun pending(
        buckets: Collection<BucketRecord>,
        adjustments: Collection<Adjustment>,
        limit: Int,
        nowMs: Long,
        sinceMs: Long = 0L,
    ): List<SyncItem> {
        if (limit <= 0) return emptyList()
        val adjBy = adjustments.groupBy { it.bucketStartMs }
        // Buckets before the user-binding boundary belong to a previous account: never offered (and never acked).
        val horizon = maxOf(nowMs - offerWindowMs, sinceMs)
        val out = ArrayList<SyncItem>()
        for (b in buckets.sortedBy { it.startMs }) {
            if (out.size >= limit) break
            if (!SyncExportMapper.isSyncable(b) || b.startMs < horizon) continue
            val adj = adjBy[b.startMs]
            val version = adj?.size ?: 0
            val ackedVersion = acked[b.startMs]
            if (ackedVersion != null && ackedVersion >= version) continue
            offered[b.startMs] = version
            out += SyncExportMapper.toItem(b, adj)
        }
        return out
    }

    /**
     * Records acknowledgements. Only [knownSettled] start times count (an ack for something that is not a settled
     * bucket cannot suppress a future bucket). Idempotent. @return how many of [startMsList] are acknowledged after
     * the call (already-acked ones included, unknown ones excluded).
     */
    @Synchronized
    fun ack(startMsList: Collection<Long>, knownSettled: Set<Long>, nowMs: Long): Int {
        var count = 0
        for (start in startMsList.toSet()) {
            if (start !in knownSettled) continue
            count++
            val v = offered[start] ?: 0
            val cur = acked[start]
            if (cur != null && cur >= v) continue
            acked[start] = v
            log.append(start, v, nowMs)
        }
        prune(nowMs)
        return count
    }

    @Synchronized fun isAcked(startMs: Long): Boolean = acked.containsKey(startMs)
    @Synchronized fun ackedCount(): Int = acked.size

    private fun prune(nowMs: Long) {
        val cutoff = nowMs - retentionMs
        val before = acked.size
        acked.keys.removeAll { it < cutoff }
        offered.keys.removeAll { it < cutoff }
        if (acked.size != before) {
            log.rewrite(acked.entries.sortedBy { it.key }.map { listOf(it.key, it.value, nowMs) })
        }
    }

    companion object {
        const val HOUR_MS = 3_600_000L
        const val DAY_MS = 24 * HOUR_MS
    }
}
