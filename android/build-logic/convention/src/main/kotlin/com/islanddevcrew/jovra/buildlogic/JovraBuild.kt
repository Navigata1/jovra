package com.islanddevcrew.jovra.buildlogic

import org.gradle.api.Project
import org.gradle.api.artifacts.VersionCatalog
import org.gradle.api.artifacts.VersionCatalogsExtension
import org.gradle.api.tasks.testing.Test
import org.gradle.jvm.toolchain.JavaLanguageVersion
import org.gradle.kotlin.dsl.getByType

/**
 * The one place for SDK levels and the JVM target (spec AD6, ADR-0024). Lane B changes [COMPILE_SDK] to 37 here and
 * the catalog pins in `gradle/libs.versions.toml`; nothing else. Raising [TARGET_SDK] to 37 is gate G-TARGET37, not a
 * version bump: it makes ACCESS_LOCAL_NETWORK mandatory for the room transport (ADR-0027).
 */
object JovraSdk {
    const val COMPILE_SDK = 36
    const val TARGET_SDK = 36
    const val MIN_SDK = 29
    const val WEAR_MIN_SDK = 30
    const val JVM_TARGET = 17

    /** The phone and the watch share one applicationId and signing key (Wearable Data Layer, ADR-0024). */
    const val APPLICATION_ID = "com.islanddevcrew.jovra"
    const val NAMESPACE_ROOT = "com.islanddevcrew.jovra"

    /** The Wear OS app is the one module with a different minSdk. */
    const val WEAR_MODULE = ":wear"
}

internal val Project.libs: VersionCatalog
    get() = extensions.getByType<VersionCatalogsExtension>().named("libs")

internal fun VersionCatalog.lib(alias: String) = findLibrary(alias).orElseThrow {
    IllegalStateException("No library '$alias' in gradle/libs.versions.toml")
}

/** `:feature:record` → `com.islanddevcrew.jovra.feature.record`; `:studio-core` → `...studiocore`. */
internal fun Project.jovraNamespace(): String =
    JovraSdk.NAMESPACE_ROOT + path.split(':').filter { it.isNotEmpty() }
        .joinToString(separator = ".", prefix = ".") { it.replace("-", "") }

internal val JVM_LANGUAGE: JavaLanguageVersion = JavaLanguageVersion.of(JovraSdk.JVM_TARGET)

/**
 * The repository root, handed to tests so `:testing` can read `spec/` in place (ADR-0024 conformance harness).
 * `spec/` is a declared input, so a fixture change re-runs the tests.
 */
internal fun Project.configureRepoRootForTests() {
    val repoRoot = rootProject.layout.projectDirectory.dir("..")
    val spec = repoRoot.dir("spec")
    val rootPath = repoRoot.asFile.canonicalPath
    tasks.withType(Test::class.java).configureEach {
        systemProperty("jovra.repoRoot", rootPath)
        inputs.dir(spec).withPropertyName("jovraSpec").withPathSensitivity(org.gradle.api.tasks.PathSensitivity.RELATIVE)
    }
}

/** Smoke tests sit in `src/test/smoke` (A01 owned area); they compile with the module's unit tests. */
internal const val SMOKE_TEST_DIR = "src/test/smoke"
