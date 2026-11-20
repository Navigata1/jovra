// :data — document store on app-specific storage (JSON, atomic writes; ADR-0002), library index rebuild,
// quarantine, migrations, DataStore preferences (never session data), archive queue items as JSON, Drive client.
plugins {
    alias(libs.plugins.jovra.android.library)
    alias(libs.plugins.kotlin.serialization)
}

dependencies {
    api(project(":core"))
    api(project(":studio-core"))
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.androidx.work.runtime)
    implementation(libs.okhttp)
    implementation(libs.play.services.auth)

    testImplementation(libs.okhttp.mockwebserver)
}
