package edu.thapar.stepup.steps

import android.content.Context
import com.stepup.trust.bridge.SyncLedger
import com.stepup.trust.bridge.UserBinding
import com.stepup.trust.store.FileLedgerStore
import com.stepup.trust.witness.WitnessPipeline
import java.io.File

/**
 * Process-wide holder shared by the foreground service (the single writer to the on-disk ledger) and the Flutter
 * bridge (reader). One pipeline per process => exactly one writer.
 */
object WitnessRuntime {
    @Volatile private var pipelineInstance: WitnessPipeline? = null
    @Volatile private var syncLedgerInstance: SyncLedger? = null
    @Volatile private var bindingInstance: UserBinding? = null

    /** The live engine while the foreground service runs (null otherwise). */
    @Volatile var engineRef: WitnessEngine? = null

    @Volatile var serviceRunning: Boolean = false
    @Volatile var lastError: String? = null

    /** Latest Activity Recognition status (diagnostic only). */
    @Volatile var arStatus: String = "not started"

    fun ledgerDir(ctx: Context): File = File(ctx.applicationContext.filesDir, "ledger").also { it.mkdirs() }

    fun pipeline(ctx: Context): WitnessPipeline {
        pipelineInstance?.let { return it }
        synchronized(this) {
            return pipelineInstance ?: WitnessPipeline(
                FileLedgerStore(ledgerDir(ctx)),
                // The wall clock lets the startup hop compaction drop hops older than 48 h even after a long downtime.
                clock = { System.currentTimeMillis() },
            ).also { pipelineInstance = it }
        }
    }

    /** Sync-acknowledgement ledger (native-side bookkeeping for `getBucketsForSync` / `ackBuckets`). */
    fun syncLedger(ctx: Context): SyncLedger {
        syncLedgerInstance?.let { return it }
        synchronized(this) {
            return syncLedgerInstance ?: SyncLedger(File(ledgerDir(ctx), "acks.tsv")).also { syncLedgerInstance = it }
        }
    }

    /** Which signed-in account the ledger belongs to (see [UserBinding]); persisted next to the acknowledgements. */
    fun binding(ctx: Context): UserBinding {
        bindingInstance?.let { return it }
        synchronized(this) {
            return bindingInstance ?: UserBinding(File(ledgerDir(ctx), "binding.tsv")).also { bindingInstance = it }
        }
    }
}
