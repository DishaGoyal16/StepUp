package edu.thapar.stepup.steps

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * After a reboot or app update, resume tracking ONLY if the user had switched tracking on and never off.
 * The hardware counter restarts from 0 after a reboot; the first event is then a baseline-only event (no credit).
 * Foreground-service start from the background can be refused by the OS (Android 12+): failures are swallowed and
 * recorded in [WitnessRuntime.lastError]; the app restores tracking the next time the user opens it.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        if (!Prefs(context).trackingRequested) return
        if (!SensorProbe.activityRecognitionGranted(context)) return // permission revoked meanwhile: do not try
        try {
            SensorWitnessService.start(context)
        } catch (t: Throwable) {
            WitnessRuntime.lastError = "Boot restart refused by OS: ${t.javaClass.simpleName}"
        }
    }
}
