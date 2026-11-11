// :feature:profile — Profile destination: preferences, equipment, archive (Drive), data export and erase.
// Feature modules never depend on each other (module-boundary check); :app wires them.
plugins {
    alias(libs.plugins.jovra.android.library)
    alias(libs.plugins.jovra.android.compose)
    alias(libs.plugins.kotlin.serialization)
}

dependencies {
    implementation(project(":core"))
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
}
