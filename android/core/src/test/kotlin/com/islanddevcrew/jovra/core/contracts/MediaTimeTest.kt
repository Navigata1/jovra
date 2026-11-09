package com.islanddevcrew.jovra.core.contracts

import com.islanddevcrew.jovra.core.json.CanonicalJson
import java.nio.file.Path
import kotlin.io.path.readText
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.DynamicTest.dynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory

class MediaTimeTest {
    @TestFactory
    fun `all rational times in the shared session fixture round-trip`(): List<DynamicTest> {
        val root = Path.of(checkNotNull(System.getProperty("jovra.repoRoot")))
        val file = root.resolve("spec/fixtures/records/session.all-fields.json")
        val session = Json.parseToJsonElement(file.readText()).jsonObject
        val marks = session.getValue("serveMarks").jsonArray.flatMap { mark ->
            listOf("contactFrame", "bounceFrame").map { mark.jsonObject.getValue(it) }
        }
        val moments = session.getValue("swings").jsonArray.flatMap { swing ->
            swing.jsonObject.getValue("keyMoments").jsonArray.map { it.jsonObject.getValue("time") }
        }
        val expected = listOf(
            1830L to 60L, 1854L to 60L,
            1759L to 60L, 1801L to 60L, 1822L to 60L, 1830L to 60L, 1846L to 60L, 1790L to 60L,
            7440L to 240L, 7476L to 240L, 7512L to 240L, 7536L to 240L, 7584L to 240L,
        )
        val times = marks + moments
        assertEquals(expected.size, times.size)
        return times.mapIndexed { index, time ->
            dynamicTest("shared mediaTime " + (index + 1)) {
                val (value, scale) = expected[index]
                assertTime(time.toString(), value, scale)
            }
        }
    }

    @Test
    fun `integer tokens retain exact signed Long precision and the original rational pair`() {
        assertTime("""{"value":744,"timescale":240}""", 744, 240)
        assertTime("""{"timescale":30000,"value":46046000}""", 46046000, 30000)
        assertTime("""{"value":9007199254740993,"timescale":2147483648}""", 9007199254740993, 2147483648)
        assertTime("""{"value":9223372036854775807,"timescale":9223372036854775807}""", Long.MAX_VALUE, Long.MAX_VALUE)
        assertTime("""{"\u0076alue":-0,"timescale":1}""", 0, 1)
    }

    @Test
    fun `integral floats exponent tokens and quoted integers are refused before canonicalization`() {
        for (token in listOf("744.0", "744e0", "7.44e2", "744E+0", "\"744\"", "+744", "0744", "744.", "true", "null")) {
            assertRefused("""{"value":$token,"timescale":240}""")
        }
        for (token in listOf("240.0", "240e0", "\"240\"", "false", "null")) {
            assertRefused("""{"value":744,"timescale":$token}""")
        }
    }

    @Test
    fun `missing unknown duplicate and malformed fields are refused`() {
        for (input in listOf(
            """{}""", """{"value":744}""", """{"timescale":240}""",
            """{"value":744,"timescale":240,"extra":0}""",
            """{"value":744,"value":744,"timescale":240}""",
            """{"value":744,"\u0076alue":745,"timescale":240}""",
            """{"value":744,"timescale":240,"timescale":240}""",
            """{"value":744 "timescale":240}""",
            """{"value":744,"timescale":240,}""",
            """{"value":744,"timescale":240} null""", """[744,240]""",
        )) {
            assertRefused(input)
        }
    }

    @Test
    fun `negative values nonpositive scales and numeric overflow are refused`() {
        for (input in listOf(
            """{"value":-1,"timescale":240}""",
            """{"value":744,"timescale":0}""",
            """{"value":744,"timescale":-1}""",
            """{"value":9223372036854775808,"timescale":240}""",
            """{"value":744,"timescale":9223372036854775808}""",
        )) {
            assertRefused(input)
        }
        assertThrows(IllegalArgumentException::class.java) { MediaTime(-1, 240) }
        assertThrows(IllegalArgumentException::class.java) { MediaTime(744, 0) }
    }

    @Test
    fun `explicit byte limit rejects before UTF-8 decoding`() {
        val input = """{"value":744,"timescale":240}""".encodeToByteArray()
        assertEquals(MediaTime(744, 240), MediaTime.decodeJson(input, input.size))
        val tooLong = assertThrows(CanonicalJson.LimitExceeded::class.java) {
            MediaTime.decodeJson(input, input.size - 1)
        }
        assertEquals(CanonicalJson.Limit.INPUT, tooLong.limit)
        assertEquals(input.size - 1, tooLong.maxBytes)
        val invalid = byteArrayOf(0xc0.toByte(), 0xaf.toByte())
        assertThrows(CanonicalJson.LimitExceeded::class.java) { MediaTime.decodeJson(invalid, 1) }
        assertThrows(IllegalArgumentException::class.java) { MediaTime.decodeJson(invalid, 2) }
        assertThrows(IllegalArgumentException::class.java) { MediaTime.decodeJson(input, -1) }
    }

    private fun assertTime(input: String, value: Long, scale: Long) {
        val bytes = input.encodeToByteArray()
        val time = MediaTime.decodeJson(bytes, bytes.size)
        assertEquals(MediaTime(value, scale), time)
        val expected = """{"timescale":$scale,"value":$value}""".encodeToByteArray()
        assertArrayEquals(expected, time.encodeJson())
    }

    private fun assertRefused(input: String) {
        val bytes = input.encodeToByteArray()
        assertThrows(IllegalArgumentException::class.java, { MediaTime.decodeJson(bytes, bytes.size) }, input)
    }
}
