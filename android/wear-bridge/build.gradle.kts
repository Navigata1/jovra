// :wear-bridge — Wearable Data Layer paths and capability names, snapshot and command codecs (types from
// :room-protocol); shared by :app and :wear.
plugins {
    alias(libs.plugins.jovra.android.library)
    alias(libs.plugins.kotlin.serialization)
}

dependencies {
    api(project(":room-protocol"))
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.play.services.wearable)
}
