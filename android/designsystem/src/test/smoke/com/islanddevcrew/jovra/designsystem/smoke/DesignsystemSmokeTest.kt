package com.islanddevcrew.jovra.designsystem.smoke

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Skeleton smoke test for :designsystem (A01). Each class below comes from a Lane A dependency this module's build file
 * declares because the module is planned to need it; the test fails if one is dropped or stops resolving.
 * Classes are looked up without initialising them, so no Android runtime is needed.
 */
class DesignsystemSmokeTest {
    private val planned = listOf(
        "androidx.compose.material3.ColorScheme",
        "androidx.compose.ui.unit.Dp",
        "androidx.core.content.ContextCompat"
    )

    @Test
    fun plannedLaneADependenciesAreOnTheTestClasspath() {
        val missing = planned.filter { name ->
            runCatching { Class.forName(name, false, javaClass.classLoader) }.isFailure
        }
        assertEquals("missing planned classes", emptyList<String>(), missing)
    }
}
