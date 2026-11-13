package com.stepup.trust.witness

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EvidenceModeSelectorTest {
    private fun sensor(name: String, wake: Boolean, fifo: Int = 100) = SensorInfo(
        name, "v", 1, "t", wake, 20_000, 0, fifo, 0, 0.01f, 78f, 0, 0.1f,
    )

    private fun caps(
        accel: SensorInfo? = null, accelWake: SensorInfo? = null,
        gyro: SensorInfo? = null, gyroWake: SensorInfo? = null,
    ) = DeviceCapabilities(
        "M", "X", 34, null, sensor("sc", false), null, accel, accelWake, gyro, gyroWake, null, null,
    )

    @Test fun e1_whenWakeUpAccelerometerExists() {
        val p = EvidenceModeSelector.select(caps(accel = sensor("a", false), accelWake = sensor("aw", true)), allowE2WakeLock = false)
        assertEquals(EvidenceMode.E1, p.mode)
        assertTrue(p.accelWakeUp)
        assertFalse(p.needsWalkingSessionWakeLock)
    }

    @Test fun e1_usesGyroOnlyIfWakeUp() {
        val noWakeGyro = EvidenceModeSelector.select(
            caps(accelWake = sensor("aw", true), gyro = sensor("g", false)), false,
        )
        assertFalse("non-wake-up gyro must not be used in E1", noWakeGyro.captureGyro)
        val wakeGyro = EvidenceModeSelector.select(
            caps(accelWake = sensor("aw", true), gyro = sensor("g", false), gyroWake = sensor("gw", true)), false,
        )
        assertTrue(wakeGyro.captureGyro); assertTrue(wakeGyro.gyroWakeUp)
    }

    @Test fun e2_onlyWhenPermitted() {
        val c = caps(accel = sensor("a", false), gyro = sensor("g", false))
        val permitted = EvidenceModeSelector.select(c, allowE2WakeLock = true)
        assertEquals(EvidenceMode.E2, permitted.mode)
        assertTrue(permitted.needsWalkingSessionWakeLock)
        val notPermitted = EvidenceModeSelector.select(c, allowE2WakeLock = false)
        assertEquals(EvidenceMode.E3, notPermitted.mode)
        assertTrue(notPermitted.opportunistic)
        assertFalse(notPermitted.needsWalkingSessionWakeLock)
    }

    @Test fun e3_whenNoAccelerometer() {
        val p = EvidenceModeSelector.select(caps(), allowE2WakeLock = true)
        assertEquals(EvidenceMode.E3, p.mode)
        assertFalse(p.captureAccel)
    }

    @Test fun e1_isPreferredOverE2EvenIfPermitted() {
        val p = EvidenceModeSelector.select(caps(accel = sensor("a", false), accelWake = sensor("aw", true)), true)
        assertEquals(EvidenceMode.E1, p.mode)
    }
}
