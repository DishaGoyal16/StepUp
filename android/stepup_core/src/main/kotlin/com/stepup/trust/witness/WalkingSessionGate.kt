package com.stepup.trust.witness

/**
 * E2 policy (v2 §L2.4): a PARTIAL_WAKE_LOCK may be held only during *walking sessions*, started by an Activity
 * Recognition WALKING/RUNNING signal or by counter activity observed while the CPU was awake, and ended after
 * [idleTimeoutMs] without either signal. This class only decides; the service acquires/releases the lock.
 */
class WalkingSessionGate(private val idleTimeoutMs: Long = 60_000L) {
    private var lastActivityMs: Long = Long.MIN_VALUE

    fun onCounterActivity(nowMs: Long) { lastActivityMs = nowMs }
    fun onActivityRecognitionWalking(nowMs: Long) { lastActivityMs = nowMs }

    fun shouldHoldWakeLock(nowMs: Long): Boolean =
        lastActivityMs != Long.MIN_VALUE && nowMs - lastActivityMs <= idleTimeoutMs

    fun reset() { lastActivityMs = Long.MIN_VALUE }
}
