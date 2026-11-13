package com.stepup.trust.replay

import com.stepup.trust.counter.CounterEvent
import com.stepup.trust.session.LabeledTest
import com.stepup.trust.session.TestScenario
import com.stepup.trust.witness.ArEvent
import com.stepup.trust.witness.ArType
import java.io.BufferedWriter
import java.io.File

/**
 * On-disk format of a RAW sensor recording (debug builds only). One directory per recording:
 *
 *  - `meta.txt`    key=value (device, start time, source=LIVE_RECORDING)
 *  - `imu.csv`     sensor(A|G),ts_ns,t_ms,x,y,z,delivered_at_ms   (t_ms = sensor time mapped to UTC ms)
 *  - `counter.csv` ts_ns,t_ms,cumulative,boot_count,delivered_at_ms
 *  - `ar.csv`      t_ms,type,confidence
 *  - `labels.csv`  id,scenario,start_ms,end_ms,ground_truth_steps
 *
 * Raw IMU is privacy-sensitive and large (~2 MB/min at 50 Hz), which is why recording is debug-only and opt-in.
 */
class RawRecordingWriter(val dir: File) : AutoCloseable {
    private val imu: BufferedWriter
    private val counter: BufferedWriter
    private val ar: BufferedWriter
    private var closed = false

    init {
        dir.mkdirs()
        imu = File(dir, "imu.csv").bufferedWriter().also { it.write("sensor,ts_ns,t_ms,x,y,z,delivered_at_ms\n") }
        counter = File(dir, "counter.csv").bufferedWriter().also { it.write("ts_ns,t_ms,cumulative,boot_count,delivered_at_ms\n") }
        ar = File(dir, "ar.csv").bufferedWriter().also { it.write("t_ms,type,confidence\n") }
    }

    fun writeMeta(vararg kv: Pair<String, String>) {
        File(dir, "meta.txt").writeText(
            ("source=LIVE_RECORDING\n" + kv.joinToString("") { "${it.first}=${it.second}\n" }),
        )
    }

    @Synchronized
    fun imuSample(sensor: Char, tsNs: Long, tMs: Double, x: Double, y: Double, z: Double, deliveredAtMs: Long) {
        if (closed) return
        imu.write("$sensor,$tsNs,${"%.3f".format(java.util.Locale.ROOT, tMs)},${"%.5f".format(java.util.Locale.ROOT, x)},${"%.5f".format(java.util.Locale.ROOT, y)},${"%.5f".format(java.util.Locale.ROOT, z)},$deliveredAtMs\n")
    }

    @Synchronized
    fun counterEvent(e: CounterEvent) {
        if (closed) return
        counter.write("${e.sensorTsNs},${e.tsMs},${e.cumulative},${e.bootCount},${e.deliveredAtMs}\n")
        counter.flush()
    }

    @Synchronized
    fun arEvent(e: ArEvent) {
        if (closed) return
        ar.write("${e.tsMs},${e.type},${e.confidence}\n")
        ar.flush()
    }

    @Synchronized
    fun flush() {
        if (closed) return
        imu.flush(); counter.flush(); ar.flush()
    }

    @Synchronized
    fun writeLabels(tests: List<LabeledTest>) {
        File(dir, "labels.csv").writeText(
            "id,scenario,start_ms,end_ms,ground_truth_steps\n" +
                tests.joinToString("") { "${it.id},${it.scenario.name},${it.startMs},${it.endMs ?: ""},${it.groundTruthSteps ?: ""}\n" },
        )
    }

    @Synchronized
    override fun close() {
        if (closed) return
        closed = true
        imu.close(); counter.close(); ar.close()
    }
}

class RawImuSample(val sensor: Char, val tsNs: Long, val tMs: Double, val x: Double, val y: Double, val z: Double, val deliveredAtMs: Long)

class RawRecording(
    val dir: File,
    val imu: List<RawImuSample>,
    val counter: List<CounterEvent>,
    val ar: List<ArEvent>,
    val tests: List<LabeledTest>,
    val meta: Map<String, String>,
) {
    companion object {
        fun read(dir: File): RawRecording {
            require(dir.isDirectory) { "not a directory: $dir" }
            // A recording written by an app that was killed mid-write (e.g. reinstall, crash) can end with a TRUNCATED
            // last line, e.g. "...,9.80938,1" where delivered_at_ms lost its digits. Such a row used to sort first in
            // replay, jump the timeline to the end and silently drop every real sample. So: drop an unterminated last
            // line, and skip any line that does not parse.
            fun lines(name: String): List<String> {
                val f = File(dir, name).takeIf { it.exists() } ?: return emptyList()
                val text = f.readText()
                val all = text.lines()
                val body = if (text.isNotEmpty() && !text.endsWith("\n")) all.dropLast(1) else all
                return body.drop(1).filter { it.isNotBlank() }
            }
            fun <T> parse(l: List<String>, f: (List<String>) -> T): List<T> = l.mapNotNull {
                try { f(it.split(',')) } catch (_: Exception) { null }
            }
            val imu = parse(lines("imu.csv")) { p ->
                // plausibility: real delivery lag is well under a minute; a wildly different value is a corrupt row
                val s = RawImuSample(p[0][0], p[1].toLong(), p[2].toDouble(), p[3].toDouble(), p[4].toDouble(), p[5].toDouble(), p[6].toLong())
                require(kotlin.math.abs(s.deliveredAtMs - s.tMs) < 120_000.0) { "implausible delivered_at" }
                s
            }
            val counter = parse(lines("counter.csv")) { p ->
                CounterEvent(p[0].toLong(), p[1].toLong(), p[2].toLong(), p[3].toInt(), p[4].toLong())
            }
            val ar = parse(lines("ar.csv")) { p -> ArEvent(p[0].toLong(), ArType.valueOf(p[1]), p[2].toInt()) }
            val tests = lines("labels.csv").map {
                val p = it.split(',')
                LabeledTest(p[0].toInt(), TestScenario.valueOf(p[1]), p[2].toLong(), p[3].toLongOrNull(), p.getOrNull(4)?.toIntOrNull())
            }
            val meta = File(dir, "meta.txt").takeIf { it.exists() }?.readLines()?.mapNotNull {
                val i = it.indexOf('='); if (i > 0) it.substring(0, i) to it.substring(i + 1) else null
            }?.toMap() ?: emptyMap()
            return RawRecording(dir, imu, counter, ar, tests, meta)
        }
    }
}
