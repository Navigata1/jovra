package com.islanddevcrew.jovra.core.contracts

import com.islanddevcrew.jovra.core.json.CanonicalJson
import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.readText
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.DynamicTest.dynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory

class RecordedFrameRateTest {
    @TestFactory
    fun `all shared frame-rate records round-trip as original rational pairs`(): List<DynamicTest> {
        val root = Path.of(checkNotNull(System.getProperty("jovra.repoRoot"))).resolve("spec/fixtures")
        val session = readObject(root.resolve("records/session.all-fields.json"))
        val recording = session.getValue("recording").jsonObject
        val segments = recording.getValue("segments").jsonArray.map { it.jsonObject.getValue("frameRate") }
        val captures = recording.getValue("captureEvents").jsonArray.mapNotNull { it.jsonObject["frameRate"] }
        val calibrations = session.getValue("calibrations").jsonArray.mapNotNull {
            it.jsonObject["camera"]?.jsonObject?.get("frameRate")
        }
        val manifest = readObject(root.resolve("sample/media-manifest.json"))
        val sample = manifest.getValue("media").jsonArray.map { media ->
            val fields = media.jsonObject
            fields.getValue("mediaId").jsonPrimitive.content to fields.getValue("frameRate")
        }
        val groundTruth = Files.walk(root.resolve("media")).use { paths ->
            paths.filter { it.fileName.toString().endsWith(".truth.json") }.sorted().toList().map { path ->
                root.relativize(path).toString() to readObject(path).getValue("video").jsonObject.getValue("frameRate")
            }
        }

        assertEquals(1, segments.size)
        assertEquals(1, captures.size)
        assertEquals(1, calibrations.size)
        assertEquals(11, sample.size)
        assertEquals(19, groundTruth.size)
        val fixtureRates = listOf(
            "recording segment" to segments.single(),
            "capture rate change" to captures.single(),
            "calibration camera" to calibrations.single(),
        ) + sample + groundTruth
        return fixtureRates.map { (name, value) ->
            dynamicTest(name) { assertFixture(value) }
        }
    }

    @Test
    fun `exact and unreduced rational pairs survive encoding`() {
        assertRate("""{"num":30000,"den":1001}""", 30000, 1001)
        assertRate("""{"den":1001,"num":60000}""", 60000, 1001)
        assertRate("""{"num":60000,"den":2002}""", 60000, 2002)
        assertRate("""{"num":9007199254740993,"den":9223372036854775807}""", 9007199254740993, Long.MAX_VALUE)
        assertRate("""{"\u006eum":9223372036854775807,"den":1}""", Long.MAX_VALUE, 1)
    }

    @Test
    fun `both fields require raw integer tokens before canonicalization`() {
        for (token in listOf("1.0", "1e0", "1E+0", "\"1\"", "+1", "01", "1.", "true", "null")) {
            assertRefused("""{"num":$token,"den":1}""")
            assertRefused("""{"num":60,"den":$token}""")
        }
    }

    @Test
    fun `positive representable values are required for both terms`() {
        for (token in listOf("0", "-0", "-1", "9223372036854775808")) {
            assertRefused("""{"num":$token,"den":1}""")
            assertRefused("""{"num":60,"den":$token}""")
        }
        assertThrows(IllegalArgumentException::class.java) { RecordedFrameRate(0, 1) }
        assertThrows(IllegalArgumentException::class.java) { RecordedFrameRate(60, 0) }
    }

    @Test
    fun `closed object refuses missing unknown duplicate and malformed fields`() {
        for (input in listOf(
            """{}""", """{"num":60}""", """{"den":1}""", """{"num":60,"den":1,"extra":1}""",
            """{"num":60,"num":60,"den":1}""", """{"num":60,"\u006eum":30,"den":1}""",
            """{"num":60,"den":1,"den":1}""", """{"num":60 "den":1}""", """{"num":60,"den":1,}""",
            """{"num":60,"den":1} null""", """[60,1]""", """{"num":{"value":60},"den":1}""",
        )) {
            assertRefused(input)
        }
        val nested = "[".repeat(2048) + "0" + "]".repeat(2048)
        assertRefused("""{"num":60,"den":$nested}""")
    }

    @Test
    fun `explicit input byte limit precedes UTF-8 decoding`() {
        val input = """{"num":60,"den":1}""".encodeToByteArray()
        assertEquals(RecordedFrameRate(60, 1), RecordedFrameRate.decodeJson(input, input.size))
        val refused = assertThrows(CanonicalJson.LimitExceeded::class.java) {
            RecordedFrameRate.decodeJson(input, input.size - 1)
        }
        assertEquals(CanonicalJson.Limit.INPUT, refused.limit)
        assertEquals(input.size - 1, refused.maxBytes)
        val invalid = byteArrayOf(0xc0.toByte(), 0xaf.toByte())
        assertThrows(CanonicalJson.LimitExceeded::class.java) { RecordedFrameRate.decodeJson(invalid, 1) }
        assertThrows(IllegalArgumentException::class.java) { RecordedFrameRate.decodeJson(invalid, 2) }
    }

    private fun readObject(path: Path): JsonObject = Json.parseToJsonElement(path.readText()).jsonObject

    private fun assertFixture(value: JsonElement) {
        val fields = value.jsonObject
        assertRate(value.toString(), fields.getValue("num").jsonPrimitive.long, fields.getValue("den").jsonPrimitive.long)
    }

    private fun assertRate(input: String, num: Long, den: Long) {
        val bytes = input.encodeToByteArray()
        val rate = RecordedFrameRate.decodeJson(bytes, bytes.size)
        assertEquals(RecordedFrameRate(num, den), rate)
        assertArrayEquals("""{"den":$den,"num":$num}""".encodeToByteArray(), rate.encodeJson())
    }

    private fun assertRefused(input: String) {
        val bytes = input.encodeToByteArray()
        assertThrows(IllegalArgumentException::class.java, { RecordedFrameRate.decodeJson(bytes, bytes.size) }, input)
    }
}
