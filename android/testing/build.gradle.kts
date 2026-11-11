// :testing — pure JVM test support: repository-root resolver for spec/, canonical JSON comparison, fixture manifest
// walker, fake monotonic clock. Used as testImplementation by the JVM modules.
plugins {
    alias(libs.plugins.jovra.jvm.library)
    alias(libs.plugins.kotlin.serialization)
}

dependencies {
    api(platform(libs.junit.bom))
    api(libs.junit.jupiter)
    implementation(libs.kotlinx.serialization.json)
}
