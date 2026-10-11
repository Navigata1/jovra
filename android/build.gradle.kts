// Root build: puts each plugin on the classpath once (so KGP 2.4.20 wins over AGP 9's bundled 2.2.10 and every module
// sees one version), and registers the module-boundary check (`checkModuleBoundaries`, also run by `check`).
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.jovra.module.boundaries)
}
