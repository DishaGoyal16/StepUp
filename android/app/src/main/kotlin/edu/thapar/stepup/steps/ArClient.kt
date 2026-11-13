package edu.thapar.stepup.steps

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityRecognitionResult
import com.google.android.gms.location.DetectedActivity
import com.stepup.trust.witness.ArEvent
import com.stepup.trust.witness.ArType

/**
 * Activity Recognition as an optional, DOWNGRADE-ONLY hint (v2 §L2.3). Needs Google Play services and the
 * ACTIVITY_RECOGNITION permission. When either is missing (or anything throws) the status string says so and the
 * IMU classifier alone decides: tracking never depends on this class. Periodic updates only (no Transition API).
 */
object ArClient {
    private fun pendingIntent(ctx: Context): PendingIntent {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
        return PendingIntent.getBroadcast(ctx.applicationContext, 7, Intent(ctx.applicationContext, ArReceiver::class.java), flags)
    }

    fun register(ctx: Context) {
        try {
            val caps = SensorProbe.probe(ctx)
            if (caps.activityRecognitionAvailable != true) {
                WitnessRuntime.arStatus = "unavailable (no Google Play services)"
                return
            }
            if (caps.activityRecognitionPermissionGranted != true) {
                WitnessRuntime.arStatus = "unavailable (ACTIVITY_RECOGNITION not granted)"
                return
            }
            ActivityRecognition.getClient(ctx.applicationContext)
                .requestActivityUpdates(15_000L, pendingIntent(ctx))
                .addOnSuccessListener { WitnessRuntime.arStatus = "registered (15 s updates)" }
                .addOnFailureListener { WitnessRuntime.arStatus = "registration failed: ${it.javaClass.simpleName}" }
        } catch (t: Throwable) {
            WitnessRuntime.arStatus = "error: ${t.javaClass.simpleName}"
        }
    }

    fun unregister(ctx: Context) {
        try {
            ActivityRecognition.getClient(ctx.applicationContext).removeActivityUpdates(pendingIntent(ctx))
        } catch (_: Throwable) { }
        WitnessRuntime.arStatus = "stopped"
    }

    internal fun map(type: Int): ArType = when (type) {
        DetectedActivity.IN_VEHICLE -> ArType.IN_VEHICLE
        DetectedActivity.ON_BICYCLE -> ArType.ON_BICYCLE
        DetectedActivity.ON_FOOT -> ArType.ON_FOOT
        DetectedActivity.WALKING -> ArType.WALKING
        DetectedActivity.RUNNING -> ArType.RUNNING
        DetectedActivity.STILL -> ArType.STILL
        DetectedActivity.TILTING -> ArType.TILTING
        else -> ArType.UNKNOWN
    }
}

class ArReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            if (!ActivityRecognitionResult.hasResult(intent)) return
            val result = ActivityRecognitionResult.extractResult(intent) ?: return
            val top = result.mostProbableActivity ?: return
            // result.elapsedRealtimeMillis is on the elapsedRealtime clock => map to UTC like sensor timestamps.
            val utc = System.currentTimeMillis() - (SystemClock.elapsedRealtime() - result.elapsedRealtimeMillis)
            val ev = ArEvent(utc, ArClient.map(top.type), top.confidence)
            WitnessRuntime.pipeline(context).onActivity(ev)
            WitnessRuntime.engineRef?.onActivityRecognition(ev)
        } catch (_: Throwable) {
            // The AR hint is optional; never let a failure here crash the app.
        }
    }
}
