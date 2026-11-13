package edu.thapar.stepup.steps

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.HandlerThread
import android.os.PowerManager
import android.os.SystemClock
import com.stepup.trust.counter.ClockMapper
import com.stepup.trust.counter.CounterEvent
import com.stepup.trust.witness.ArEvent
import com.stepup.trust.witness.ArType
import com.stepup.trust.witness.DeviceCapabilities
import com.stepup.trust.witness.EvidenceMode
import com.stepup.trust.witness.EvidenceModeSelector
import com.stepup.trust.witness.EvidencePlan
import com.stepup.trust.witness.WalkingSessionGate

/**
 * Registers the real hardware sensors and feeds the pure-Kotlin [com.stepup.trust.witness.WitnessPipeline].
 * Owned by [SensorWitnessService]. Nothing here generates or simulates values: every sample comes from
 * `SensorManager`, every timestamp is the SENSOR timestamp (mapped to UTC), never the delivery time.
 *
 * Ported from the tested v2 prototype; the sensor/bucketing/baseline logic is unchanged. Removed: the prototype's
 * raw IMU recording and its timing-diagnostics counters (neither is reachable from the Flutter app).
 */
class WitnessEngine(private val ctx: Context) {
    private val sm = ctx.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val thread = HandlerThread("witness-sensors").apply { start() }
    private val handler = Handler(thread.looper)
    private val prefs = Prefs(ctx)

    val pipeline = WitnessRuntime.pipeline(ctx)
    private val clock = ClockMapper()
    private val gate = WalkingSessionGate()
    private var wakeLock: PowerManager.WakeLock? = null

    @Volatile var caps: DeviceCapabilities = SensorProbe.probe(ctx); private set
    @Volatile var plan: EvidencePlan = EvidenceModeSelector.select(caps, prefs.allowE2WakeLock); private set

    @Volatile var stepCounterRegistered = false; private set
    @Volatile var accelRegistered = false; private set
    @Volatile var gyroRegistered = false; private set
    @Volatile var sensorClockWarning: String? = null; private set
    @Volatile var wakeLockHeld = false; private set

    private val tickRunnable = object : Runnable {
        override fun run() {
            tick()
            handler.postDelayed(this, 2_000L)
        }
    }

    private fun checkSensorClock(eventTsNs: Long, nowElapsedMs: Long, mayBeOld: Boolean = false) {
        // SensorEvent.timestamp is nanoseconds on the elapsedRealtime clock (AOSP). Verify, don't assume.
        // TYPE_STEP_COUNTER stamps an event with the time of the LAST STEP, so the first event after registration
        // (the baseline) can legitimately be many minutes old: only a negative lag is evidence of a wrong clock there.
        val lagMs = nowElapsedMs - eventTsNs / 1_000_000.0
        if (lagMs < -2_000 || (!mayBeOld && lagMs > 10 * 60_000)) {
            sensorClockWarning = "event.timestamp not on elapsedRealtime clock? lag=${lagMs.toLong()}ms"
        }
    }

    private val counterListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            val nowElapsedMs = SystemClock.elapsedRealtime()
            val nowWallMs = System.currentTimeMillis()
            checkSensorClock(event.timestamp, nowElapsedMs, mayBeOld = true)
            val tsMs = clock.toUtcMs(event.timestamp, nowWallMs, nowElapsedMs)
            val cumulative = event.values[0].toLong()
            val e = CounterEvent(
                sensorTsNs = event.timestamp, tsMs = tsMs, cumulative = cumulative,
                bootCount = SensorProbe.bootCount(ctx) ?: -1, deliveredAtMs = nowWallMs,
            )
            val r = pipeline.onCounterEvent(e)
            if (r.delta != null) gate.onCounterActivity(nowWallMs)
            tick()
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    private fun imuListener(isGyro: Boolean) = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            val nowElapsedMs = SystemClock.elapsedRealtime()
            val nowWallMs = System.currentTimeMillis()
            val tMs = clock.toUtcMsExact(event.timestamp, nowWallMs, nowElapsedMs)
            val x = event.values[0].toDouble(); val y = event.values[1].toDouble(); val z = event.values[2].toDouble()
            if (isGyro) pipeline.onGyro(tMs, x, y, z) else pipeline.onAccel(tMs, x, y, z)
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    private val accelListener = imuListener(false)
    private val gyroListener = imuListener(true)

