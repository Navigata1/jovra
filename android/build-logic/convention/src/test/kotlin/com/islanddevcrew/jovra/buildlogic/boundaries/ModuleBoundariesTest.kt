package com.islanddevcrew.jovra.buildlogic.boundaries

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * The module-boundary rules of ADR-0024 and the Android spec ("Module layout"), checked through the one public entry
 * point, [ModuleBoundaries.check]. Expected violations are written out by hand from the spec's four rules.
 */
class ModuleBoundariesTest {

    private fun jvm(path: String, deps: Set<String> = emptySet(), sources: List<SourceText> = emptyList()) =
        ModuleFacts(path, ModuleKind.JVM, deps, emptySet(), sources)

    private fun android(
        path: String,
        deps: Set<String> = emptySet(),
        external: Set<String> = emptySet(),
        sources: List<SourceText> = emptyList(),
    ) = ModuleFacts(path, ModuleKind.ANDROID, deps, external, sources)

    private fun kt(path: String, text: String) = SourceText(path, text)

    private val cleanGraph = listOf(
        jvm(":core"),
        jvm(":studio-core", deps = setOf(":core")),
        jvm(":room-protocol", deps = setOf(":core")),
        jvm(":testing"),
        android(":designsystem", deps = setOf(":core")),
        android(
            ":media",
            deps = setOf(":core"),
            external = setOf("androidx.camera:camera-core", "androidx.media3:media3-exoplayer"),
            sources = listOf(kt("src/main/kotlin/Engine.kt", "import androidx.camera.core.Preview\nimport android.media.MediaCodec")),
        ),
        android(
            ":room-transport",
            deps = setOf(":room-protocol"),
            sources = listOf(kt("src/main/kotlin/Carrier.kt", "import javax.net.ssl.SSLSocket\nimport android.net.nsd.NsdManager")),
        ),
        android(":feature:record", deps = setOf(":core", ":designsystem", ":media")),
        android(":feature:sessions", deps = setOf(":core", ":media")),
        android(":app", deps = setOf(":feature:record", ":feature:sessions", ":room-transport", ":media")),
    )

    @Test
    fun `the planned module graph has no violations`() {
        assertEquals(emptyList<Violation>(), ModuleBoundaries.check(cleanGraph))
    }

    @Test
    fun `a JVM module that depends on an Android module is a violation`() {
        val graph = cleanGraph.map { if (it.path == ":core") jvm(":core", deps = setOf(":designsystem")) else it }
        assertEquals(
            listOf(Violation(Rule.JVM_DEPENDS_ON_ANDROID, ":core", "depends on Android module :designsystem")),
            ModuleBoundaries.check(graph),
        )
    }

    @Test
    fun `a feature module that depends on another feature module is a violation`() {
        val graph = cleanGraph.map {
            if (it.path == ":feature:record") it.copy(projectDependencies = it.projectDependencies + ":feature:sessions") else it
        }
        assertEquals(
            listOf(Violation(Rule.FEATURE_DEPENDS_ON_FEATURE, ":feature:record", "depends on feature module :feature:sessions")),
            ModuleBoundaries.check(graph),
        )
    }

    @Test
    fun `the app may depend on every feature module`() {
        val app = cleanGraph.single { it.path == ":app" }
        assertEquals(emptyList<Violation>(), ModuleBoundaries.check(cleanGraph + app.copy(path = ":wear")))
    }

    @Test
    fun `a socket outside room-transport is a violation`() {
        val graph = cleanGraph.map {
            if (it.path == ":feature:sessions") {
                it.copy(sourceFiles = listOf(kt("src/main/kotlin/Peer.kt", "import java.net.Socket\nval s = Socket()")))
            } else {
                it
            }
        }
        assertEquals(
            listOf(Violation(Rule.NETWORK_OUTSIDE_ROOM_TRANSPORT, ":feature:sessions", "src/main/kotlin/Peer.kt references Socket")),
            ModuleBoundaries.check(graph),
        )
    }

