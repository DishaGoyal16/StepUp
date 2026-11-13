package edu.thapar.stepup.steps

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorManager
import android.os.Build
import android.provider.Settings
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.stepup.trust.witness.DeviceCapabilities
import com.stepup.trust.witness.SensorInfo

/** Reads what the REAL device exposes (sensors, Play services, permission state). Nothing here is simulated. */
object SensorProbe {

    fun probe(ctx: Context): DeviceCapabilities {
        val sm = ctx.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        fun def(type: Int, wake: Boolean): SensorInfo? = sm.getDefaultSensor(type, wake)?.let { toInfo(it) }

        // getDefaultSensor(type, wakeUp=false) may legally return a wake-up sensor on some devices;
        // only treat a result as the "wake-up" variant when isWakeUpSensor is true.
        val accelWake = def(Sensor.TYPE_ACCELEROMETER, true)?.takeIf { it.isWakeUp }
        val accelAny = def(Sensor.TYPE_ACCELEROMETER, false)
        val gyroWake = def(Sensor.TYPE_GYROSCOPE, true)?.takeIf { it.isWakeUp }
        val gyroAny = def(Sensor.TYPE_GYROSCOPE, false)

        val arAvailable = try {
            GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(ctx) == ConnectionResult.SUCCESS
        } catch (_: Throwable) {
            false
        }
        val arPermission = activityRecognitionGranted(ctx)

        return DeviceCapabilities(
            manufacturer = Build.MANUFACTURER ?: "",
            model = Build.MODEL ?: "",
            sdkInt = Build.VERSION.SDK_INT,
            bootCount = bootCount(ctx),
            stepCounter = def(Sensor.TYPE_STEP_COUNTER, false),
            stepDetector = def(Sensor.TYPE_STEP_DETECTOR, false),
            accelerometer = accelAny?.takeIf { !it.isWakeUp } ?: accelAny,
            accelerometerWakeUp = accelWake,
            gyroscope = gyroAny?.takeIf { !it.isWakeUp } ?: gyroAny,
            gyroscopeWakeUp = gyroWake,
            activityRecognitionAvailable = arAvailable,
            activityRecognitionPermissionGranted = arPermission,
            // The full sensor list was only for the prototype's diagnostics export; not needed in production.
            allSensors = emptyList(),
        )
    }

    /** Runtime-permission state only. Prompting is done from Dart (permission_handler); natively we just report. */
    fun activityRecognitionGranted(ctx: Context): Boolean =
        if (Build.VERSION.SDK_INT >= 29) {
            ctx.checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED
        } else true

    fun bootCount(ctx: Context): Int? = try {
        Settings.Global.getInt(ctx.contentResolver, Settings.Global.BOOT_COUNT)
    } catch (_: Throwable) {
        null
    }

    private fun toInfo(s: Sensor) = SensorInfo(
        name = s.name ?: "",
        vendor = s.vendor ?: "",
        type = s.type,
        typeName = s.stringType ?: "",
        isWakeUp = s.isWakeUpSensor,
        minDelayUs = s.minDelay,
        maxDelayUs = s.maxDelay,
        fifoMaxEventCount = s.fifoMaxEventCount,
        fifoReservedEventCount = s.fifoReservedEventCount,
        resolution = s.resolution,
        maxRange = s.maximumRange,
        reportingMode = s.reportingMode,
        powerMa = s.power,
    )
}
