package com.islanddevcrew.jovra.core.pct

import com.islanddevcrew.jovra.core.json.CanonicalJson
import java.nio.file.Path
import kotlin.io.path.readText
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.DynamicTest.dynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory

class RateRatioWireTest {
    @Test
    fun `half-up rates and undefined rates round-trip exact canonical wire bytes`() {
        val examples = listOf(
            RateRatio(1, 8) to """{"d":8,"display":"13%","n":1,"pct":13}""",
            RateRatio(0, 0) to """{"d":0,"display":"—","n":0,"pct":null}""",
        )
        for ((expected, wire) in examples) {
            val bytes = wire.encodeToByteArray()
            assertEquals(expected, RateRatio.decodeJson(bytes, bytes.size))
            assertArrayEquals(bytes, expected.encodeJson(bytes.size))
        }
    }

    @TestFactory
    fun `all non-scoring shared rate records round-trip`(): List<DynamicTest> {
        val root = Path.of(checkNotNull(System.getProperty("jovra.repoRoot"))).resolve("spec/fixtures")
        val files = mapOf(
            "records/practice-plan.all-fields.json" to 1,
            "records/practice-plan.sample.json" to 1,
            "sample/jon-vs-alex.expected.json" to 31,
            "stats/T01-integer-percentages.json" to 27,
            "stats/T02-every-end-type.json" to 45,
            "stats/T03-doubles-per-server.json" to 41,
            "stats/T04-tiebreak-not-a-service-game.json" to 35,
        )
        return files.flatMap { (file, count) ->
            val fixture = Json.parseToJsonElement(root.resolve(file).readText())
            val records = ratioObjects(fixture)
            assertEquals(count, records.size, file)
            records.mapIndexed { index, record ->
                dynamicTest("$file rate ${index + 1}") {
                    val ratio = decode(record.toString())
                    assertEquals(record.getValue("n").jsonPrimitive.long, ratio.n)
                    assertEquals(record.getValue("d").jsonPrimitive.long, ratio.d)
                    assertEquals(record.getValue("pct"), ratio.pct?.let(::JsonPrimitive) ?: JsonNull)
                    assertEquals(record.getValue("display").jsonPrimitive.content, ratio.display)
                    // Fixture scalars are already canonical, so sorting their keys gives the independent wire bytes.
                    val expected = JsonObject(record.toSortedMap()).toString().encodeToByteArray()
                    assertArrayEquals(expected, ratio.encodeJson(expected.size))
                }
            }
        }
    }

    @Test
    fun `stored percentage must match integer derivation including undefined versus zero`() {
        assertRefused(wire(pct = "12"))
        assertRefused(wire(pct = "null"))
        assertRefused(wire(pct = "101"))
        assertRefused(wire(pct = "-1"))
        assertRefused(wire(pct = "0", n = "0", d = "0", display = "—"))
        assertEquals(0, decode(wire(pct = "0", n = "0", display = "0%")).pct)
    }

    @Test
    fun `stored display must equal canonical wire spelling`() {
        for (display in listOf("12%", "13 %", "13％", "13% ", "—", "")) assertRefused(wire(display = display))
        assertRefused(wire(pct = "null", n = "0", d = "0", display = "0%"))
        assertRefused(wire(pct = "null", n = "0", d = "0", display = "-"))
        assertRefused(wire().replace("\"13%\"", "13"))
        assertRefused(wire().replace("\"13%\"", "null"))
        assertEquals("13%", decode(wire().replace("13%", "\\u0031\\u0033%")).display)
    }

    @Test
    fun `raw integer tokens cannot be fractions exponents strings or overflowed numbers`() {
        for (token in listOf("1.0", "1e0", "\"1\"", "true", "null", "+1", "01", "9223372036854775808")) {
            assertRefused(wire(n = token))
        }
        for (token in listOf("8.0", "8E0", "\"8\"", "false", "null", "-8", "9223372036854775808")) {
            assertRefused(wire(d = token))
        }
        for (token in listOf("13.0", "13e0", "\"13\"", "true", "9223372036854775808")) {
            assertRefused(wire(pct = token))
        }
        assertRefused(wire(n = "-1"))
        assertRefused(wire(n = "9"))
        assertRefused(wire(n = "1", d = "0", pct = "null", display = "—"))
    }

