package com.islanddevcrew.jovra.core.contracts

import com.islanddevcrew.jovra.core.json.CanonicalJson
import java.nio.file.Path
import kotlin.io.path.readText
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.DynamicTest.dynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory

class SessionPlayerTest {
    @TestFactory
    fun `all player records in the three shared session fixtures round-trip`(): List<DynamicTest> {
        val root = Path.of(checkNotNull(System.getProperty("jovra.repoRoot"))).resolve("spec/fixtures")
        val fixtures = listOf(
            "sample/jon-vs-alex.session.json", "records/session.all-fields.json", "records/session.order-overrides.json",
        )
        return fixtures.flatMap { file ->
            val session = Json.parseToJsonElement(root.resolve(file).readText()).jsonObject
            val players = session.getValue("players").jsonArray
            assertEquals(2, players.size, file)
            players.map { source ->
                val fields = source.jsonObject
                val id = fields.getValue("id").jsonPrimitive.content
                dynamicTest("$file $id") {
                    val input = source.toString().encodeToByteArray()
                    val player = SessionPlayer.decodeJson(input, input.size)
                    assertEquals(id, player.id.value)
                    assertEquals(fields.getValue("displayName").jsonPrimitive.content, player.displayName)
                    assertEquals(fields.getValue("handedness").jsonPrimitive.content, player.handedness.wireName)
                    assertEquals(fields.getValue("backhand").jsonPrimitive.content, player.backhand.wireName)
                    assertEquals(fields.getValue("isSelf").jsonPrimitive.boolean, player.isSelf)
                    assertEquals(fields["profileId"]?.jsonPrimitive?.content, player.profileId?.value)
                    assertEquals(fields["level"]?.jsonPrimitive?.content, player.level)
                    assertArrayEquals(CanonicalJson.canonicalize(input), player.encodeJson())
                }
            }
        }
    }

    @Test
    fun `opaque IDs match the entire value and preserve spelling`() {
        for (id in listOf("A", "e75faf7e-1ce8-5d45-b003-af3f331b1082", "A0._:-z", "a".repeat(64))) {
            assertEquals(id, OpaqueId(id).value)
            assertEquals(OpaqueId(id), decode(playerJson(id = quote(id))).id)
        }
        for (id in listOf("", "a".repeat(65), "abc\n", "abc\r", "abc\r\n", " abc", "abc ", "_abc", "é", "a/1")) {
            assertThrows(IllegalArgumentException::class.java, { OpaqueId(id) }, id)
            assertRefused(playerJson(id = quote(id)))
            assertRefused(playerJson(extra = ",\"profileId\":" + quote(id)))
        }
        assertEquals(OpaqueId("A0._:-z"), decode(playerJson(extra = ",\"profileId\":\"A0._:-z\"")).profileId)
        assertRefused(playerJson(id = "123"))
    }

    @Test
    fun `strict grammar refuses unknown missing duplicate and malformed fields`() {
        val fields = Json.parseToJsonElement(playerJson()).jsonObject
        for (required in listOf("id", "displayName", "handedness", "backhand", "isSelf")) {
            assertRefused(JsonObject(fields - required).toString())
        }
        for (input in listOf(
            playerJson(extra = ",\"surprise\":\"none\""),
            playerJson(extra = ",\"id\":\"player-2\""),
            playerJson(extra = ",\"\\u0069d\":\"player-2\""),
            playerJson(extra = ",\"level\":\"a\",\"level\":\"b\""),
            playerJson().replace(",\"displayName\"", " \"displayName\""),
            playerJson().dropLast(1) + ",}",
            playerJson() + " null",
            """["player-1"]""",
        )) {
            assertRefused(input)
        }
        val nested = "[".repeat(2048) + "0" + "]".repeat(2048)
        assertRefused(playerJson(name = nested))
    }

