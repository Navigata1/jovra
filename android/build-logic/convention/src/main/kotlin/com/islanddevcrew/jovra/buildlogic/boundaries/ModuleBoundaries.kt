package com.islanddevcrew.jovra.buildlogic.boundaries

import java.io.Serializable

/** Whether a module builds with only a JDK (`:core`, `:studio-core`, `:room-protocol`, `:testing`) or needs Android. */
enum class ModuleKind { JVM, ANDROID }

/** One source file of a module: its path relative to the module directory, and its text. */
data class SourceText(val path: String, val text: String)

/** What the check needs to know about one module. Gathered from the Gradle model by [ModuleBoundariesPlugin]. */
data class ModuleFacts(
    val path: String,
    val kind: ModuleKind,
    /** Gradle paths of the project dependencies the module declares, in any configuration. */
    val projectDependencies: Set<String>,
    /** `group:name` of the external dependencies the module declares, in any configuration. */
    val externalDependencies: Set<String>,
    val sourceFiles: List<SourceText>,
) : Serializable

/** The module-dependency rules of ADR-0024 and the Android spec ("Module layout"). */
enum class Rule(val summary: String) {
    JVM_DEPENDS_ON_ANDROID("JVM modules never depend on Android modules"),
    FEATURE_DEPENDS_ON_FEATURE("feature modules never depend on each other"),
    NETWORK_OUTSIDE_ROOM_TRANSPORT("only :room-transport may use sockets, NSD or Wi-Fi"),
    MEDIA_OUTSIDE_MEDIA("only :media may use CameraX, Media3 or MediaCodec"),
}

data class Violation(val rule: Rule, val module: String, val detail: String) : Serializable {
    override fun toString(): String = "$module ${rule.name}: $detail (${rule.summary})"
}

/**
 * The module-boundary check. Pure: it sees only [ModuleFacts], so it is tested without Gradle.
 *
 * Source references are found after comments and string literals are blanked, and only as whole identifiers, so a
 * comment that names `NsdManager` or a class called `WebSocketLikeThing` is not a reference.
 */
object ModuleBoundaries {
    const val ROOM_TRANSPORT = ":room-transport"
    const val MEDIA = ":media"
    private const val FEATURE_PREFIX = ":feature:"

    /** Socket, NSD and Wi-Fi types that only `:room-transport` may reference. */
    private val NETWORK_TYPES = listOf(
        "Socket", "ServerSocket", "SSLSocket", "SSLServerSocket", "DatagramSocket", "MulticastSocket",
        "SocketFactory", "SSLSocketFactory", "NsdManager", "WifiManager",
    )

    /** Package roots and the codec type that only `:media` may reference. */
    private val MEDIA_REFERENCES = listOf("androidx.camera", "androidx.media3", "MediaCodec")

    /** Dependency groups that only `:media` may declare. */
    private val MEDIA_GROUPS = listOf("androidx.camera", "androidx.media3")

    fun check(modules: List<ModuleFacts>): List<Violation> {
        val kinds = modules.associate { it.path to it.kind }
        return modules.sortedBy { it.path }.flatMap { module -> violationsOf(module, kinds) }
    }

    private fun violationsOf(module: ModuleFacts, kinds: Map<String, ModuleKind>): List<Violation> = buildList {
        val deps = module.projectDependencies.filter { it != module.path }.sorted()
        if (module.kind == ModuleKind.JVM) {
            deps.filter { kinds[it] == ModuleKind.ANDROID }
                .forEach { add(Violation(Rule.JVM_DEPENDS_ON_ANDROID, module.path, "depends on Android module $it")) }
        }
        if (module.path.startsWith(FEATURE_PREFIX)) {
            deps.filter { it.startsWith(FEATURE_PREFIX) }
                .forEach { add(Violation(Rule.FEATURE_DEPENDS_ON_FEATURE, module.path, "depends on feature module $it")) }
        }
        val code = module.sourceFiles.sortedBy { it.path }.map { it.path to stripCommentsAndStrings(it.text) }
        if (module.path != ROOM_TRANSPORT) {
            code.forEach { (path, text) ->
                NETWORK_TYPES.filter { containsReference(text, it) }
                    .forEach { add(Violation(Rule.NETWORK_OUTSIDE_ROOM_TRANSPORT, module.path, "$path references $it")) }
            }
        }
        if (module.path != MEDIA) {
            module.externalDependencies.sorted()
                .filter { dep -> MEDIA_GROUPS.any { dep.startsWith("$it:") || dep.startsWith("$it.") } }
                .forEach { add(Violation(Rule.MEDIA_OUTSIDE_MEDIA, module.path, "declares dependency $it")) }
            code.forEach { (path, text) ->
                MEDIA_REFERENCES.filter { containsReference(text, it) }
                    .forEach { add(Violation(Rule.MEDIA_OUTSIDE_MEDIA, module.path, "$path references $it")) }
            }
        }
    }

    /** True when [name] occurs as a whole identifier or package root, not inside a longer identifier. */
    private fun containsReference(code: String, name: String): Boolean =
        referencePatterns.getOrPut(name) { Regex("(?<![\\w$])${Regex.escape(name)}(?![\\w$])") }.containsMatchIn(code)

    private val referencePatterns = java.util.concurrent.ConcurrentHashMap<String, Regex>()

    /**
     * Replaces comments and string/char literals with spaces (keeping newlines), so names inside them are not seen as
     * references. Handles `//`, `/* */`, `"..."`, `"""..."""` and `'.'`; good enough for Kotlin and Java sources.
     */
    internal fun stripCommentsAndStrings(text: String): String {
        val out = StringBuilder(text.length)
        var i = 0
        fun blank(until: Int) {
            for (j in i until until.coerceAtMost(text.length)) out.append(if (text[j] == '\n') '\n' else ' ')
            i = until.coerceAtMost(text.length)
        }
        while (i < text.length) {
            when {
                text.startsWith("//", i) -> blank(text.indexOf('\n', i).let { if (it < 0) text.length else it })
                text.startsWith("/*", i) -> blank(text.indexOf("*/", i + 2).let { if (it < 0) text.length else it + 2 })
                text.startsWith("\"\"\"", i) -> blank(text.indexOf("\"\"\"", i + 3).let { if (it < 0) text.length else it + 3 })
                text[i] == '"' || text[i] == '\'' -> blank(endOfQuoted(text, i))
                else -> out.append(text[i++])
            }
        }
        return out.toString()
    }

    private fun endOfQuoted(text: String, start: Int): Int {
        val quote = text[start]
        var j = start + 1
        while (j < text.length && text[j] != quote && text[j] != '\n') j += if (text[j] == '\\') 2 else 1
        return (j + 1).coerceAtMost(text.length)
    }
}
