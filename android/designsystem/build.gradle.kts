// :designsystem — Material 3 theme with JOVRA colour roles (light, dark, high contrast), type scale, 48 dp
// components, ProvenanceBadge, StatusPill, StateCard, court diagrams and charts with semantics.
plugins {
    alias(libs.plugins.jovra.android.library)
    alias(libs.plugins.jovra.android.compose)
}

dependencies {
    api(project(":core"))
    api(libs.androidx.compose.material3)
    implementation(libs.androidx.core.ktx)
}
