package com.islanddevcrew.jovra.media.smoke

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Skeleton smoke test for :media (A01). Each class below comes from a Lane A dependency this module's build file
 * declares because the module is planned to need it; the test fails if one is dropped or stops resolving.
 * Classes are looked up without initialising them, so no Android runtime is needed.
 */
class MediaSmokeTest {
    private val planned = listOf(
        "androidx.camera.core.CameraSelector",
        "androidx.camera.camera2.Camera2Config",
        "androidx.camera.lifecycle.ProcessCameraProvider",
        "androidx.camera.video.Recorder",
        "androidx.media3.exoplayer.ExoPlayer",
        "androidx.media3.transformer.Transformer",
        "androidx.media3.effect.OverlayEffect",
        "androidx.media3.muxer.Muxer",
        "androidx.compose.ui.unit.Dp"
    )

    @Test
    fun plannedLaneADependenciesAreOnTheTestClasspath() {
        val missing = planned.filter { name ->
            runCatching { Class.forName(name, false, javaClass.classLoader) }.isFailure
        }
        assertEquals("missing planned classes", emptyList<String>(), missing)
    }
}
