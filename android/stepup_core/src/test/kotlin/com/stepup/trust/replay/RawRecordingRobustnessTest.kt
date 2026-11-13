package com.stepup.trust.replay

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Test

/** Regression: a real recording (rec_1794513266682) killed mid-write by a reinstall ended with "...,9.80938,1". */
class RawRecordingRobustnessTest {
    private fun rec(imu: String): RawRecording {
        val d = kotlin.io.path.createTempDirectory("rawrec").toFile()
        File(d, "imu.csv").writeText("sensor,ts_ns,t_ms,x,y,z,delivered_at_ms\n$imu")
        File(d, "counter.csv").writeText("ts_ns,t_ms,cumulative,boot_count,delivered_at_ms\n")
        File(d, "ar.csv").writeText("t_ms,type,confidence\n")
        File(d, "labels.csv").writeText("id,scenario,start_ms,end_ms,ground_truth_steps\n")
        return RawRecording.read(d)
    }

    private val good = "A,1,1794513266706.661,-5.4,3.7,7.2,1794513266730\nA,2,1794513266727.000,-5.5,3.9,6.6,1794513266742\n"

    @Test fun unterminatedTruncatedLastLineIsDropped() {
        val r = rec(good + "A,3,1794514477033.432,-0.06191,0.23958,9.80938,1")
        assertEquals(2, r.imu.size)
    }

    @Test fun truncatedButTerminatedRowWithImplausibleDeliveryTimeIsSkipped() {
        val r = rec(good + "A,3,1794514477033.432,-0.06191,0.23958,9.80938,1\n")
        assertEquals(2, r.imu.size)
    }

    @Test fun malformedRowsAreSkippedNotFatal() {
        val r = rec(good + "garbage\nA,4,notanumber,1,2,3,4\n")
        assertEquals(2, r.imu.size)
    }

    @Test fun cleanFileIsReadCompletely() {
        assertEquals(2, rec(good).imu.size)
    }
}
