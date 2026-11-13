package com.stepup.trust.witness

import com.stepup.trust.export.Csv
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TimingStatsTest {
    @Test fun measuresRateAndGapsFromSensorTimestamps() {
        val s = StreamTimingStats(gapThresholdMs = 1000.0)
        var t = 0L
        repeat(100) { s.add(t); t += 40_000_000L } // 25 Hz for 4 s
        t += 3_000_000_000L // 3 s gap
        repeat(100) { s.add(t); t += 40_000_000L }
        assertEquals(1L, s.gapCount)
        assertTrue(s.maxGapMs > 2900)
        assertEquals(40.0, s.meanDtMs, 0.5)
        assertTrue("jitter of a perfect clock is ~0", s.jitterMs < 0.5)
        // span ~11.9 s of which ~3.04 s is the gap -> coverage ~0.74
        assertEquals(0.74, s.coverage, 0.02)
    }

    @Test fun ignoresOutOfOrderTimestamps() {
        val s = StreamTimingStats()
        assertTrue(s.add(1_000_000_000L))
        assertTrue(s.add(1_040_000_000L))
        assertFalse(s.add(1_020_000_000L))
        assertEquals(1L, s.outOfOrder)
        assertEquals(2L, s.count)
    }

    @Test fun counterLagAndLumpHistogram() {
        val c = CounterTimingStats()
        c.add(100, 500.0); c.add(106, 2_000.0); c.add(108, 9_000.0)
        assertEquals(3L, c.events)
        assertEquals(9000.0, c.maxLagMs, 0.0)
        assertEquals(6, c.maxDelta)
        assertTrue(c.summary().contains("lumpSizes(2:1,6:1)"))
    }

    @Test fun walkingSessionGateTimesOut() {
        val g = WalkingSessionGate(idleTimeoutMs = 60_000)
        assertFalse(g.shouldHoldWakeLock(0))
        g.onCounterActivity(1_000)
        assertTrue(g.shouldHoldWakeLock(30_000))
        assertFalse(g.shouldHoldWakeLock(62_000))
    }

    @Test fun reportsNotMeasuredInsteadOfInventingValues() {
        val caps = DeviceCapabilities("M", "X", 34, null, null, null, null, null, null, null, null, null)
        val plan = EvidenceModeSelector.select(caps, false)
        val text = DiagnosticsReport.summaryText(caps, plan, null, null, null)
        assertTrue(text.contains("NOT MEASURED"))
        assertTrue(text.contains("ABSENT"))
    }

    @Test fun csvRoundTrip() {
        val line = Csv.row("a,b", "q\"uote", 1.5, Double.NaN, null)
        val parsed = Csv.parse(line + "\n")
        assertEquals(listOf("a,b", "q\"uote", "1.5", "", ""), parsed.single())
    }
}