    @Test
    fun `enum boolean and optional wire values keep their exact meaning`() {
        val player = decode(playerJson(hand = "\"unknown\"", backhand = "\"unknown\"", self = "false"))
        assertEquals(SessionPlayer.Handedness.UNKNOWN, player.handedness)
        assertEquals(SessionPlayer.Backhand.UNKNOWN, player.backhand)
        assertEquals(false, player.isSelf)
        assertNull(player.level)
        assertNull(player.profileId)
        assertArrayEquals(
            """{"backhand":"unknown","displayName":"Player","handedness":"unknown","id":"player-1","isSelf":false}""".encodeToByteArray(),
            player.encodeJson(),
        )
        assertEquals("", decode(playerJson(extra = ",\"level\":\"\"")).level)
        for (input in listOf(
            playerJson(hand = "\"Right\""), playerJson(backhand = "\"both\""),
            playerJson(self = "\"false\""), playerJson(self = "0"), playerJson(self = "null"),
            playerJson(name = "44"), playerJson(extra = ",\"level\":null"),
            playerJson(extra = ",\"level\":2"), playerJson(extra = ",\"profileId\":null"),
        )) {
            assertRefused(input)
        }
    }

    @Test
    fun `text lengths count Unicode scalars and preserve original names`() {
        val player = decode(playerJson(name = quote(" Jön / 🎾 ")))
        assertEquals(" Jön / 🎾 ", player.displayName)
        assertEquals(" ", decode(playerJson(name = quote(" "))).displayName)
        assertEquals("🎾".repeat(60), decode(playerJson(name = quote("🎾".repeat(60)))).displayName)
        assertEquals("e\u0301".repeat(30), decode(playerJson(name = quote("e\u0301".repeat(30)))).displayName)
        assertEquals("🎾".repeat(40), decode(playerJson(extra = ",\"level\":" + quote("🎾".repeat(40)))).level)
        assertRefused(playerJson(name = quote("")))
        assertRefused(playerJson(name = quote("🎾".repeat(61))))
        assertRefused(playerJson(name = quote("e\u0301".repeat(31))))
        assertRefused(playerJson(extra = ",\"level\":" + quote("🎾".repeat(41))))
        assertRefused(playerJson(name = "\"\\ud800\""))
        assertThrows(IllegalArgumentException::class.java) { player.copy(displayName = "\uD800") }
        assertThrows(IllegalArgumentException::class.java) { player.copy(level = "\uDC00") }
    }

    @Test
    fun `input byte limit precedes UTF-8 decoding`() {
        val bytes = playerJson(name = quote("🎾")).encodeToByteArray()
        assertEquals("🎾", SessionPlayer.decodeJson(bytes, bytes.size).displayName)
        val refused = assertThrows(CanonicalJson.LimitExceeded::class.java) {
            SessionPlayer.decodeJson(bytes, bytes.size - 1)
        }
        assertEquals(CanonicalJson.Limit.INPUT, refused.limit)
        assertEquals(bytes.size - 1, refused.maxBytes)
        val invalid = byteArrayOf(0xc0.toByte(), 0xaf.toByte())
        assertThrows(CanonicalJson.LimitExceeded::class.java) { SessionPlayer.decodeJson(invalid, 1) }
        assertThrows(IllegalArgumentException::class.java) { SessionPlayer.decodeJson(invalid, 2) }
    }

    private fun playerJson(
        id: String = "\"player-1\"",
        name: String = "\"Player\"",
        hand: String = "\"right\"",
        backhand: String = "\"twoHanded\"",
        self: String = "true",
        extra: String = "",
    ) = """{"id":$id,"displayName":$name,"handedness":$hand,"backhand":$backhand,"isSelf":$self$extra}"""

    private fun quote(value: String): String = Json.encodeToString(value)

    private fun decode(input: String): SessionPlayer {
        val bytes = input.encodeToByteArray()
        return SessionPlayer.decodeJson(bytes, bytes.size)
    }

    private fun assertRefused(input: String) {
        assertThrows(IllegalArgumentException::class.java, { decode(input) }, input)
    }
}
