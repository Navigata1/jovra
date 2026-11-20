package com.islanddevcrew.jovra.feature.insights.smoke

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Skeleton smoke test for :feature:insights (A01). Each class below comes from a Lane A dependency this module's build file
 * declares because the module is planned to need it; the test fails if one is dropped or stops resolving.
 * Classes are looked up without initialising them, so no Android runtime is needed.
 */
class InsightsSmokeTest {
    private val planned = listOf(
        "androidx.compose.material3.ColorScheme",
        "androidx.compose.material3.adaptive.WindowAdaptiveInfo",
        "androidx.navigation3.runtime.NavKey",
        "androidx.lifecycle.ViewModel",
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