    @Test
    fun `counts beyond binary precision and around a signed long threshold remain exact`() {
        val examples = listOf(
            RateRatio(9_007_199_254_740_993, 18_014_398_509_481_986) to
                """{"d":18014398509481986,"display":"50%","n":9007199254740993,"pct":50}""",
            RateRatio(1_152_921_504_606_846_975, Long.MAX_VALUE) to
                """{"d":9223372036854775807,"display":"12%","n":1152921504606846975,"pct":12}""",
            RateRatio(1_152_921_504_606_846_976, Long.MAX_VALUE) to
                """{"d":9223372036854775807,"display":"13%","n":1152921504606846976,"pct":13}""",
            RateRatio(Long.MAX_VALUE, Long.MAX_VALUE) to
                """{"d":9223372036854775807,"display":"100%","n":9223372036854775807,"pct":100}""",
        )
        for ((expected, raw) in examples) {
            val bytes = raw.encodeToByteArray()
            assertEquals(expected, decode(raw))
            assertArrayEquals(bytes, expected.encodeJson(bytes.size))
        }
    }

    @Test
    fun `closed wire object refuses missing duplicate unknown and malformed fields`() {
        for (raw in listOf(
            """{"n":1,"d":8,"pct":13}""", """{"n":1,"d":8,"display":"13%"}""",
            """{"n":1,"pct":13,"display":"13%"}""", """{"d":8,"pct":13,"display":"13%"}""",
            """{"n":1,"n":1,"d":8,"pct":13,"display":"13%"}""",
            """{"n":1,"d":8,"pct":13,"\u0070ct":13,"display":"13%"}""",
            """{"n":1,"d":8,"pct":13,"display":"13%","unknown":0}""",
            wire().dropLast(1) + ",}", wire() + " {}", "[${wire()}]",
        )) assertRefused(raw)
    }

    @Test
    fun `input and output limits apply to UTF-8 bytes at the exact boundary`() {
        val raw = """{"d":0,"display":"—","n":0,"pct":null}"""
        val bytes = raw.encodeToByteArray()
        val ratio = RateRatio.decodeJson(bytes, bytes.size)
        assertArrayEquals(bytes, ratio.encodeJson(bytes.size))
        assertEquals(CanonicalJson.Limit.INPUT, assertThrows(CanonicalJson.LimitExceeded::class.java) {
            RateRatio.decodeJson(bytes, bytes.size - 1)
        }.limit)
        assertEquals(CanonicalJson.Limit.OUTPUT, assertThrows(CanonicalJson.LimitExceeded::class.java) {
            ratio.encodeJson(bytes.size - 1)
        }.limit)
        val invalid = byteArrayOf(0xc0.toByte(), 0xaf.toByte())
        assertThrows(CanonicalJson.LimitExceeded::class.java) { RateRatio.decodeJson(invalid, 1) }
        assertThrows(IllegalArgumentException::class.java) { RateRatio.decodeJson(invalid, invalid.size) }
    }

    private fun ratioObjects(value: JsonElement): List<JsonObject> = when (value) {
        is JsonObject -> if (value.keys == setOf("n", "d", "pct", "display")) listOf(value) else
            value.values.flatMap(::ratioObjects)
        is JsonArray -> value.flatMap(::ratioObjects)
        else -> emptyList()
    }

    private fun wire(n: String = "1", d: String = "8", pct: String = "13", display: String = "13%") =
        """{"n":$n,"d":$d,"pct":$pct,"display":"$display"}"""

    private fun decode(raw: String): RateRatio {
        val bytes = raw.encodeToByteArray()
        return RateRatio.decodeJson(bytes, bytes.size)
    }

    private fun assertRefused(raw: String) {
        assertThrows(IllegalArgumentException::class.java, { decode(raw) }, raw)
    }
}
