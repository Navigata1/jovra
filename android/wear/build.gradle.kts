// :wear — the Wear OS companion (watch spec): five surfaces, optional tiles, Data Layer listener. Same
// applicationId as :app so the Wearable Data Layer connects them; minSdk 30 comes from build-logic (JovraSdk).
plugins {
    alias(libs.plugins.jovra.android.application)
    alias(libs.plugins.jovra.android.compose)
    alias(libs.plugins.kotlin.serialization)
}

dependencies {
    implementation(project(":core"))
    implementation(project(":room-protocol"))
    implementation(project(":wear-bridge"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.core.splashscreen)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.wear.compose.material3)
    implementation(libs.androidx.wear.compose.foundation)
    implementation(libs.androidx.wear.compose.navigation)
    implementation(libs.androidx.wear.tiles)
    implementation(libs.androidx.wear.protolayout)
    implementation(libs.androidx.health.services.client)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.play.services.wearable)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)
}