    @Test
    fun `NSD and Wi-Fi managers outside room-transport are violations`() {
        val graph = cleanGraph.map {
            if (it.path == ":app") {
                it.copy(
                    sourceFiles = listOf(
                        kt("src/main/kotlin/A.kt", "val m = context.getSystemService(android.net.nsd.NsdManager::class.java)"),
                        kt("src/main/java/B.java", "import android.net.wifi.WifiManager;"),
                    ),
                )
            } else {
                it
            }
        }
        assertEquals(
            listOf(
                Violation(Rule.NETWORK_OUTSIDE_ROOM_TRANSPORT, ":app", "src/main/java/B.java references WifiManager"),
                Violation(Rule.NETWORK_OUTSIDE_ROOM_TRANSPORT, ":app", "src/main/kotlin/A.kt references NsdManager"),
            ),
            ModuleBoundaries.check(graph),
        )
    }

    @Test
    fun `CameraX outside media is a violation, as a dependency and as a source reference`() {
        val graph = cleanGraph.map {
            if (it.path == ":feature:record") {
                it.copy(
                    externalDependencies = setOf("androidx.camera:camera-compose"),
                    sourceFiles = listOf(kt("src/main/kotlin/Framing.kt", "import androidx.camera.compose.CameraXViewfinder")),
                )
            } else {
                it
            }
        }
        assertEquals(
            listOf(
                Violation(Rule.MEDIA_OUTSIDE_MEDIA, ":feature:record", "declares dependency androidx.camera:camera-compose"),
                Violation(Rule.MEDIA_OUTSIDE_MEDIA, ":feature:record", "src/main/kotlin/Framing.kt references androidx.camera"),
            ),
            ModuleBoundaries.check(graph),
        )
    }

    @Test
    fun `Media3 and MediaCodec outside media are violations`() {
        val graph = cleanGraph + android(
            ":studio:editor",
            external = setOf("androidx.media3:media3-ui-compose"),
            sources = listOf(
                kt("src/main/kotlin/Player.kt", "import androidx.media3.exoplayer.ExoPlayer"),
                kt("src/main/kotlin/Decode.kt", "val codec = android.media.MediaCodec.createDecoderByType(mime)"),
            ),
        )
        assertEquals(
            listOf(
                Violation(Rule.MEDIA_OUTSIDE_MEDIA, ":studio:editor", "declares dependency androidx.media3:media3-ui-compose"),
                Violation(Rule.MEDIA_OUTSIDE_MEDIA, ":studio:editor", "src/main/kotlin/Decode.kt references MediaCodec"),
                Violation(Rule.MEDIA_OUTSIDE_MEDIA, ":studio:editor", "src/main/kotlin/Player.kt references androidx.media3"),
            ),
            ModuleBoundaries.check(graph),
        )
    }

    @Test
    fun `names in comments and string literals are not references`() {
        val graph = cleanGraph + android(
            ":feature:profile",
            sources = listOf(
                kt(
                    "src/main/kotlin/Notes.kt",
                    """
                    // Only :room-transport may open a java.net.Socket or use NsdManager.
                    /* CameraX and androidx.media3 live in :media; MediaCodec too. */
                    val label = "WifiManager is not used here"
                    val raw = ${"\"\"\""}androidx.camera.core${"\"\"\""}
                    """.trimIndent(),
                ),
            ),
        )
        assertEquals(emptyList<Violation>(), ModuleBoundaries.check(graph))
    }

    @Test
    fun `names that merely contain a forbidden word are not references`() {
        val graph = cleanGraph + android(
            ":feature:insights",
            sources = listOf(kt("src/main/kotlin/Ok.kt", "class WebSocketLikeThing\nval mediaCodecLabel = 1\nval socketCount = 2")),
        )
        assertEquals(emptyList<Violation>(), ModuleBoundaries.check(graph))
    }

    @Test
    fun `violations are reported in a stable order across modules`() {
        val graph = listOf(
            jvm(":testing", deps = setOf(":media")),
            jvm(":core", deps = setOf(":designsystem")),
            android(":designsystem"),
            android(":media"),
        )
        assertEquals(
            listOf(
                Violation(Rule.JVM_DEPENDS_ON_ANDROID, ":core", "depends on Android module :designsystem"),
                Violation(Rule.JVM_DEPENDS_ON_ANDROID, ":testing", "depends on Android module :media"),
            ),
            ModuleBoundaries.check(graph),
        )
    }
}
