package com.stepup.trust.replay

import com.stepup.trust.classify.ClassifierConfig
import java.io.File

/**
 * Offline replay CLI.
 *
 *   gradlew :core:run --args="--dir <recording-dir> [--out <dir>] [--set r0Gait=0.4 --set scoreMargin=3]
 *                             [--sweep churnShakeMin=60,80,120]"
 *
 * `--set`   overrides ClassifierConfig fields (repeatable).
 * `--sweep` re-runs the replay once per value and prints one comparison line per value.
 * Output is ALWAYS labelled REPLAY; it must not be mixed up with live results.
 */
fun main(args: Array<String>) {
    var dir: File? = null
    var out: File? = null
    val sets = linkedMapOf<String, Double>()
    var sweepKey: String? = null
    var sweepValues = emptyList<Double>()
    var i = 0
    while (i < args.size) {
        when (args[i]) {
            "--dir" -> dir = File(args[++i])
            "--out" -> out = File(args[++i])
            "--set" -> { val (k, v) = args[++i].split("=", limit = 2); sets[k] = v.toDouble() }
            "--sweep" -> {
                val (k, v) = args[++i].split("=", limit = 2)
                sweepKey = k; sweepValues = v.split(",").map { it.trim().toDouble() }
            }
            "--help", "-h" -> { println("see KDoc in ReplayMain.kt / TESTING_GUIDE.md"); return }
            else -> { System.err.println("unknown argument ${args[i]}"); return }
        }
        i++
    }
    if (dir == null) { System.err.println("usage: --dir <recording-dir> [--out dir] [--set k=v] [--sweep k=a,b,c]"); return }
    val rec = RawRecording.read(dir)
    println("Loaded recording ${dir.path}: imu=${rec.imu.size} counter=${rec.counter.size} ar=${rec.ar.size} labeledTests=${rec.tests.size}")
    val base = ClassifierConfig().withOverrides(sets)
    if (sweepKey != null) {
        println("SWEEP $sweepKey (REPLAY, not live data)")
        println("%-12s %8s %8s %8s %8s".format(sweepKey, "raw", "verified", "rejected", "unwit"))
        for (v in sweepValues) {
            val r = ReplayRunner.run(rec, base.withOverrides(mapOf(sweepKey!! to v)))
            println("%-12s %8d %8d %8d %8d".format(v.toString(), r.summary.rawAll, r.summary.verifiedSteps, r.summary.rejectedSteps, r.summary.unwitnessedSteps))
            r.tests.forEach { t ->
                println("    test ${t.test.id} ${t.test.scenario.name}: verified=${t.verifiedSteps} raw=${t.rawSteps} retention=${t.retention} leakage=${t.leakage} ratio=${t.creditRatio}")
            }
        }
        return
    }
    val report = ReplayRunner.run(rec, base)
    println(report.toText())
    out?.let { ReplayRunner.writeCsv(report, rec, it); println("Wrote REPLAY CSVs to ${it.path}") }
}
