package com.islanddevcrew.jovra.roomprotocol.smoke

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test

/**
 * Skeleton smoke test for :room-protocol (A01). It fails if the module stops being pure JVM (an Android class becomes
 * loadable), or if the kotlinx.serialization compiler plugin or runtime is dropped from the module's build file.
 */
class RoomProtocolSmokeTest {
    @Serializable
    private data class Probe(val module: String, val millis: Long)

    @Test
    fun `the module builds without Android on the classpath`() {
        assertThrows(ClassNotFoundException::class.java) { Class.forName("android.os.Build") }
    }

    @Test
    fun `kotlinx serialization round-trips an integer-only record`() {
        val json = """{"module":":room-protocol","millis":1500}"""
        val decoded = Json.decodeFromString(Probe.serializer(), json)
        assertEquals(Probe(":room-protocol", 1500L), decoded)
        assertEquals(json, Json.encodeToString(Probe.serializer(), decoded))
    }
}
