package com.islanddevcrew.jovra.app.smoke

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Skeleton smoke test for :app (A01). Each class below comes from a Lane A dependency this module's build file
 * declares because the module is planned to need it; the test fails if one is dropped or stops resolving.
 * Classes are looked up without initialising them, so no Android runtime is needed.
 */
class AppSmokeTest {
    private val planned = listOf(
        "androidx.activity.ComponentActivity",
        "androidx.core.splashscreen.SplashScreen",
        "androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType",
        "androidx.navigation3.runtime.NavKey",
        "androidx.lifecycle.ProcessLifecycleOwner",
        "androidx.window.layout.WindowInfoTracker",
        "androidx.window.testing.layout.WindowLayoutInfoPublisherRule"
    )

    @Test
    fun plannedLaneADependenciesAreOnTheTestClasspath() {
        val missing = planned.filter { name ->
            runCatching { Class.forName(name, false, javaClass.classLoader) }.isFailure
        }
        assertEquals("missing planned classes", emptyList<String>(), missing)
    }
}
