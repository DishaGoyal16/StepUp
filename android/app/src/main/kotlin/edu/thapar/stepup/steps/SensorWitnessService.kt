package edu.thapar.stepup.steps

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import edu.thapar.stepup.MainActivity
import edu.thapar.stepup.R

/**
 * Foreground service (type `health`) that keeps the Sensor Witness alive with the screen off.
 * Android 9+ gives background apps no continuous sensor events, so a foreground service is the supported way
 * (v2 §L2.1). START_STICKY + the persisted "tracking requested" flag let it come back after a process kill; any
 * steps counted while it was dead become a display-only GAP (never reward-eligible).
 */
class SensorWitnessService : Service() {
    private var engine: WitnessEngine? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopTracking()
            return START_NOT_STICKY
        }
        // A sticky restart (null intent) after the user switched tracking off must not resurrect the service.
        if (intent == null && !Prefs(this).trackingRequested) {
            stopSelf()
            return START_NOT_STICKY
        }
        startTracking()
        return START_STICKY
    }

    private fun startTracking() {
        if (engine != null) return
        try {
            promoteToForeground()
        } catch (t: Throwable) {
            // e.g. ForegroundServiceStartNotAllowedException or SecurityException (permission missing).
            WitnessRuntime.lastError = "Cannot start foreground service: ${t.javaClass.simpleName}: ${t.message}"
            stopSelf()
            return
        }
        val e = try {
            WitnessEngine(applicationContext)
        } catch (t: Throwable) {
            WitnessRuntime.lastError = "Engine init failed: ${t.javaClass.simpleName}: ${t.message}"
            Prefs(this).trackingRequested = false
            stopForegroundCompat()
            stopSelf()
            return
        }
        if (!e.start()) {
            // Without TYPE_STEP_COUNTER there is nothing to witness; do not sit in the foreground doing nothing.
            WitnessRuntime.lastError = "NO_STEP_COUNTER"
            e.stop()
            Prefs(this).trackingRequested = false
            stopForegroundCompat()
            stopSelf()
            return
        }
        WitnessRuntime.lastError = null
        engine = e
        WitnessRuntime.engineRef = e
        WitnessRuntime.serviceRunning = true
        Prefs(this).trackingRequested = true
    }

    private fun stopTracking() {
        Prefs(this).trackingRequested = false
        engine?.stop()
        engine = null
        WitnessRuntime.engineRef = null
        WitnessRuntime.serviceRunning = false
        stopForegroundCompat()
        stopSelf()
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE) else @Suppress("DEPRECATION") stopForeground(true)
    }

    override fun onDestroy() {
        // Do NOT clear trackingRequested here: an OS kill must still allow a restart. Only Stop clears it.
        engine?.stop()
        engine = null
        WitnessRuntime.engineRef = null
        WitnessRuntime.serviceRunning = false
        super.onDestroy()
    }

    private fun promoteToForeground() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Step tracking", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL_ID)
        else @Suppress("DEPRECATION") Notification.Builder(this)
        val notification = builder
            .setContentTitle("StepUp is counting verified steps")
            .setContentText("Step tracking is running in the background")
            .setSmallIcon(R.drawable.ic_stat_steps)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    companion object {
        const val ACTION_STOP = "edu.thapar.stepup.steps.STOP"
        private const val CHANNEL_ID = "step_tracking"
        private const val NOTIFICATION_ID = 1001

        fun start(ctx: Context) {
            val i = Intent(ctx, SensorWitnessService::class.java)
            if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
        }

        fun stop(ctx: Context) {
            // Delivered as a normal start command so a running service handles it; it then stops itself.
            val i = Intent(ctx, SensorWitnessService::class.java).setAction(ACTION_STOP)
            Prefs(ctx).trackingRequested = false
            if (WitnessRuntime.serviceRunning) ctx.startService(i)
        }
    }
}
