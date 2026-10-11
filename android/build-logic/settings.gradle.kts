// Convention plugins for the JOVRA Android build (ADR-0024). SDK levels, the Kotlin/JVM toolchain, Compose setup,
// test configuration and the module-boundary check live here, in one place.
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    versionCatalogs {
        create("libs") {
            from(files("../gradle/libs.versions.toml"))
        }
    }
}

rootProject.name = "build-logic"
include(":convention")
