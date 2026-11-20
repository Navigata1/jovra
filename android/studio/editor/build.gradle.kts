// :studio:editor — Studio sync review and cut editing panes (supporting-pane layout).
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
    implementation(project(":media"))
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material3.adaptive)
    implementation(libs.androidx.compose.material3.adaptive.layout)
    implementation(libs.androidx.compose.material3.adaptive.navigation)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.navigation3.runtime)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.androidx.window)
}
