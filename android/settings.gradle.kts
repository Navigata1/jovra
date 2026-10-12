// JOVRA Android: one Gradle build (ADR-0024). Run from the repository root with `./gradlew -p android <tasks>` or
// from this directory. JAVA_HOME must point at a JDK 17 (docs/DEVELOPING.md, Android section).
pluginManagement {
    includeBuild("build-logic")
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "jovra-android"

// Pure JVM (no Android): testable with only a JDK; the required CI job `android-core` runs these.
include(":core", ":studio-core", ":room-protocol", ":testing")

// Android libraries. The multi-phone protocol modules are :room-protocol and :room-transport, never a bare "room"
// module: in an Android repository that name reads as the androidx database library, which ADR-0002 rules out.
include(":designsystem", ":data", ":media", ":room-transport", ":wear-bridge")
include(":feature:home", ":feature:sessions", ":feature:record", ":feature:insights", ":feature:profile")
include(":studio:build-match", ":studio:films", ":studio:editor", ":studio:cloud")

// Applications: phone/tablet/foldable and the Wear OS companion (same applicationId).
include(":app", ":wear")