    /** @return false when TYPE_STEP_COUNTER is missing on this device. */
    fun start(): Boolean {
        caps = SensorProbe.probe(ctx)
        plan = EvidenceModeSelector.select(caps, prefs.allowE2WakeLock)
        pipeline.evidenceMode = plan.mode

        val counter = sm.getDefaultSensor(Sensor.TYPE_STEP_COUNTER) ?: return false
        pipeline.onListenerRegistered() // next counter event is a BASELINE (restart-safe)
        // v2 §L2.2: maxReportLatency 30 s so the sensor hub can batch while the CPU sleeps.
        stepCounterRegistered = sm.registerListener(
            counterListener, counter, SensorManager.SENSOR_DELAY_NORMAL, 30_000_000, handler,
        )

        // v2 §L2.4: 25 Hz IMU. E1 uses the wake-up variants batched for 30 s; E2/E3 use the plain variants.
        // (No HIGH_SAMPLING_RATE_SENSORS permission: 25 Hz is below the 200 Hz rate-limit threshold.)
        val latencyUs = if (plan.mode == EvidenceMode.E1) 30_000_000 else 2_000_000
        if (plan.captureAccel) {
            val a = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER, plan.accelWakeUp)
            if (a != null) accelRegistered = sm.registerListener(accelListener, a, 40_000, latencyUs, handler)
        }
        if (plan.captureGyro) {
            val g = sm.getDefaultSensor(Sensor.TYPE_GYROSCOPE, plan.gyroWakeUp)
            if (g != null) gyroRegistered = sm.registerListener(gyroListener, g, 40_000, latencyUs, handler)
        }
        if (!accelRegistered) {
            // No evidence is possible: every counter step will end up UNWITNESSED (display-only).
            pipeline.evidenceMode = EvidenceMode.E3
        }
        ArClient.register(ctx)
        handler.postDelayed(tickRunnable, 2_000L)
        return true
    }

    /** Called from the AR receiver when AR reports walking/running (opens an E2 walking session). */
    fun onActivityRecognition(e: ArEvent) {
        if (e.type == ArType.WALKING || e.type == ArType.RUNNING || e.type == ArType.ON_FOOT) {
            gate.onActivityRecognitionWalking(System.currentTimeMillis())
        }
    }

    private fun tick() {
        val now = System.currentTimeMillis()
        pipeline.tick(now)
        if (plan.needsWalkingSessionWakeLock) updateWakeLock(now)
    }

    private fun updateWakeLock(now: Long) {
        val want = gate.shouldHoldWakeLock(now)
        if (want) {
            if (wakeLock == null) {
                val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "StepUp:walkingSession")
            }
            wakeLock?.acquire(120_000L) // always with a timeout: a leaked lock cannot drain the battery
            wakeLockHeld = true
        } else if (wakeLockHeld) {
            try { wakeLock?.release() } catch (_: Throwable) { }
            wakeLockHeld = false
        }
    }

    fun flush() {
        try { sm.flush(counterListener) } catch (_: Throwable) { }
        try { sm.flush(accelListener) } catch (_: Throwable) { }
        try { sm.flush(gyroListener) } catch (_: Throwable) { }
    }

    fun stop() {
        handler.removeCallbacks(tickRunnable)
        try { sm.unregisterListener(counterListener) } catch (_: Throwable) { }
        try { sm.unregisterListener(accelListener) } catch (_: Throwable) { }
        try { sm.unregisterListener(gyroListener) } catch (_: Throwable) { }
        ArClient.unregister(ctx)
        if (wakeLockHeld) { try { wakeLock?.release() } catch (_: Throwable) { }; wakeLockHeld = false }
        stepCounterRegistered = false; accelRegistered = false; gyroRegistered = false
        pipeline.tick(System.currentTimeMillis())
        thread.quitSafely()
    }
}
