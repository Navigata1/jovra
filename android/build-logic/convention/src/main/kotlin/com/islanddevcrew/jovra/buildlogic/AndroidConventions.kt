package com.islanddevcrew.jovra.buildlogic

import com.android.build.api.dsl.ApplicationExtension
import com.android.build.api.dsl.LibraryExtension
import org.gradle.api.JavaVersion
import org.gradle.api.Plugin
import org.gradle.api.Project

/**
 * `jovra.android.library`: an Android library on Lane A SDK levels. Kotlin comes from AGP 9's built-in Kotlin (the
 * KGP version is raised to 2.4.20 by the root build); `org.jetbrains.kotlin.android` is never applied.
 */
class AndroidLibraryConventionPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        with(target) {
            pluginManager.apply("com.android.library")
            extensions.configure(LibraryExtension::class.java) {
                namespace = jovraNamespace()
                compileSdk = JovraSdk.COMPILE_SDK
                defaultConfig.minSdk = JovraSdk.MIN_SDK
                defaultConfig.testInstrumentationRunner = TEST_RUNNER
                testOptions.targetSdk = JovraSdk.TARGET_SDK
                lint.targetSdk = JovraSdk.TARGET_SDK
                compileOptions.sourceCompatibility = JAVA_VERSION
                compileOptions.targetCompatibility = JAVA_VERSION
                sourceSets.getByName("test").kotlin.directories.add(SMOKE_TEST_DIR)
            }
            pluginManager.apply("jovra.android.test")
        }
    }
}

/**
 * `jovra.android.application`: the phone/tablet/foldable app (`:app`) and the Wear OS app (`:wear`). Both use the same
 * applicationId (and, at release, the same signing key) so the Wearable Data Layer connects them (ADR-0024).
 */
class AndroidApplicationConventionPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        with(target) {
            pluginManager.apply("com.android.application")
            val isWear = path == JovraSdk.WEAR_MODULE
            extensions.configure(ApplicationExtension::class.java) {
                namespace = jovraNamespace()
                compileSdk = JovraSdk.COMPILE_SDK
                defaultConfig.applicationId = JovraSdk.APPLICATION_ID
                defaultConfig.minSdk = if (isWear) JovraSdk.WEAR_MIN_SDK else JovraSdk.MIN_SDK
                defaultConfig.targetSdk = JovraSdk.TARGET_SDK
                defaultConfig.versionCode = 1
                defaultConfig.versionName = "0.1.0"
                defaultConfig.testInstrumentationRunner = TEST_RUNNER
                compileOptions.sourceCompatibility = JAVA_VERSION
                compileOptions.targetCompatibility = JAVA_VERSION
                sourceSets.getByName("test").kotlin.directories.add(SMOKE_TEST_DIR)
            }
            pluginManager.apply("jovra.android.test")
        }
    }
}

/**
 * `jovra.android.compose`: Compose on top of an Android library or application. Adds the Compose compiler plugin,
 * the Lane A BOM and the pieces every Compose module uses; Material (phone Material 3 or Wear Material 3) is declared
 * by the module, because the phone and the watch use different libraries.
 */
class AndroidComposeConventionPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        with(target) {
            pluginManager.apply("org.jetbrains.kotlin.plugin.compose")
            pluginManager.withPlugin("com.android.library") {
                extensions.configure(LibraryExtension::class.java) { buildFeatures.compose = true }
            }
            pluginManager.withPlugin("com.android.application") {
                extensions.configure(ApplicationExtension::class.java) { buildFeatures.compose = true }
            }
            val bom = dependencies.platform(libs.lib("androidx-compose-bom"))
            listOf("implementation", "debugImplementation", "testImplementation", "androidTestImplementation")
                .forEach { dependencies.add(it, bom) }
            dependencies.add("implementation", libs.lib("androidx-compose-ui"))
            dependencies.add("implementation", libs.lib("androidx-compose-ui-graphics"))
            dependencies.add("implementation", libs.lib("androidx-compose-foundation"))
            dependencies.add("implementation", libs.lib("androidx-compose-ui-tooling-preview"))
            dependencies.add("debugImplementation", libs.lib("androidx-compose-ui-tooling"))
            dependencies.add("debugImplementation", libs.lib("androidx-compose-ui-test-manifest"))
            dependencies.add("testImplementation", libs.lib("androidx-compose-ui-test-junit4"))
            dependencies.add("testImplementation", libs.lib("roborazzi"))
            dependencies.add("testImplementation", libs.lib("roborazzi-compose"))
            dependencies.add("testImplementation", libs.lib("roborazzi-junit-rule"))
            dependencies.add("androidTestImplementation", libs.lib("androidx-compose-ui-test-junit4"))
        }
    }
}

/**
 * `jovra.android.test`: the Android test stack (ADR-0024). JUnit 4 + Robolectric 4.17 + Turbine for unit tests
 * (Robolectric, Roborazzi and the Compose rules are JUnit 4), AndroidX Test for instrumented tests on JOVRA AVDs.
 * Robolectric needs JDK 21 for SDK 36, so local runs pin SDK 34 per module (gate G-JDK21); CI runs 36 on JDK 21.
 */
class AndroidTestConventionPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        with(target) {
            pluginManager.withPlugin("com.android.library") {
                extensions.configure(LibraryExtension::class.java) { testOptions.unitTests.isIncludeAndroidResources = true }
            }
            pluginManager.withPlugin("com.android.application") {
                extensions.configure(ApplicationExtension::class.java) { testOptions.unitTests.isIncludeAndroidResources = true }
            }
            dependencies.add("testImplementation", libs.lib("junit4"))
            dependencies.add("testImplementation", libs.lib("androidx-test-ext-junit"))
            dependencies.add("testImplementation", libs.lib("robolectric"))
            dependencies.add("testImplementation", libs.lib("turbine"))
            dependencies.add("testImplementation", libs.lib("kotlinx-coroutines-test"))
            dependencies.add("androidTestImplementation", libs.lib("androidx-test-runner"))
            dependencies.add("androidTestImplementation", libs.lib("androidx-test-ext-junit"))
        }
    }
}

private const val TEST_RUNNER = "androidx.test.runner.AndroidJUnitRunner"
private val JAVA_VERSION = JavaVersion.toVersion(JovraSdk.JVM_TARGET)
