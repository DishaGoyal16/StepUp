package edu.thapar.stepup.steps

import android.content.Context
import android.content.SharedPreferences
import java.util.UUID

/**
 * Tiny SharedPreferences wrapper (private app storage, `allowBackup=false`, so nothing here is restored onto
 * another device). Holds only the "tracking was requested" flag and the per-install random device id.
 */
class Prefs(ctx: Context) {
    private val p: SharedPreferences = ctx.applicationContext.getSharedPreferences("witness_prefs", Context.MODE_PRIVATE)

    /** Persisted so a reboot / app update / process death can restore tracking (user turned it on and never off). */
    var trackingRequested: Boolean
        get() = p.getBoolean("tracking_requested", false)
        set(v) = p.edit().putBoolean("tracking_requested", v).apply()

    /**
     * E2 (PARTIAL_WAKE_LOCK during walking sessions) is OFF and nothing in the Flutter app can turn it on; kept
     * only so the ported evidence-mode selection behaves exactly like the tested prototype (E1 / E3 in practice).
     */
    var allowE2WakeLock: Boolean
        get() = p.getBoolean("allow_e2", false)
        set(v) = p.edit().putBoolean("allow_e2", v).apply()

    /**
     * Random UUID generated once per install. NOT an advertising id, IMEI, serial number or any hardware
     * identifier: it disappears with an uninstall / "clear data" and is never derived from the device.
     */
    @Synchronized
    fun deviceId(): String {
        p.getString("device_id", null)?.takeIf { it.isNotBlank() }?.let { return it }
        val id = UUID.randomUUID().toString()
        // commit(): the id is handed to the server, so it must be durable before we return it.
        p.edit().putString("device_id", id).commit()
        return id
    }
}
