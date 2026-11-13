package com.stepup.trust.witness

/**
 * Static description of one Android sensor, copied from `android.hardware.Sensor` by the app layer.
 * Kept Android-free so the evidence-mode decision (spike S1) is unit-testable.
 */
data class SensorInfo(
    val name: String,
    val vendor: String,
    val type: Int,
    val typeName: String,
    val isWakeUp: Boolean,
    /** Minimum delay between events in microseconds (0 for on-change sensors). */
    val minDelayUs: Int,
    /** Maximum delay in microseconds (0 if unknown/not reported). */
    val maxDelayUs: Int,
    /** Max number of events the hardware FIFO can hold (0 = no batching support). */
    val fifoMaxEventCount: Int,
    val fifoReservedEventCount: Int,
    val resolution: Float,
    val maxRange: Float,
    /** android.hardware.Sensor.REPORTING_MODE_*: 0 continuous, 1 on-change, 2 one-shot, 3 special. */
    val reportingMode: Int,
    val powerMa: Float,
) {
    /** True when the hardware can batch events (needed for the E1 low-power capture). */
    val supportsBatching: Boolean get() = fifoMaxEventCount > 0
}

/** The sensors StepUp cares about, as discovered on this device. `null` = not present. */
data class DeviceCapabilities(
    val manufacturer: String,
    val model: String,
    val sdkInt: Int,
    val bootCount: Int?,
    val stepCounter: SensorInfo?,
    val stepDetector: SensorInfo?,
    val accelerometer: SensorInfo?,
    val accelerometerWakeUp: SensorInfo?,
    val gyroscope: SensorInfo?,
    val gyroscopeWakeUp: SensorInfo?,
    /** Google Play services present AND Activity Recognition API usable. `null` = not checked yet. */
    val activityRecognitionAvailable: Boolean?,
    val activityRecognitionPermissionGranted: Boolean?,
    /** Every sensor reported by the platform, for the S1 diagnostics export. */
    val allSensors: List<SensorInfo> = emptyList(),
) {
    val hasStepCounter: Boolean get() = stepCounter != null
    val hasAccelerometer: Boolean get() = accelerometer != null || accelerometerWakeUp != null
    val hasGyroscope: Boolean get() = gyroscope != null || gyroscopeWakeUp != null
}
