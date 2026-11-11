package com.islanddevcrew.jovra.data.smoke

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Skeleton smoke test for :data (A01). Each class below comes from a Lane A dependency this module's build file
 * declares because the module is planned to need it; the test fails if one is dropped or stops resolving.
 * Classes are looked up without initialising them, so no Android runtime is needed.
 */
class DataSmokeTest {
    private val planned = listOf(
        "kotlinx.serialization.json.Json",
        "androidx.datastore.preferences.core.Preferences",
        "androidx.work.WorkManager",
        "okhttp3.OkHttpClient",
        "com.google.android.gms.auth.api.identity.AuthorizationClient",
        "kotlinx.coroutines.android.HandlerDispatcher"
    )

    @Test
    fun plannedLaneADependenciesAreOnTheTestClasspath() {
        val missing = planned.filter { name ->
            runCatching { Class.forName(name, false, javaClass.classLoader) }.isFailure
        }
        assertEquals("missing planned classes", emptyList<String>(), missing)
    }
}
