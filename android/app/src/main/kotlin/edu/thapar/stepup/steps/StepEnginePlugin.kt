package edu.thapar.stepup.steps

import android.app.NotificationManager
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import com.stepup.trust.bridge.StepSummaryAggregator
import com.stepup.trust.witness.EvidenceModeSelector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * Flutter bridge for the genuine-step engine. Implements exactly the contract in DATABASE_SCHEMA.md
 * ("Android ⇄ Flutter channel contract"):
 *
 *  MethodChannel `edu.thapar.stepup/engine`: getCapabilities, startTracking, stopTracking, isTracking,
 *  getTodaySummary, getBucketsForSync, ackBuckets, getLiveStatus, getDeviceId, bindUser {uid}.
 *  EventChannel `edu.thapar.stepup/engine_events`: a map every 2 s while a listener is attached and tracking.
 *
 * Runtime permission prompts are NOT done here (Dart/permission_handler does them); this class only reports state.
 * Nothing in this bridge can start raw IMU recording (that prototype feature was not ported).
 * All ledger work runs on a background thread; results are posted back to the main thread.
 */
class StepEnginePlugin(context: Context) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val app: Context = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val io: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor { r ->
        Thread(r, "stepup-engine-bridge").apply { isDaemon = true }
    }

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var sink: EventChannel.EventSink? = null
    private var ticker: ScheduledFuture<*>? = null
    @Volatile private var lastEmittedTracking = false

    fun register(messenger: BinaryMessenger) {
        methodChannel = MethodChannel(messenger, METHOD_CHANNEL).also { it.setMethodCallHandler(this) }
        eventChannel = EventChannel(messenger, EVENT_CHANNEL).also { it.setStreamHandler(this) }
        // Load the on-disk ledgers off the main thread now, so the first real call (or the service start) is cheap.
        io.execute { try { WitnessRuntime.pipeline(app) } catch (t: Throwable) { Log.w(TAG, "ledger warm-up failed", t) } }
    }

    fun dispose() {
        methodChannel?.setMethodCallHandler(null); methodChannel = null
        eventChannel?.setStreamHandler(null); eventChannel = null
        onCancel(null)
        io.shutdown()
    }

    // ---- MethodChannel ------------------------------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        io.execute {
            try {
                val value: Any? = when (call.method) {
                    "getCapabilities" -> capabilities()
                    "startTracking" -> startTracking()
                    "stopTracking" -> { SensorWitnessService.stop(app); emptyMap<String, Any>() }
                    "isTracking" -> isTracking()
                    "getTodaySummary" -> todaySummary(call)
                    "getBucketsForSync" -> bucketsForSync(call)
                    "ackBuckets" -> ackBuckets(call)
                    "getLiveStatus" -> liveStatus()
                    "getDeviceId" -> Prefs(app).deviceId()
                    "bindUser" -> bindUser(call)
                    else -> { main.post { result.notImplemented() }; return@execute }
                }
                main.post { result.success(value) }
            } catch (e: IllegalArgumentException) {
                main.post { result.error("BAD_ARGUMENTS", e.message, null) }
            } catch (t: Throwable) {
                Log.w(TAG, "${call.method} failed", t)
                main.post { result.error("ENGINE_ERROR", "${t.javaClass.simpleName}: ${t.message}", null) }
            }
        }
    }

    private fun isTracking(): Boolean = WitnessRuntime.serviceRunning

    private fun capabilities(): Map<String, Any?> {
        val caps = SensorProbe.probe(app)
        val mode = WitnessRuntime.engineRef?.plan?.mode ?: EvidenceModeSelector.select(caps, Prefs(app).allowE2WakeLock).mode
        return mapOf(
            "stepCounter" to caps.hasStepCounter,
            "accelerometer" to caps.hasAccelerometer,
            "gyroscope" to caps.hasGyroscope,
            "activityRecognitionGranted" to SensorProbe.activityRecognitionGranted(app),
            "notificationsGranted" to notificationsGranted(),
            "evidenceMode" to mode.name,
            "sdkInt" to Build.VERSION.SDK_INT,
            "model" to (Build.MODEL ?: ""),
        )
    }

    private fun notificationsGranted(): Boolean = try {
        (app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled()
    } catch (_: Throwable) { true }

    /** `{started, reason?}`; reason: PERMISSION_DENIED | NO_STEP_COUNTER | START_FAILED. Reports the truth, not hope. */
    private fun startTracking(): Map<String, Any?> {
        if (WitnessRuntime.serviceRunning) return mapOf("started" to true)
        if (!SensorProbe.activityRecognitionGranted(app)) return mapOf("started" to false, "reason" to "PERMISSION_DENIED")
        val sm = app.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        if (sm.getDefaultSensor(Sensor.TYPE_STEP_COUNTER) == null) return mapOf("started" to false, "reason" to "NO_STEP_COUNTER")
        WitnessRuntime.lastError = null
        try {
            SensorWitnessService.start(app)
        } catch (t: Throwable) { // e.g. ForegroundServiceStartNotAllowedException when the app is not visible
            Log.w(TAG, "service start refused", t)
            return mapOf("started" to false, "reason" to "START_FAILED")
        }
        // Wait (off the main thread) for the service to actually come up or report an error, up to 3 s.
        val deadline = SystemClock.elapsedRealtime() + 3_000
        while (SystemClock.elapsedRealtime() < deadline) {
            if (WitnessRuntime.serviceRunning) return mapOf("started" to true)
            WitnessRuntime.lastError?.let { err ->
                val reason = when {
                    err == "NO_STEP_COUNTER" -> "NO_STEP_COUNTER"
                    err.contains("SecurityException") -> "PERMISSION_DENIED"
                    else -> "START_FAILED"
                }
                return mapOf("started" to false, "reason" to reason)
            }
            Thread.sleep(50)
        }
        return mapOf("started" to false, "reason" to "START_FAILED")
    }

    private fun long(call: MethodCall, key: String): Long =
        (call.argument<Any>(key) as? Number)?.toLong() ?: throw IllegalArgumentException("missing numeric argument '$key'")

    private fun todaySummary(call: MethodCall): Map<String, Any> {
        val start = long(call, "dayStartMs")
        val end = long(call, "dayEndMs")
        if (end <= start) throw IllegalArgumentException("dayEndMs must be > dayStartMs")
        return summaryFor(start, end).toMap()
    }

    private fun summaryFor(startMs: Long, endMs: Long) =
        WitnessRuntime.pipeline(app).let { p ->
            StepSummaryAggregator.aggregate(
                p.buckets(), p.adjustmentsList(), p.pendingBuckets(), p.counterGaps(), startMs, endMs,
                sinceMs = WitnessRuntime.binding(app).sinceMs,
            )
        }

    /** `{bound:true, changed, sinceMs}`: the ledger now belongs to [uid]; older buckets are excluded, not deleted. */
    private fun bindUser(call: MethodCall): Map<String, Any> {
        val uid = call.argument<String>("uid") ?: throw IllegalArgumentException("missing 'uid'")
        return WitnessRuntime.binding(app).bind(uid, System.currentTimeMillis()).toMap()
    }

    private fun bucketsForSync(call: MethodCall): List<Map<String, Any?>> {
        val limit = ((call.argument<Any>("limit") as? Number)?.toInt() ?: 200).coerceIn(1, 200)
        val p = WitnessRuntime.pipeline(app)
        return WitnessRuntime.syncLedger(app)
            .pending(p.buckets(), p.adjustmentsList(), limit, System.currentTimeMillis(), WitnessRuntime.binding(app).sinceMs)
            .map { it.toMap() }
    }

    private fun ackBuckets(call: MethodCall): Map<String, Any> {
        val list = call.argument<List<*>>("startMsList") ?: throw IllegalArgumentException("missing 'startMsList'")
        val starts = list.map { (it as? Number)?.toLong() ?: throw IllegalArgumentException("startMsList must hold numbers") }
        val known = WitnessRuntime.pipeline(app).buckets().mapTo(HashSet()) { it.startMs }
        val n = WitnessRuntime.syncLedger(app).ack(starts, known, System.currentTimeMillis())
        return mapOf("acked" to n)
    }

    private fun liveStatus(): Map<String, Any?> {
        val tracking = isTracking()
        val snap = WitnessRuntime.pipeline(app).snapshot()
        return mapOf(
            "tracking" to tracking,
            "liveLabel" to (if (tracking) snap.live?.label?.name else null),
            "carryMode" to (if (tracking) snap.carryMode.name else null),
            "lastRejection" to snap.lastRejection,
        )
    }

    // ---- EventChannel -------------------------------------------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        lastEmittedTracking = false
        ticker?.cancel(false)
        ticker = io.scheduleWithFixedDelay({ emitEvent() }, 0, 2, TimeUnit.SECONDS)
    }

    override fun onCancel(arguments: Any?) {
        ticker?.cancel(false); ticker = null
        sink = null
    }

    /** Runs on the bridge thread. Emits while tracking, plus one final `tracking:false` event when it stops. */
    private fun emitEvent() {
        try {
            if (sink == null) return
            val tracking = isTracking()
            if (!tracking && !lastEmittedTracking) return
            lastEmittedTracking = tracking
            val (s, e) = todayRange()
            val d = summaryFor(s, e)
            val live = if (tracking) WitnessRuntime.pipeline(app).snapshot().live?.label?.name else null
            val event = mapOf(
                "tracking" to tracking, "raw" to d.raw, "verified" to d.verified, "pending" to d.pending,
                "rejected" to d.rejected, "suspicious" to d.suspicious, "liveLabel" to live,
            )
            main.post { sink?.success(event) }
        } catch (t: Throwable) {
            Log.w(TAG, "event emit failed", t)
        }
    }

    /** Device-local calendar day [00:00, next 00:00) (handles DST/zone because it uses Calendar, not 24 h math). */
    private fun todayRange(): Pair<Long, Long> {
        val c = Calendar.getInstance()
        c.set(Calendar.HOUR_OF_DAY, 0); c.set(Calendar.MINUTE, 0); c.set(Calendar.SECOND, 0); c.set(Calendar.MILLISECOND, 0)
        val start = c.timeInMillis
        c.add(Calendar.DAY_OF_YEAR, 1)
        return start to c.timeInMillis
    }

    companion object {
        const val METHOD_CHANNEL = "edu.thapar.stepup/engine"
        const val EVENT_CHANNEL = "edu.thapar.stepup/engine_events"
        private const val TAG = "StepEnginePlugin"
    }
}
