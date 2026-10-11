// :studio:cloud — Studio backend adapters (demo, test, live), off by default (ADR-0014, ADR-0019); the local adapter is the default.
plugins {
    alias(libs.plugins.jovra.android.library)
    alias(libs.plugins.jovra.android.compose)
    alias(libs.plugins.kotlin.serialization)
}

dependencies {
    implementation(project(":core"))
    implementation(project(":studio-core"))
    implementation(project(":designsystem"))
    implementation(project(":data"))
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material3.adaptive)
    implementation(libs.androidx.compose.material3.adaptive.layout)
    implementation(libs.androidx.compose.material3.adaptive.navigation)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.navigation3.runtime)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.okhttp)
    implementation(libs.androidx.credentials)
    implementation(libs.androidx.credentials.play.services.auth)
    implementation(libs.androidx.work.runtime)

    testImplementation(libs.okhttp.mockwebserver)
}
