package com.islanddevcrew.jovra.testing.smoke

import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * Skeleton smoke test for :testing (A01). The conformance harness reads spec/ fixtures in place through the
 * `jovra.repoRoot` system property that build-logic hands every JVM test task (ADR-0024); this fails if that wiring
 * breaks or the module stops being pure JVM.
 */
class TestingSmokeTest {
    @Test
    fun `the module builds without Android on the classpath`() {
        assertThrows(ClassNotFoundException::class.java) { Class.forName("android.os.Build") }
    }

    @Test
    fun `the repository root points at the shared spec fixtures`() {
        val root = System.getProperty("jovra.repoRoot")
        assertNotNull(root, "build-logic must set the jovra.repoRoot system property")
        assertTrue(File(root, "spec/README.md").isFile, "spec/README.md under $root")
        assertTrue(File(root, "spec/fixtures").isDirectory, "spec/fixtures under $root")
        assertTrue(File(root, "android/settings.gradle.kts").isFile, "the Android build under $root")
    }
}
