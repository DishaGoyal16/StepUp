package com.stepup.trust.witness

import com.stepup.trust.export.Csv

/**
 * Spike S1/S2 output. Everything here is *measured on the device that produced it*; when no measurement exists a
 * line says "NOT MEASURED" instead of a value (no fabricated hardware results).
 */
object DiagnosticsReport {

    fun sensorTableCsv(caps: DeviceCapabilities): String {
        val sb = StringBuilder()
        sb.appendLine(
            Csv.row(
                "name", "vendor", "type", "type_name", "wake_up", "min_delay_us", "max_delay_us", "fifo_max",
                "fifo_reserved", "resolution", "max_range", "reporting_mode", "power_ma",
            ),
        )
        for (s in caps.allSensors) {
            sb.appendLine(
                Csv.row(
                    s.name, s.vendor, s.type, s.typeName, s.isWakeUp, s.minDelayUs, s.maxDelayUs,
                    s.fifoMaxEventCount, s.fifoReservedEventCount, s.resolution, s.maxRange, s.reportingMode, s.powerMa,
                ),
            )
        }
        return sb.toString()
    }

    fun summaryText(
        caps: DeviceCapabilities,
        plan: EvidencePlan,
        accel: StreamTimingStats?,
        gyro: StreamTimingStats?,
        counter: CounterTimingStats?,
    ): String {
        val sb = StringBuilder()
        sb.appendLine("Device: ${caps.manufacturer} ${caps.model} (SDK ${caps.sdkInt})")
        fun line(label: String, s: SensorInfo?) = sb.appendLine(
            if (s == null) "$label: ABSENT"
            else "$label: ${s.name} wakeUp=${s.isWakeUp} minDelay=${s.minDelayUs}us fifoMax=${s.fifoMaxEventCount} maxDelay=${s.maxDelayUs}us",
        )
        line("StepCounter", caps.stepCounter)
        line("StepDetector", caps.stepDetector)
        line("Accelerometer", caps.accelerometer)
        line("Accelerometer(wake-up)", caps.accelerometerWakeUp)
        line("Gyroscope", caps.gyroscope)
        line("Gyroscope(wake-up)", caps.gyroscopeWakeUp)
        sb.appendLine("ActivityRecognition: ${caps.activityRecognitionAvailable ?: "not checked"} (permission=${caps.activityRecognitionPermissionGranted ?: "unknown"})")
        sb.appendLine("Evidence plan: ${plan.mode} (accelWake=${plan.accelWakeUp}, gyro=${plan.captureGyro}, wakeLock=${plan.needsWalkingSessionWakeLock}, opportunistic=${plan.opportunistic})")
        sb.appendLine("  because: ${plan.rationale}")
        sb.appendLine(accel?.takeIf { it.count > 0 }?.summary("Accel delivered") ?: "Accel delivered: NOT MEASURED (no samples yet)")
        sb.appendLine(gyro?.takeIf { it.count > 0 }?.summary("Gyro delivered") ?: "Gyro delivered: NOT MEASURED (no samples / absent)")
        sb.appendLine(counter?.takeIf { it.events > 0 }?.summary() ?: "StepCounter timing: NOT MEASURED (no events yet)")
        return sb.toString()
    }
}
