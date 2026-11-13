package com.stepup.trust.classify

import com.stepup.trust.dsp.Resampler
import kotlin.math.sqrt

/**
 * Streaming L3 front end: raw accelerometer (+ gyroscope) samples -> 25 Hz absolute grid -> 4 s windows every
 * 2 s -> [HopFeatures]. Live tracking and the offline replay harness use this exact class.
 *
 * Time base: callers pass `tMs` = SENSOR timestamp mapped to UTC ms. Grid sample `k` is at `k * 40 ms`; hop `h`
 * covers grid indices `[h*50, (h+1)*50)` i.e. UTC `[h*2000, (h+1)*2000) ms`, so hops tile 10 s buckets exactly.
 *
 * Missing data is never invented: a gap larger than `maxInterpGapMs` leaves grid samples unwritten (invalid). A
 * hop with too few valid samples is simply not emitted (the bucket's coverage drops and its steps become
 * UNWITNESSED). A hop whose 4 s window contains invalid samples is emitted without features and flagged with an
 * UNKNOWN reason (treated as non-walk downstream).
 *
 * Ring slots carry the absolute grid index that wrote them, so stale data from an earlier lap of the ring can
 * never be mistaken for current evidence.
 */
class ImuHopProcessor(
    private val cfg: ClassifierConfig = ClassifierConfig(),
    private val onHop: (HopFeatures) -> Unit,
) {
    private companion object {
        const val N = 512 // ring size (power of two), > window + hop + lookahead + gyro wait
        const val MASK = (N - 1).toLong()
        const val HOP = ClassifierConfig.HOP_SAMPLES
        const val HOPL = HOP.toLong()
        const val WIN = ClassifierConfig.WINDOW_SAMPLES
        const val GYRO_WAIT_SAMPLES = 100L
    }

    private fun slot(k: Long) = (k and MASK).toInt()

    private val ax = DoubleArray(N); private val ay = DoubleArray(N); private val az = DoubleArray(N)
    private val sSig = DoubleArray(N); private val vecSig = DoubleArray(N)
    private val avSig = DoubleArray(N); private val ahSig = DoubleArray(N)
    private val churnSig = DoubleArray(N)
    private val gux = DoubleArray(N); private val guy = DoubleArray(N); private val guz = DoubleArray(N)
    private val aStamp = LongArray(N) { Long.MIN_VALUE }
    private val gyroMag = DoubleArray(N)
    private val gStamp = LongArray(N) { Long.MIN_VALUE }

    private fun accelValid(k: Long) = aStamp[slot(k)] == k
    private fun gyroValid(k: Long) = gStamp[slot(k)] == k

    private val estimator = GaitStepEstimator(cfg)
    private val stepsPerHop = HashMap<Long, Int>()

    private var gravity = DoubleArray(3)
    private var gravityInit = false
    private val gAlpha = run {
        val dt = ClassifierConfig.GRID_MS / 1000.0
        val rc = 1.0 / (2.0 * Math.PI * cfg.gravityCutoffHz)
        dt / (rc + dt)
    }
    private var prevUx = 0.0; private var prevUy = 0.0; private var prevUz = 0.0
    private var prevUValid = false

    private var firstGridK = Long.MIN_VALUE
    private var lastAccelK = Long.MIN_VALUE
    private var lastGyroK = Long.MIN_VALUE
    private var nextHop = Long.MIN_VALUE

    /** Diagnostics. */
    var accelRawSamples = 0L; private set
    var gyroRawSamples = 0L; private set
    var hopsEmitted = 0L; private set
    var hopsSkippedNoEvidence = 0L; private set

    private val accelResampler = Resampler(
        ClassifierConfig.GRID_MS, 3, cfg.maxInterpGapMs, ::onAccelGrid, ::onAccelGap,
    )
    private val gyroResampler = Resampler(
        ClassifierConfig.GRID_MS, 3, cfg.maxInterpGapMs, ::onGyroGrid, ::onGyroGap,
    )

    fun onAccel(tMs: Double, x: Double, y: Double, z: Double) {
        accelRawSamples++
        accelResampler.push(tMs, doubleArrayOf(x, y, z))
    }

    fun onGyro(tMs: Double, x: Double, y: Double, z: Double) {
        gyroRawSamples++
        gyroResampler.push(tMs, doubleArrayOf(x, y, z))
        tryEmit(false)
    }

    /** Emit the hops that are complete at the current stream position (end of a recording / replay). */
    fun finish() {
        for (step in estimator.flush()) countStep(step)
        tryEmit(true)
    }

    // ---------------------------------------------------------------------------------------------------------

    private fun countStep(k: Long) {
        stepsPerHop.merge(Math.floorDiv(k, HOPL), 1, Int::plus)
    }

    private fun onAccelGap(fromK: Long, toK: Long) {
        if (firstGridK == Long.MIN_VALUE) return
        // Hops that ended before the gap are complete: confirm the estimator's pending peak and emit them now.
        for (step in estimator.flush()) countStep(step)
        while (nextHop != Long.MIN_VALUE && (nextHop + 1) * HOPL <= fromK) {
            emitHop(nextHop)
            nextHop++
        }
        // Hops lying wholly inside the gap have no evidence at all: skip them (counted as skipped).
        val firstAfter = Math.floorDiv(toK, HOPL)
        if (firstAfter > nextHop) {
            hopsSkippedNoEvidence += firstAfter - nextHop
            nextHop = firstAfter
        }
        if (toK - fromK + 1 > 50) gravityInit = false // stale gravity after a long gap
        prevUValid = false
        estimator.reset()
    }

    private fun onAccelGrid(k: Long, v: DoubleArray) {
        val i = slot(k)
        val x = v[0]; val y = v[1]; val z = v[2]
        ax[i] = x; ay[i] = y; az[i] = z
        if (!gravityInit) {
            gravity = doubleArrayOf(x, y, z)
            gravityInit = true
        } else {
            gravity[0] += gAlpha * (x - gravity[0])
            gravity[1] += gAlpha * (y - gravity[1])
            gravity[2] += gAlpha * (z - gravity[2])
        }
        val gN = sqrt(gravity[0] * gravity[0] + gravity[1] * gravity[1] + gravity[2] * gravity[2])
        val aN = sqrt(x * x + y * y + z * z)
        sSig[i] = aN - gN
        val dx = x - gravity[0]; val dy = y - gravity[1]; val dz = z - gravity[2]
        val vec = sqrt(dx * dx + dy * dy + dz * dz)
        vecSig[i] = vec
        val ux = if (gN > 1e-6) gravity[0] / gN else 0.0
        val uy = if (gN > 1e-6) gravity[1] / gN else 0.0
        val uz = if (gN > 1e-6) gravity[2] / gN else 0.0
        gux[i] = ux; guy[i] = uy; guz[i] = uz
        val vert = dx * ux + dy * uy + dz * uz
        avSig[i] = vert
        ahSig[i] = sqrt(maxOf(0.0, vec * vec - vert * vert))
        aStamp[i] = k

        // Gravity-direction churn: angular speed of the direction of a short moving average of raw acceleration.
        var churn = 0.0
        val m = cfg.churnSmoothSamples
        var mx = 0.0; var my = 0.0; var mz = 0.0
        var ok = true
        for (j in 0 until m) {
            val kk = k - j
            if (!accelValid(kk)) { ok = false; break }
            val idx = slot(kk)
            mx += ax[idx]; my += ay[idx]; mz += az[idx]
        }
        if (ok) {
            val mn = sqrt(mx * mx + my * my + mz * mz)
            if (mn > 1e-6) {
                val ex = mx / mn; val ey = my / mn; val ez = mz / mn
                if (prevUValid) {
                    churn = FeatureExtractor.angleDeg(ex, ey, ez, prevUx, prevUy, prevUz) /
                        (ClassifierConfig.GRID_MS / 1000.0)
                }
                prevUx = ex; prevUy = ey; prevUz = ez; prevUValid = true
            }
        } else prevUValid = false
        churnSig[i] = churn

        if (firstGridK == Long.MIN_VALUE) {
            firstGridK = k
            nextHop = Math.floorDiv(k + HOPL - 1, HOPL) // first hop starting at or after the first sample
        }
        lastAccelK = k
        for (step in estimator.push(k, sSig[i])) countStep(step)
        tryEmit(false)
    }

    private fun onGyroGap(fromK: Long, toK: Long) { /* unwritten slots are invalid by construction */ }

    private fun onGyroGrid(k: Long, v: DoubleArray) {
        val i = slot(k)
        gyroMag[i] = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
        gStamp[i] = k
        lastGyroK = k
    }

    // ---------------------------------------------------------------------------------------------------------

    private fun tryEmit(force: Boolean) {
        if (firstGridK == Long.MIN_VALUE) return
        val lookahead = estimator.confirmationLookaheadSamples
        while (true) {
            val h = nextHop
            val endK = (h + 1) * HOPL
            if (force) {
                if (lastAccelK < endK - 1) return
            } else {
                if (lastAccelK < endK + lookahead) return
                // Wait (bounded) for the gyroscope stream to catch up when one is delivering.
                val gyroActive = lastGyroK != Long.MIN_VALUE && lastAccelK - lastGyroK < GYRO_WAIT_SAMPLES
                if (gyroActive && lastGyroK < endK && lastAccelK < endK + lookahead + GYRO_WAIT_SAMPLES) return
            }
            emitHop(h)
            nextHop = h + 1
        }
    }

    private fun emitHop(h: Long) {
        val startK = h * HOPL
        val endK = startK + HOPL
        var validInHop = 0
        for (k in startK until endK) if (accelValid(k)) validInHop++
        val steps = (stepsPerHop.remove(h) ?: 0).toDouble()
        if (stepsPerHop.size > 64) stepsPerHop.keys.removeAll { it < h }
        if (validInHop < cfg.minHopValidFraction * HOP) {
            hopsSkippedNoEvidence++
            return // no evidence for this hop; the verifier's coverage rule handles it
        }
        val winStart = endK - WIN
        var validInWin = 0
        var gyroInWin = 0
        for (k in winStart until endK) {
            if (accelValid(k)) validInWin++
            if (gyroValid(k)) gyroInWin++
        }
        val hopStartMs = h * ClassifierConfig.HOP_MS
        val hasGyro = gyroInWin >= WIN * 0.95
        if (validInWin < WIN) {
            hopsEmitted++
            val reason = if (winStart < firstGridK) "WARMUP" else "WINDOW_GAP"
            onHop(HopFeatures(hopStartMs, steps, null, reason, hasGyro))
            return
        }
        val s = DoubleArray(WIN); val vec = DoubleArray(WIN); val av = DoubleArray(WIN); val ah = DoubleArray(WIN)
        val ch = DoubleArray(WIN)
        val gx = DoubleArray(WIN); val gy = DoubleArray(WIN); val gz = DoubleArray(WIN)
        val gm = if (hasGyro) DoubleArray(WIN) else null
        for (j in 0 until WIN) {
            val idx = slot(winStart + j)
            s[j] = sSig[idx]; vec[j] = vecSig[idx]; av[j] = avSig[idx]; ah[j] = ahSig[idx]
            ch[j] = churnSig[idx]
            gx[j] = gux[idx]; gy[j] = guy[idx]; gz[j] = guz[idx]
            if (gm != null) gm[j] = if (gyroValid(winStart + j)) gyroMag[idx] else 0.0
        }
        val f = FeatureExtractor.extract(WindowInput(s, vec, av, ah, gm, ch, gx, gy, gz), cfg)
        hopsEmitted++
        onHop(HopFeatures(hopStartMs, steps, f, null, hasGyro))
    }
}
