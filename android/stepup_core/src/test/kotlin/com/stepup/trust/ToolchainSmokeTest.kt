package com.stepup.trust

import org.junit.Assert.assertEquals
import org.junit.Test

class ToolchainSmokeTest {
    @Test
    fun toolchainRunsTests() {
        assertEquals("StepUp_AntiFraud_Architecture_v2", ProjectInfo.ARCHITECTURE)
    }
}
