package com.stepup.trust.bridge

import com.stepup.trust.store.AppendLog
import java.io.File

/** Result of [UserBinding.bind]: [changed] is true when the bound account differs from the stored one. */
data class BindResult(val changed: Boolean, val sinceMs: Long) {
    fun toMap(): Map<String, Any> = mapOf("bound" to true, "changed" to changed, "sinceMs" to sinceMs)
}

/**
 * Which account the on-device step ledger currently belongs to.
 *
 * The engine ledger is per INSTALL, not per user. When a different student signs in on the same phone, everything
 * counted before that moment must neither be shown nor synced under the new account. [sinceMs] is that boundary:
 * the bind time floored to a 10 s bucket boundary; consumers ignore buckets with `startMs < sinceMs`
 * (see [StepSummaryAggregator.aggregate] and [SyncLedger.pending]). Old rows are excluded, never deleted or acked.
 *
 *  * No uid ever bound   -> [sinceMs] = 0 (nothing filtered).
 *  * First bind / different uid -> [sinceMs] = floor(now); persisted.
 *  * Same uid again      -> [sinceMs] unchanged.
 *
 * Persistence: a one-row TSV (`uid, sinceMs`) replaced atomically (write temp + rename), in the same private
 * ledger directory as the acknowledgements, so it survives process death and reboot.
 * A bucket that straddles the bind instant (its start is the floored boundary) is included: at most 10 s of the
 * previous account's steps can leak into the new one, which is the documented granularity.
 */
class UserBinding(file: File, private val bucketMs: Long = 10_000L) {
    private val log = AppendLog(file)

    @Volatile var uid: String? = null; private set
    @Volatile var sinceMs: Long = 0L; private set

    init {
        val row = log.readAll().lastOrNull()
        if (row != null && row.size >= 2) {
            val s = row[1].toLongOrNull()
            if (row[0].isNotEmpty() && s != null) { uid = row[0]; sinceMs = s }
        }
    }

    @Synchronized
    fun bind(newUid: String, nowMs: Long): BindResult {
        require(newUid.isNotBlank() && newUid.none { it.isWhitespace() }) { "invalid uid" }
        if (uid == newUid) return BindResult(false, sinceMs)
        val since = Math.floorDiv(nowMs, bucketMs) * bucketMs
        log.rewrite(listOf(listOf(newUid, since))) // persist first; only then expose
        uid = newUid
        sinceMs = since
        return BindResult(true, since)
    }
}
