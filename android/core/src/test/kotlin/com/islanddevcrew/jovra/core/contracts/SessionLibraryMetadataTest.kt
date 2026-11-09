package com.islanddevcrew.jovra.core.contracts

import com.islanddevcrew.jovra.core.json.CanonicalJson
import java.nio.file.Path
import kotlin.io.path.readBytes
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.DynamicTest.dynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory

class SessionLibraryMetadataTest {
    @TestFactory
    fun `three real session versions expose typed library metadata`(): List<DynamicTest> {
        val root = Path.of(checkNotNull(System.getProperty("jovra.repoRoot"))).resolve("spec/fixtures")
        val fixtures = listOf(
            Fixture("sample/jon-vs-alex.session.json", "1.0.0", "b75c57d3-04df-5b4d-b969-32ed5cbfd97a",
                "Jon vs Alex", "Alex", 3_240_000, false, "localOnly", "none"),
            Fixture("records/session.all-fields.json", "1.1.0", "ex-session-all-fields",
                "Contract example: every 1.1 field", "Mia", 600_000, true, "backedUp", "onDevice"),
            Fixture("records/session.order-overrides.json", "1.2.0", "sample-reviewed-order",
                "Sample reviewed serving order", "Alex", 3_240_000, false, "localOnly", "none"),
        )
        return fixtures.map { fixture ->
            dynamicTest(fixture.path) {
                val bytes = root.resolve(fixture.path).readBytes()
                val metadata = SessionLibraryMetadata.decodeJson(bytes, bytes.size)
                assertEquals(fixture.version, metadata.schemaVersion)
                assertEquals(OpaqueId(fixture.id), metadata.id)
                assertEquals(fixture.title, metadata.title)
                assertEquals(SessionLibraryMetadata.Kind.MATCH, metadata.sessionKind)
                assertEquals(listOf("Jon", fixture.otherPlayer), metadata.players.map { it.displayName })
                assertEquals(true, metadata.sample?.synthetic)
                assertEquals(fixture.durationMs, metadata.recording.durationMs)
                assertEquals(fixture.mediaAvailable, metadata.recording.mediaAvailable)
                assertEquals(fixture.archive, metadata.storedArchiveState.wireName)
                assertEquals(fixture.originals, metadata.storedOriginals.wireName)
            }
        }
    }


    @Test
    fun `duration retains a raw nonnegative signed 64 bit integer or absence`() {
        assertEquals(744L, decode(raw()).recording.durationMs)
        val precise = raw().replace("\"durationMs\":744", "\"durationMs\":9007199254740993")
        assertEquals(9_007_199_254_740_993L, decode(precise).recording.durationMs)
        assertNull(decode(raw().replace(",\"durationMs\":744", "")).recording.durationMs)
        for (token in listOf("744.0", "744e0", "\"744\"", "true", "null", "-1", "9223372036854775808")) {
            assertRefused(raw().replace("\"durationMs\":744", "\"durationMs\":$token"))
        }
    }

