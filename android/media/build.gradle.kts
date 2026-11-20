// :media — the only module that uses CameraX, Media3 or MediaCodec (module-boundary check). It exports the
// composables and flows other modules need: camera preview (media/ui/preview), the player surface (media/ui/video)
// and QR scanner frames (media/ui/scanner), so framing, replay, the Studio player, the director preview and the room
// QR scanner never reference CameraX or Media3 themselves.
plugins {
    alias(libs.plugins.jovra.android.library)
    alias(libs.plugins.jovra.android.compose)
}

dependencies {
    api(project(":core"))
    api(project(":studio-core"))
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)

    implementation(libs.androidx.camera.core)
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.video)
    implementation(libs.androidx.camera.compose)

    implementation(libs.androidx.media3.exoplayer)
    implementation(libs.androidx.media3.ui.compose)
    implementation(libs.androidx.media3.transformer)
    implementation(libs.androidx.media3.effect)
    implementation(libs.androidx.media3.muxer)
    implementation(libs.androidx.media3.inspector.frame)
}
