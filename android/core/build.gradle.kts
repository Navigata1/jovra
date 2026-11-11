// :core — pure JVM twin of iOS JovraCore: session model, scoring fold, stats, pct, units, CSV (ADR-0024).
// No Android and no coroutines-android: the required CI job android-core builds it with only a JDK.
plugins {
    alias(libs.plugins.jovra.jvm.library)
    alias(libs.plugins.kotlin.serialization)
}

dependencies {
    implementation(libs.kotlinx.serialization.json)

    testImplementation(project(":testing"))
}
