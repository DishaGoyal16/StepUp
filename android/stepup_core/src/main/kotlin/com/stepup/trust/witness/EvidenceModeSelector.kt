package com.stepup.trust.witness

/** v2 §L2.4 evidence-capture modes. */
enum class EvidenceMode { E1, E2, E3 }

/**
 * What the Sensor Witness service should register. Produced by [EvidenceModeSelector].
 *
 * @property captureAccel register an accelerometer at all (false only when none exists)
 * @property accelWakeUp use the wake-up variant of the accelerometer
 * @property captureGyro register a gyroscope
 * @property gyroWakeUp use the wake-up variant of the gyroscope
 * @property needsWalkingSessionWakeLock E2: hold a PARTIAL_WAKE_LOCK only during walking sessions
 * @property opportunistic E3 with a non-wake-up accelerometer: capture whatever arrives while the CPU is
 *           awake (screen on etc.). Missing coverage still becomes UNWITNESSED, never guessed.
 */
data class EvidencePlan(
    val mode: EvidenceMode,
    val captureAccel: Boolean,
    val accelWakeUp: Boolean,
    val captureGyro: Boolean,
    val gyroWakeUp: Boolean,
    val needsWalkingSessionWakeLock: Boolean,
    val opportunistic: Boolean,
    val rationale: String,
)

/**
 * Chooses E1 / E2 / E3 from device capabilities (v2 §L2.4).
 *
 * * E1 (preferred): a wake-up accelerometer exists -> batched capture, CPU wakes ~2x/min, no wake lock.
 * * E2: no wake-up accelerometer, but the tester explicitly permitted a walking-session wake lock.
 * * E3: otherwise. Steps without IMU coverage are UNWITNESSED (display-only).
 *
 * Gyroscope policy: in E1 only a *wake-up* gyroscope is used (a non-wake-up gyro would silently vanish with the
 * screen off and make features inconsistent); without one the classifier runs accelerometer-only (stricter
 * thresholds, v2 §6). In E2 a non-wake-up gyro is fine because the wake lock keeps the CPU awake.
 */
object EvidenceModeSelector {
    fun select(caps: DeviceCapabilities, allowE2WakeLock: Boolean): EvidencePlan {
        val wakeAccel = caps.accelerometerWakeUp
        val plainAccel = caps.accelerometer

        if (wakeAccel != null) {
            val gyroWake = caps.gyroscopeWakeUp
            return EvidencePlan(
                mode = EvidenceMode.E1,
                captureAccel = true,
                accelWakeUp = true,
                captureGyro = gyroWake != null,
                gyroWakeUp = gyroWake != null,
                needsWalkingSessionWakeLock = false,
                opportunistic = false,
                rationale = "Wake-up accelerometer present (${wakeAccel.name}); batched capture without a wake lock." +
                    if (gyroWake == null) " No wake-up gyroscope: accelerometer-only features." else "",
            )
        }
        if (plainAccel != null && allowE2WakeLock) {
            return EvidencePlan(
                mode = EvidenceMode.E2,
                captureAccel = true,
                accelWakeUp = false,
                captureGyro = caps.gyroscope != null,
                gyroWakeUp = false,
                needsWalkingSessionWakeLock = true,
                opportunistic = false,
                rationale = "No wake-up accelerometer; E2 permitted by the tester: PARTIAL_WAKE_LOCK during walking sessions only.",
            )
        }
        if (plainAccel != null) {
            return EvidencePlan(
                mode = EvidenceMode.E3,
                captureAccel = true,
                accelWakeUp = false,
                captureGyro = caps.gyroscope != null,
                gyroWakeUp = false,
                needsWalkingSessionWakeLock = false,
                opportunistic = true,
                rationale = "No wake-up accelerometer and E2 not permitted: evidence only while the CPU is awake. " +
                    "Uncovered buckets become UNWITNESSED.",
            )
        }
        return EvidencePlan(
            mode = EvidenceMode.E3,
            captureAccel = false,
            accelWakeUp = false,
            captureGyro = false,
            gyroWakeUp = false,
            needsWalkingSessionWakeLock = false,
            opportunistic = false,
            rationale = "No accelerometer on this device: all counter steps are UNWITNESSED (display-only).",
        )
    }
}
