// :room-protocol — pure JVM JOVRA Room v1 envelopes, roles, invites, freshness, receipts, watch snapshot codec.
// No sockets: only :room-transport touches the network (module-boundary check).
plugins {
    alias(libs.plugins.jovra.jvm.library)
    alias(libs.plugins.kotlin.serialization)
}

dependencies {
    api(project(":core"))
    implementation(libs.kotlinx.serialization.json)

    testImplementation(project(":testing"))
}
