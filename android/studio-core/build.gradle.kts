// :studio-core — pure JVM twin of the Studio reference: EDL, sync fit, job state, quote and reservation ledger.
plugins {
    alias(libs.plugins.jovra.jvm.library)
    alias(libs.plugins.kotlin.serialization)
}

dependencies {
    api(project(":core"))
    implementation(libs.kotlinx.serialization.json)

    testImplementation(project(":testing"))
}
