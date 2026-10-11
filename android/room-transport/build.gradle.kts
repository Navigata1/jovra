// :room-transport — the only module that touches sockets, NSD or Wi-Fi (module-boundary check): NSD
// advertise/browse, TLS 1.3 socket carrier with SPKI pin, QR payload codec, LocalOnlyHotspot host. Platform APIs only.
plugins {
    alias(libs.plugins.jovra.android.library)
    alias(libs.plugins.kotlin.serialization)
}

dependencies {
    api(project(":room-protocol"))
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.androidx.core.ktx)
}
