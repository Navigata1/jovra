plugins {
    `kotlin-dsl`
}

group = "com.islanddevcrew.jovra.buildlogic"

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(17))
    }
}

dependencies {
    // compileOnly: the root build puts the plugins themselves on the classpath (android/build.gradle.kts), so one
    // version of each is resolved for the whole build and KGP 2.4.20 wins over AGP's bundled 2.2.10.
    compileOnly(libs.android.gradle.plugin)
    compileOnly(libs.kotlin.gradle.plugin)
    compileOnly(libs.compose.compiler.gradle.plugin)

    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)
}

tasks.test {
    useJUnitPlatform()
}

gradlePlugin {
    plugins {
        register("jvmLibrary") {
            id = "jovra.jvm.library"
            implementationClass = "com.islanddevcrew.jovra.buildlogic.JvmLibraryConventionPlugin"
        }
        register("androidLibrary") {
            id = "jovra.android.library"
            implementationClass = "com.islanddevcrew.jovra.buildlogic.AndroidLibraryConventionPlugin"
        }
        register("androidCompose") {
            id = "jovra.android.compose"
            implementationClass = "com.islanddevcrew.jovra.buildlogic.AndroidComposeConventionPlugin"
        }
        register("androidApplication") {
            id = "jovra.android.application"
            implementationClass = "com.islanddevcrew.jovra.buildlogic.AndroidApplicationConventionPlugin"
        }
        register("androidTest") {
            id = "jovra.android.test"
            implementationClass = "com.islanddevcrew.jovra.buildlogic.AndroidTestConventionPlugin"
        }
        register("moduleBoundaries") {
            id = "jovra.module-boundaries"
            implementationClass = "com.islanddevcrew.jovra.buildlogic.boundaries.ModuleBoundariesPlugin"
        }
    }
}
