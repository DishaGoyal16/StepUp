package com.stepup.trust.bridge

import com.stepup.trust.Hop
import com.stepup.trust.HopLabel
import com.stepup.trust.ledger.LedgerState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SyncExportMapperTest {
    private val s = 50_000L

    @Test fun hopsSerialiseLabelAndImuStepsInTimeOrder() {
        val hops = listOf(
            Hop(s, HopLabel.WALK, 2.0), Hop(s + 2_000, HopLabel.RUN, 3.5), Hop(s + 4_000, HopLabel.SHAKE, 0.0),
            Hop(s + 6_000, HopLabel.STILL, 0.0), Hop(s + 8_000, HopLabel.UNKNOWN, 0.0),
        )
        val m = SyncExportMapper.toItem(rec(s, 5, 2, LedgerState.PARTIAL, "EXCESS_OVER_IMU", hops), null).toMap()
        @Suppress("UNCHECKED_CAST") val h = m["hops"] as List<Map<String, Any>>
        assertEquals(5, h.size)
        assertEquals(listOf("WALK", "RUN", "SHAKE", "STILL", "UNKNOWN"), h.map { it["label"] })
        assertEquals(listOf(2.0, 3.5, 0.0, 0.0, 0.0), h.map { it["imuSteps"] })
        assertTrue(h.all { it.keys == setOf("label", "imuSteps") })
    }

    @Test fun vehicleLabelAndPartialCoverageAreKept() {
        val hops = listOf(Hop(s, HopLabel.VEHICLE, 0.0), Hop(s + 4_000, HopLabel.WALK, 1.25)) // hops 0 and 2 only
        val item = SyncExportMapper.toItem(rec(s, 3, 0, LedgerState.UNWITNESSED, "NO_IMU_EVIDENCE", hops), null)
        assertEquals(listOf("VEHICLE", "WALK"), item.hops.map { it.label })
        assertEquals(1.25, item.hops[1].imuSteps, 1e-9)
    }

    @Test fun itemCarriesAllContractFields() {
        val m = SyncExportMapper.toItem(rec(s, 12, 12, LedgerState.VERIFIED, null, walkHops(s)), null).toMap()
        assertEquals(
            setOf("startMs", "bootCount", "rawDelta", "credited", "state", "reason", "walkFraction", "evidenceMode",
                "carryMode", "hops", "lateRawAdded", "lateCreditedAdded"),
            m.keys,
        )
        assertEquals(s, m["startMs"]); assertEquals(7, m["bootCount"]); assertEquals(12, m["rawDelta"])
        assertEquals(12, m["credited"]); assertEquals("VERIFIED", m["state"]); assertNull(m["reason"])
        assertEquals("E1", m["evidenceMode"]); assertEquals("HAND", m["carryMode"])
        assertEquals(0, m["lateRawAdded"]); assertEquals(0, m["lateCreditedAdded"])
    }

    @Test fun lateAdjustmentsAreFoldedIntoTotalsAndFlagged() {
        val item = SyncExportMapper.toItem(
            rec(s, 12, 12, LedgerState.VERIFIED, null, walkHops(s)), listOf(adj(s, 3, 3), adj(s, 2, 1)),
        )
        assertEquals(17, item.rawDelta); assertEquals(16, item.credited)
        assertEquals(5, item.lateRawAdded); assertEquals(4, item.lateCreditedAdded)
    }

    @Test fun onlySettledStatesAreSyncable() {
        for (st in listOf(LedgerState.VERIFIED, LedgerState.PARTIAL, LedgerState.REJECTED, LedgerState.UNWITNESSED)) {
            assertTrue(st.name, SyncExportMapper.isSyncable(rec(s, 1, 0, st)))
        }
        assertFalse(SyncExportMapper.isSyncable(rec(s, 1, 0, LedgerState.PENDING)))
        assertFalse(SyncExportMapper.isSyncable(rec(s, 1, 0, LedgerState.GAP)))
    }
}
