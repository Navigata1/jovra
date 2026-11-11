package com.islanddevcrew.jovra.wear.smoke

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Skeleton smoke test for :wear (A01). Each class below comes from a Lane A dependency this module's build file
 * declares because the module is planned to need it; the test fails if one is dropped or stops resolving.
 * Classes are looked up without initialising them, so no Android runtime is needed.
 */
class WearSmokeTest {
    private val planned = listOf(
        "androidx.wear.compose.material3.ColorScheme",
        "androidx.wear.compose.foundation.lazy.TransformingLazyColumnState",
        "androidx.wear.tiles.TileService",
        "androidx.wear.protolayout.LayoutElementBuilders",
        "androidx.health.services.client.HealthServicesClient",
        "com.google.android.gms.wearable.DataClient",
        "androidx.activity.ComponentActivity"
    )

    @Test
    fun plannedLaneADependenciesAreOnTheTestClasspath() {
        val missing = planned.filter { name ->
            runCatching { Class.forName(name, false, javaClass.classLoader) }.isFailure
        }
        assertEquals("missing planned classes", emptyList<String>(), missing)
    }
}
