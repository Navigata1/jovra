package com.islanddevcrew.jovra.core.json

import java.nio.file.Path
import kotlin.io.path.readText
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.DynamicTest.dynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory

class CanonicalJsonTest {
    @TestFactory
    fun `independent shared CJSON01 canonical byte cases`(): List<DynamicTest> {
        val root = Path.of(checkNotNull(System.getProperty("jovra.repoRoot")))
        val fixture = Json.parseToJsonElement(root.resolve("spec/contracts/canonical-json.v1.json").readText()).jsonObject
        val vectors = fixture.getValue("cases").jsonArray.map { it.jsonObject }
        assertEquals(13, vectors.size)
        return vectors.map { vector ->
            dynamicTest(vector.text("id")) {
                assertCanonical(vector.text("input"), vector.text("canonical"))
            }
        }
    }

    @Test
    fun `object keys sort by scalar and canonically equivalent spellings stay distinct`() {
        assertCanonical(
            """{"🎾":0,"\ue000":1,"é":2,"e\u0301":3,"a𐀀":4,"a":5}""",
            "{\"a\":5,\"a𐀀\":4,\"e\u0301\":3,\"é\":2,\"\ue000\":1,\"🎾\":0}",
        )
    }

    @Test
    fun `decoded duplicate keys are refused at every object depth`() {
        for (input in listOf(
            """{"x":1,"x":2}""",
            """{"outer":[{"a":1,"\u0061":2}]}""",
            """{"🎾":1,"\ud83c\udfbe":2}""",
        )) {
            assertRefused(input)
        }
        assertCanonical("""[{"x":1},{"x":2}]""", """[{"x":1},{"x":2}]""")
    }

    @Test
    fun `invalid Unicode is refused in both keys and values`() {
        for (input in listOf(
            """{"\ud800":0}""",
            """["\udc00"]""",
            """["\ud800\u0061"]""",
            """["\udc00\ud800"]""",
            "\"\u0000\"",
            "\"\\\n\"",
        )) {
            assertRefused(input)
        }
        val malformedUtf8 = byteArrayOf(34, 0xC0.toByte(), 0xAF.toByte(), 34)
        val encodedSurrogate = byteArrayOf(34, 0xED.toByte(), 0xA0.toByte(), 0x80.toByte(), 34)
        for (bytes in listOf(malformedUtf8, encodedSurrogate)) {
            assertThrows(IllegalArgumentException::class.java) { CanonicalJson.canonicalize(bytes) }
        }
    }

    @Test
    fun `invalid JSON syntax and nonfinite values are refused`() {
        for (input in listOf(
            "", "true false", "null\u00a0", "[1,]", """{"x":1,}""", """{x:1}""",
            """{"x" 1}""", """["\q"]""", """["\u00fg"]""", "\"unterminated",
            "+1", "01", "-01", "1.", ".1", "1e", "1e+", "--1", "NaN", "Infinity", "-Infinity",
        )) {
            assertRefused(input)
        }
    }

    @Test
    fun `exact decimal text survives exponent and precision boundaries`() {
        assertCanonical(" 9007199254740993000000.01000e-2 \n", "90071992547409930000.0001")
        assertCanonical("1E+0000000000000000000001", "10")
        assertCanonical("-0.000E-10000", "0")
        assertCanonical("1e10000", "1" + "0".repeat(10000))
        assertCanonical("1e-10000", "0." + "0".repeat(9999) + "1")
        assertRefused("1e10001")
        assertRefused("0e-10001")
        assertRefused("1e2147483648")
    }

    @Test
    fun `excessive nesting is refused before stack exhaustion`() {
        val admitted = "[".repeat(511) + "0" + "]".repeat(511)
        assertCanonical(admitted, admitted)
        assertRefused("[".repeat(512) + "0" + "]".repeat(512))
    }

    private fun assertCanonical(input: String, expected: String) {
        assertArrayEquals(expected.encodeToByteArray(), CanonicalJson.canonicalize(input.encodeToByteArray()), input)
    }

    private fun assertRefused(input: String) {
        assertThrows(IllegalArgumentException::class.java, { CanonicalJson.canonicalize(input.encodeToByteArray()) }, input)
    }

    private fun JsonObject.text(key: String): String = getValue(key).jsonPrimitive.content
}