    @TestFactory
    fun `repeated and escaped duplicate keys are refused before object decoding`(): List<DynamicTest> = listOf(
        "root" to raw(extra = ""","title":"Second title""""),
        "root escaped" to raw(extra = ""","\u0074itle":"Second title""""),
        "player escaped" to raw().replace("\"isSelf\":false", """"isSelf":false,"\u0069sSelf":true"""),
        "recording" to raw().replace("\"durationMs\":744", "\"durationMs\":744,\"durationMs\":744"),
        "opaque section" to raw(extra = ""","analysis":{"state":1,"\u0073tate":2}"""),
    ).map { (name, input) -> dynamicTest(name) { assertRefused(input) } }

    @Test
    fun `selected fields reject unknown missing invalid and null shapes`() {
        for (field in listOf("schemaVersion", "kind", "id", "sport", "createdAt", "updatedAt", "title", "sessionKind",
                             "players", "recording", "storage", "archive")) {
            val obj = Json.parseToJsonElement(raw()).jsonObject
            assertRefused(JsonObject(obj - field).toString())
        }
        for (input in listOf(
            raw(extra = ""","unknown":0"""), raw().replace("\"id\":\"p1\"", "\"id\":\"p1\",\"unknown\":0"),
            raw().replace("\"mode\":\"none\"", "\"mode\":\"none\",\"unknown\":0"),
            raw().replace("\"state\":\"localOnly\"", "\"state\":null"), raw().replace("\"sport\":\"tennis\"", "\"sport\":\"pickleball\""),
            raw().replace("\"mediaAvailable\":false", "\"mediaAvailable\":\"false\""),
            raw().replace("\"includeInDeviceBackup\":false", "\"includeInDeviceBackup\":0"),
            raw().replace("\"segments\":[]", "\"segments\":null"), raw().replace("\"mode\":\"none\"", "\"mode\":\"mystery\""),
            raw(kind = "match"), raw(extra = ""","sample":null"""), raw().dropLast(1) + ",}", raw() + " []",
        )) assertRefused(input)
    }

    @Test
    fun `version and sample metadata preserve the projected v1 field conditions`() {
        assertNull(decode(raw()).sample)
        assertEquals("1.2.7", decode(raw(version = "1.2.7")).schemaVersion)
        for (version in listOf("1.3.0", "2.0.0", "1.02.0", "1.2.0\n")) assertRefused(raw(version = version))
        val withIds = ""","sample":{"label":"Sample","synthetic":false,"generator":"Fixture","mediaIds":["sample.a","sample.b"]}"""
        val projected = decode(raw(extra = withIds)).sample
        assertEquals(false, projected?.synthetic)
        assertEquals(listOf(OpaqueId("sample.a"), OpaqueId("sample.b")), projected?.mediaIds)
        assertRefused(raw(version = "1.0.0", extra = withIds))
        assertRefused(raw(extra = withIds.replace("sample.b", "sample.a")))
        assertRefused(raw(extra = withIds.replace("\"sample.a\",\"sample.b\"", "")))
        assertRefused(raw(extra = withIds.replace("\"Sample\"", "\"Demo\"")))
        val waiting = raw(version = "1.0.0").replace("localOnly", "waitingForWiFi")
        assertRefused(waiting)
        assertEquals(SessionLibraryMetadata.ArchiveState.WAITING_FOR_WIFI,
            decode(waiting.replace("1.0.0", "1.1.0")).storedArchiveState)
    }

    @Test
    fun `opaque known sections do not grant document validity or change selected values`() {
        val a = decode(raw())
        val b = decode(raw(extra = ""","analysis":{"notASchemaField":["opaque"]},"marks":[17],"notes":{}"""))
        assertEquals(a.id, b.id)
        assertEquals(a.players, b.players)
        assertEquals(a.recording, b.recording)
        assertEquals(a.storedArchiveState, b.storedArchiveState)
    }

    @Test
    fun `metadata keeps session and player ID spelling and scalar limits`() {
        val title = "🎾".repeat(120)
        assertEquals(title, decode(raw(id = "session:A-1", title = title)).title)
        assertEquals(OpaqueId("session:A-1"), decode(raw(id = "session:A-1")).id)
        assertRefused(raw(id = "session:A-1\n"))
        assertRefused(raw().replace("\"id\":\"p1\"", """"id":"p1\n""""))
        assertRefused(raw(title = "$title🎾"))
        assertRefused(raw(title = ""))
        assertRefused(raw().replace("\"Fixture session\"", """"\uD800""""))
        assertRefused(raw().replace("2026-10-07T18:00:00Z", "2026-10-07T18:00:00+00:00"))
        assertRefused(raw(players = "[]"))
        assertRefused(raw(players = List(5) { player }.joinToString(prefix = "[", postfix = "]")))
    }

    @Test
    fun `byte and depth budgets also cover opaque content`() {
        val bytes = raw(title = "🎾").encodeToByteArray()
        assertEquals("🎾", SessionLibraryMetadata.decodeJson(bytes, bytes.size).title)
        val failure = assertThrows(CanonicalJson.LimitExceeded::class.java) {
            SessionLibraryMetadata.decodeJson(bytes, bytes.size - 1)
        }
        assertEquals(CanonicalJson.Limit.INPUT, failure.limit)
        val invalid = byteArrayOf(0xc0.toByte(), 0xaf.toByte())
        assertThrows(CanonicalJson.LimitExceeded::class.java) { SessionLibraryMetadata.decodeJson(invalid, 1) }
        assertThrows(IllegalArgumentException::class.java) { SessionLibraryMetadata.decodeJson(invalid, invalid.size) }
        fun nested(count: Int) = ",\"analysis\":" + "[".repeat(count) + "0" + "]".repeat(count)
        assertEquals("Fixture session", decode(raw(extra = nested(14))).title)
        assertRefused(raw(extra = nested(15)))
    }

    private val player = """{"id":"p1","displayName":"Player 1","handedness":"right","backhand":"unknown","isSelf":false}"""

    private fun raw(
        version: String = "1.2.0", id: String = "session-1", title: String = "Fixture session",
        kind: String = "lesson", players: String = "[$player]", extra: String = "",
    ) = """{"schemaVersion":${quote(version)},"kind":"jovra.session","id":${quote(id)},"sport":"tennis",
        "createdAt":"2026-10-07T18:00:00Z","updatedAt":"2026-10-07T18:00:00Z","title":${quote(title)},
        "sessionKind":"$kind","players":$players,"recording":{"mode":"none","segments":[],"gaps":[],"microphone":"notRequested","mediaAvailable":false,"durationMs":744},
        "storage":{"originals":"none","includeInDeviceBackup":false},"archive":{"state":"localOnly"}$extra}"""

    private fun quote(value: String): String = Json.encodeToString(value)

    private fun decode(raw: String): SessionLibraryMetadata {
        val bytes = raw.encodeToByteArray()
        return SessionLibraryMetadata.decodeJson(bytes, bytes.size)
    }

    private fun assertRefused(raw: String) {
        assertThrows(IllegalArgumentException::class.java, { decode(raw) }, raw)
    }

    private data class Fixture(
        val path: String, val version: String, val id: String, val title: String, val otherPlayer: String,
        val durationMs: Long, val mediaAvailable: Boolean, val archive: String, val originals: String,
    )
}
