package com.islanddevcrew.jovra.wearbridge.smoke

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Skeleton smoke test for :wear-bridge (A01). Each class below comes from a Lane A dependency this module's build file
 * declares because the module is planned to need it; the test fails if one is dropped or stops resolving.
 * Classes are looked up without initialising them, so no Android runtime is needed.
 */
class WearBridgeSmokeTest {
    private val planned = listOf(
        "com.google.android.gms.wearable.DataClient",
        "com.google.android.gms.wearable.MessageClient",
        "com.google.android.gms.wearable.CapabilityClient",
        "kotlinx.serialization.json.Json"
    )

    @Test
    fun plannedLaneADependenciesAreOnTheTestClasspath() {
        val missing = planned.filter { name ->
            runCatching { Class.forName(name, false, javaClass.classLoader) }.isFailure
        }
        assertEquals("missing planned classes", emptyList<String>(), missing)
    }
}
