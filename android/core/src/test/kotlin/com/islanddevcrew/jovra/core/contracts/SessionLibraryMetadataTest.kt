package com.islanddevcrew.jovra.core.contracts

import java.nio.file.Path
import kotlin.io.path.readBytes
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.DynamicTest.dynamicTest
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

    private data class Fixture(
        val path: String, val version: String, val id: String, val title: String, val otherPlayer: String,
        val durationMs: Long, val mediaAvailable: Boolean, val archive: String, val originals: String,
    )
}
