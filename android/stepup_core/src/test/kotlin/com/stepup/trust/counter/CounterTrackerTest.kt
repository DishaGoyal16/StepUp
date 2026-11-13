package com.stepup.trust.counter

import com.stepup.trust.store.FileCounterStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class CounterTrackerTest {
    @get:Rule val tmp = TemporaryFolder()

    private fun ev(tsMs: Long, cum: Long, boot: Int = 7, deliveredAt: Long = tsMs + 5_000) =
        CounterEvent(sensorTsNs = tsMs * 1_000_000L, tsMs = tsMs, cumulative = cum, bootCount = boot, deliveredAtMs = deliveredAt)

    @Test fun firstEventIsBaselineOnly() {
        val t = CounterTracker(null)
        val r = t.onEvent(ev(1_000, 5_000))
        assertEquals(CounterEventKind.BASELINE_FIRST, r.kind)
        assertNull("baseline must not produce a delta", r.delta)
        assertNull(r.gap)
        assertEquals(5_000L, r.state.lastCumulative)
    }

    @Test fun deltaAfterBaselineUsesSensorTimestampNotDeliveryTime() {
        val t = CounterTracker(null)
        t.onEvent(ev(1_000, 100))
        val r = t.onEvent(ev(tsMs = 12_000, cum = 106, deliveredAt = 40_000))
        assertEquals(CounterEventKind.DELTA, r.kind)
        assertEquals(6, r.delta!!.delta)
        assertEquals("keyed by sensor timestamp", 12_000L, r.delta!!.tsMs)
        assertEquals(40_000L, r.delta!!.deliveredAtMs)
    }

    @Test fun duplicateEventIsNotCreditedTwice() {
        val t = CounterTracker(null)
        t.onEvent(ev(1_000, 100))
        val a = t.onEvent(ev(2_000, 105))
        val b = t.onEvent(ev(2_000, 105)) // exact duplicate
        assertEquals(CounterEventKind.DELTA, a.kind)
        assertEquals(CounterEventKind.DUPLICATE, b.kind)
        assertNull(b.delta)
        // And a later event only credits the NEW steps.
        assertEquals(3, t.onEvent(ev(3_000, 108)).delta!!.delta)
    }

    @Test fun staleOlderEventDoesNotMoveBaselineBackwards() {
        val t = CounterTracker(null)
        t.onEvent(ev(1_000, 100)); t.onEvent(ev(5_000, 110))
        val stale = t.onEvent(ev(3_000, 104))
        assertEquals(CounterEventKind.DUPLICATE, stale.kind)
        assertEquals(110L, t.state!!.lastCumulative)
        assertEquals(2, t.onEvent(ev(6_000, 112)).delta!!.delta)
    }

    @Test fun serviceRestartTurnsMissedStepsIntoDisplayOnlyGap() {
        val store = FileCounterStore(tmp.newFolder())
        val t1 = CounterTracker(store.loadState())
        t1.onEvent(ev(1_000, 100)).also { store.saveState(it.state) }
        t1.onEvent(ev(2_000, 110)).also { store.saveState(it.state) }

        // Service killed; 37 steps happen unobserved; service restarts (new tracker, persisted state).
        val t2 = CounterTracker(store.loadState())
        val first = t2.onEvent(ev(90_000, 147))
        assertEquals(CounterEventKind.BASELINE_AFTER_RESTART, first.kind)
        assertNull("restart event must not be a delta", first.delta)
        assertEquals(37, first.gap!!.steps)
        assertEquals("SERVICE_NOT_LISTENING", first.gap!!.reason)
        // Afterwards normal deltas resume.
        assertEquals(4, t2.onEvent(ev(95_000, 151)).delta!!.delta)
    }

    @Test fun restartWithNoNewStepsIsBaselineWithoutGapAndDoesNotSwallowNextDelta() {
        val store = FileCounterStore(tmp.newFolder())
        val t1 = CounterTracker(null)
        store.saveState(t1.onEvent(ev(1_000, 100)).state)
        val t2 = CounterTracker(store.loadState())
        val re = t2.onEvent(ev(1_000, 100)) // sensor re-delivers its current value on registration
        assertEquals(CounterEventKind.BASELINE_AFTER_RESTART, re.kind)
        assertNull(re.gap)
        assertEquals("first real lump after restart must be credited", 6, t2.onEvent(ev(9_000, 106)).delta!!.delta)
    }

    @Test fun rebootGivesNewBaselineAndNoCreditForTheJump() {
        val t = CounterTracker(null)
        t.onEvent(ev(1_000, 90_000, boot = 7))
        // After reboot the hardware counter restarts from 0; first event reports 12 with a NEW boot count.
        val r = t.onEvent(ev(500_000, 12, boot = 8))
        assertEquals(CounterEventKind.BASELINE_REBOOT, r.kind)
        assertNull(r.delta); assertNull(r.gap)
        assertEquals(5, t.onEvent(ev(510_000, 17, boot = 8)).delta!!.delta)
    }

    @Test fun rebootWithLargerCounterStillNoCredit() {
        val t = CounterTracker(null)
        t.onEvent(ev(1_000, 100, boot = 7))
        val r = t.onEvent(ev(2_000, 5_000, boot = 8)) // bigger number but different boot => baseline, not +4900
        assertEquals(CounterEventKind.BASELINE_REBOOT, r.kind)
        assertNull(r.delta)
    }

    @Test fun counterResetWithoutBootCountChange() {
        val t = CounterTracker(null)
        t.onEvent(ev(1_000, 500)); t.onEvent(ev(2_000, 510))
        val r = t.onEvent(ev(10_000, 3))
        assertEquals(CounterEventKind.BASELINE_COUNTER_RESET, r.kind)
        assertNull(r.delta)
        assertEquals(4, t.onEvent(ev(11_000, 7)).delta!!.delta)
    }

    @Test fun markRegisteredAfterListenerRestartMakesNextEventABaseline() {
        val t = CounterTracker(null)
        t.onEvent(ev(1_000, 100)); t.onEvent(ev(2_000, 105))
        t.markRegistered()
        val r = t.onEvent(ev(30_000, 120))
        assertEquals(CounterEventKind.BASELINE_AFTER_RESTART, r.kind)
        assertEquals(15, r.gap!!.steps)
    }

    @Test fun resetForgetsEverything() {
        val t = CounterTracker(null)
        t.onEvent(ev(1_000, 100))
        t.reset()
        assertNull(t.state)
        assertEquals(CounterEventKind.BASELINE_FIRST, t.onEvent(ev(2_000, 105)).kind)
    }

    @Test fun fileStoreSurvivesRoundTrip() {
        val dir = tmp.newFolder()
        val s = FileCounterStore(dir)
        s.saveState(CounterState(7, 123, 456, 789))
        s.appendDelta(StoredDelta(1_000, 6, 7, 129, 1_000_000_000L, 4_000))
        s.appendGap(GapRecord(2_000, 11, "SERVICE_NOT_LISTENING"))
        val s2 = FileCounterStore(dir)
        assertEquals(CounterState(7, 123, 456, 789), s2.loadState())
        assertEquals(6, s2.loadDeltas().single().delta)
        assertEquals(11, s2.loadGaps().single().steps)
        s2.clear()
        assertNull(FileCounterStore(dir).loadState())
        assertNotNull(s2)
    }

    @Test fun clockMapperUsesSensorTimeAndDetectsWallClockJumps() {
        val m = ClockMapper(maxJumpMs = 2_000)
        // wall=1_000_000, elapsed=10_000 -> offset 990_000; sensor ts = 8 s of uptime
        val a = m.toUtcMs(8_000_000_000L, 1_000_000, 10_000)
        assertEquals(990_000 + 8_000, a)
        // Delivery is 5 s later but the *event* is the same sensor time -> same UTC label.
        val b = m.toUtcMs(8_000_000_000L, 1_005_000, 15_000)
        assertEquals(a, b)
        // User moves the wall clock forward 1 h: offset jump -> ignored, counted.
        val c = m.toUtcMs(20_000_000_000L, 1_005_000 + 3_600_000, 15_000)
        assertEquals(1, m.clockAdjustCount)
        assertEquals(990_000 + 20_000, c)
    }
}
