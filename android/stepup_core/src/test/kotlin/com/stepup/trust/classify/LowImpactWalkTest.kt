package com.stepup.trust.classify

import com.stepup.trust.*
import com.stepup.trust.replay.RawRecording
import com.stepup.trust.replay.ReplayRunner
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class LowImpactWalkTest {
    private fun rows(resource: String = "/low-impact-walk.tsv") = javaClass.getResourceAsStream(resource)!!.bufferedReader().readLines().map {
        val p = it.split('\t')
        HopFeatures.deserialize(p.dropLast(2)) to ClassifyContext(p.last().toDouble(), CarryMode.valueOf(p[p.size-2]))
    }
    private fun credit(cfg: ClassifierConfig, resource: String = "/low-impact-walk.tsv", rawCounts: List<Int> = listOf(20,15,13,8)): Int {
        val hops = rows(resource).map { (h,c) -> Hop(h.startMs, HopClassifier(cfg).classify(h,c).label,h.imuSteps) }
        return rawCounts.mapIndexed { i, raw -> BucketVerifier().verify(i*10000L,listOf(CounterDelta(i*10000L,raw)),hops,false)!!.credited }.sum()
    }
    @Test fun recordedWalkImprovesWithoutChangingRawOrImuCaps() {
        for ((h,c) in rows()) println("HOP ${h.startMs}: ${HopClassifier().classify(h,c).trace}")
        val baseline=credit(ClassifierConfig(strideImpactAlternative=false)); val revised=credit(ClassifierConfig())
        println("LOW_IMPACT_WALK baseline=$baseline revised=$revised raw=56 manual=50")
        assertEquals(0,baseline)
        assertTrue("at least 70% of the reported 50 steps retained", revised>=35)
        assertTrue(revised<=56)
    }
    @Test fun recordedPocketWalkPreservesObservedCreditAndCounterCap() {
        val verified = credit(ClassifierConfig(), "/pocket-walk-50.tsv", listOf(9, 12, 13, 10))
        println("POCKET_WALK verified=$verified raw=44 manual=50")
        assertTrue("observed credit $verified", verified in 10..44)
    }
    @Test fun replayPairedWalkAndShakeThroughSettlement() {
        fun replay(resource: String, counts: List<Int>): Int {
            val groups = rows(resource).groupBy { it.first.startMs / 10000 }
            return counts.mapIndexed { i, raw ->
                val start = i * 10000L
                val interval = groups.getValue(i.toLong())
                val verdicts = HopClassifier().classifyInterval(interval, 2000)
                val hops = interval.mapIndexed { j, (h, _) -> Hop(h.startMs, verdicts[j].label, h.imuSteps) }
                BucketVerifier().verify(start, listOf(CounterDelta(start, raw)), hops, false)!!.credited
            }.sum()
        }
        val walk = replay("/normal-walk.tsv", listOf(15, 14, 12, 12))
        val shake = replay("/phone-shake.tsv", listOf(12, 12))
        val pocket = replay("/pocket-walk-50.tsv", listOf(9, 12, 13, 10))
        val followUp = replay("/normal-walk-54.tsv", listOf(20, 12, 12, 10))
        println("FOLLOW_UP verified=$followUp")
        assertTrue(followUp in 45..54)
        println("PAIR walk=$walk shake=$shake pocket=$pocket")
        assertTrue(walk in 40..53)
        assertEquals(0, shake)
        assertTrue(pocket in 10..44)
    }
    @Test fun alternativeNeedsEveryCorroboratingSignal() {
        val (h,c)=rows().first()
        val classifier=HopClassifier()
        assertEquals(HopLabel.WALK,classifier.classify(h,c).label)
        val f=h.features!!
        val invalid=listOf(h.copy(hasGyro=false),h.copy(imuSteps=0.0),h.copy(features=f.copy(purity=0.95)),
            h.copy(features=f.copy(hfFraction=0.7)),h.copy(features=f.copy(subHarmonic=Double.NaN)),
            h.copy(features=f.copy(rotRatio=Double.NaN)))
        for (v in invalid) assertFalse(classifier.classify(v,c).trace.contains("strideCorroborated"))
        assertFalse(classifier.classify(h,c.copy(counterCadenceSpm=Double.NaN)).trace.contains("strideCorroborated"))
        assertFalse(classifier.classify(h,c.copy(counterCadenceSpm=300.0)).trace.contains("strideCorroborated"))
        assertEquals(HopLabel.VEHICLE,classifier.classify(h,c.copy(arVehicle=true)).label)
        assertEquals(HopLabel.SHAKE,classifier.classify(h.copy(features=f.copy(dynRms=10.0,churnDegPerS=200.0)),c).label)
    }
    @Test fun syntheticShakeAndBounceWithCounterAgreementNeverWalkAndVehicleDoesNotRegress() {
        for (seed in 1L..8L) {
            val signals=listOf(
                com.stepup.trust.testsupport.Synth.shake(1000000.0,30.0,seed=seed),
                com.stepup.trust.testsupport.Synth.shake(1000000.0,30.0,freqHz=1.7,strokeAmp=3.0,tiltRad=0.1,seed=seed),
                com.stepup.trust.testsupport.Synth.shake(1000000.0,30.0,freqHz=1.9,strokeAmp=5.0,tiltRad=0.05,seed=seed,mechanical=true),
                com.stepup.trust.testsupport.Synth.legBounce(1000000.0,30.0,seed=seed),
                com.stepup.trust.testsupport.Synth.vehicle(1000000.0,30.0,seed=seed))
            for (signal in signals) {
                val intervals = com.stepup.trust.testsupport.Synth.hops(signal).groupBy { it.startMs / 10000 }
                for (interval in intervals.values) for (carry in CarryMode.values()) {
                    val rows = interval.map { h -> h to ClassifyContext(60 * (h.features?.f0Hz ?: Double.NaN), carry) }
                    val classifier = HopClassifier()
                    val settled = classifier.classifyInterval(rows, 2000)
                    rows.forEachIndexed { i, (h, ctx) ->
                        assertEquals("fake motion upgraded during settlement", classifier.classify(h, ctx).label, settled[i].label)
                    }
                }
            }
            for ((idx,signal) in signals.withIndex()) for(h in com.stepup.trust.testsupport.Synth.hops(signal)) {
                val f=h.features ?: continue
                for(carry in CarryMode.values()) {
                    val v=HopClassifier().classify(h,ClassifyContext(60*f.f0Hz,carry))
                    val old=HopClassifier(ClassifierConfig(strideImpactAlternative=false)).classify(h,ClassifyContext(60*f.f0Hz,carry))
                    val newGait=v.label==HopLabel.WALK || v.label==HopLabel.RUN
                    val oldGait=old.label==HopLabel.WALK || old.label==HopLabel.RUN
                    assertFalse("new fake acceptance seed=$seed signal=$idx carry=$carry ${v.trace}",newGait && !oldGait)
                    if (idx<4) assertFalse("shake/bounce accepted seed=$seed signal=$idx ${v.trace}",newGait)
                }
            }
        }
    }
    @Test fun optionalPrivateRawRecordingAudit() {
        val root=System.getenv("STEPUP_RECORDINGS")?.let(::File) ?: return
        for (dir in root.listFiles()!!.filter { it.isDirectory }.sortedBy { it.name }) {
            val rec=RawRecording.read(dir)
            val before=ReplayRunner.run(rec,ClassifierConfig(strideImpactAlternative=false))
            val after=ReplayRunner.run(rec)
            println("RAW_REPLAY ${dir.name} before=${before.summary.verifiedSteps} after=${after.summary.verifiedSteps} raw=${after.summary.rawAll}")
            for (t in after.tests) if (t.test.scenario.name in setOf("FAST_SHAKE","SLOW_SHAKE","LEG_BOUNCE")) {
                assertEquals("fake leakage ${dir.name} test ${t.test.id}",0,t.verifiedSteps)
            }
        }
    }
}
