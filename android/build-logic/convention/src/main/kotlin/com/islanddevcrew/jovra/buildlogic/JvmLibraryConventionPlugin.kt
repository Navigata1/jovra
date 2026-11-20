package com.islanddevcrew.jovra.buildlogic

import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.plugins.JavaPluginExtension
import org.gradle.api.tasks.SourceSetContainer
import org.gradle.api.tasks.testing.Test
import org.jetbrains.kotlin.gradle.dsl.KotlinJvmProjectExtension

/**
 * `jovra.jvm.library`: pure Kotlin/JVM, no Android (`:core`, `:studio-core`, `:room-protocol`, `:testing`).
 * Builds and tests on a plain JDK 17, which is what the required `android-core` CI job relies on.
 * Tests run on JUnit Jupiter (JUnit 6), with the repository root handed to them for the in-place spec fixtures.
 */
class JvmLibraryConventionPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        with(target) {
            pluginManager.apply("org.jetbrains.kotlin.jvm")
            extensions.configure(JavaPluginExtension::class.java) { toolchain.languageVersion.set(JVM_LANGUAGE) }
            extensions.configure(KotlinJvmProjectExtension::class.java) { jvmToolchain(JovraSdk.JVM_TARGET) }
            extensions.configure(SourceSetContainer::class.java) {
                named("test") { java.srcDir(SMOKE_TEST_DIR) }
            }
            dependencies.add("testImplementation", dependencies.platform(libs.lib("junit-bom")))
            dependencies.add("testImplementation", libs.lib("junit-jupiter"))
            dependencies.add("testRuntimeOnly", libs.lib("junit-platform-launcher"))
            tasks.withType(Test::class.java).configureEach { useJUnitPlatform() }
            configureRepoRootForTests()
        }
    }
}
