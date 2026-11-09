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

class CanonicalJsonLimitsTest {
    @TestFactory
    fun `shared bytes meet the exact input and output limits`(): List<DynamicTest> {
        val root = Path.of(checkNotNull(System.getProperty("jovra.repoRoot")))
        val fixture = Json.parseToJsonElement(root.resolve("spec/contracts/canonical-json.v1.json").readText()).jsonObject
        return fixture.getValue("cases").jsonArray.map { it.jsonObject }.map { vector ->
            dynamicTest(vector.text("id")) {
                val input = vector.text("input").encodeToByteArray()
                val expected = vector.text("canonical").encodeToByteArray()
                assertArrayEquals(expected, CanonicalJson.canonicalize(input, CanonicalJson.Limits(input.size, expected.size)))
                assertLimit(CanonicalJson.Limit.INPUT, input.size - 1) {
                    CanonicalJson.canonicalize(input, CanonicalJson.Limits(input.size - 1, expected.size))
                }
                assertLimit(CanonicalJson.Limit.OUTPUT, expected.size - 1) {
                    CanonicalJson.canonicalize(input, CanonicalJson.Limits(input.size, expected.size - 1))
                }
            }
        }
    }

    @Test
    fun `limits are byte based and input refusal precedes UTF-8 decoding`() {
        val input = """ { "é":"🎾", "x":"\u0000", "a":"\u0061" } """.encodeToByteArray()
        val expected = """{"a":"a","x":"\u0000","é":"🎾"}""".encodeToByteArray()
        assertArrayEquals(expected, CanonicalJson.canonicalize(input, CanonicalJson.Limits(input.size, expected.size)))
        assertLimit(CanonicalJson.Limit.OUTPUT, expected.size - 1) {
            CanonicalJson.canonicalize(input, CanonicalJson.Limits(input.size, expected.size - 1))
        }

        val invalid = byteArrayOf(0xc0.toByte(), 0xaf.toByte())
        assertLimit(CanonicalJson.Limit.INPUT, 1) {
            CanonicalJson.canonicalize(invalid, CanonicalJson.Limits(1, 10))
        }
        val malformed = assertThrows(IllegalArgumentException::class.java) {
            CanonicalJson.canonicalize(invalid, CanonicalJson.Limits(2, 10))
        }
        assertEquals(IllegalArgumentException::class.java, malformed.javaClass)
    }

    @Test
    fun `one shared output budget covers expansions in nested objects and arrays`() {
        val input = """{"z":[1e30,1e30],"a":{"x":1e30}}""".encodeToByteArray()
        val number = "1" + "0".repeat(30)
        val expected = """{"a":{"x":$number},"z":[$number,$number]}""".encodeToByteArray()
        assertArrayEquals(expected, CanonicalJson.canonicalize(input, CanonicalJson.Limits(input.size, expected.size)))
        assertLimit(CanonicalJson.Limit.OUTPUT, expected.size - 1) {
            CanonicalJson.canonicalize(input, CanonicalJson.Limits(input.size, expected.size - 1))
        }

        for (token in listOf("1e10000", "-1e-10000")) {
            val bytes = token.encodeToByteArray()
            assertLimit(CanonicalJson.Limit.OUTPUT, 64) {
                CanonicalJson.canonicalize(bytes, CanonicalJson.Limits(bytes.size, 64))
            }
        }
    }

    @Test
    fun `numeric normalization keeps decimal positions and significant zeroes exact`() {
        for ((input, expected) in listOf(
            "0.0000100e2" to "0.001",
            "-10000.000e-1" to "-1000",
            "1.0100e-1" to "0.101",
            "10000000e-3" to "10000",
            "10000000e-7" to "1",
        )) {
            val bytes = input.encodeToByteArray()
            assertArrayEquals(
                expected.encodeToByteArray(),
                CanonicalJson.canonicalize(bytes, CanonicalJson.Limits(bytes.size, expected.length)),
            )
        }
    }

    @Test
    fun `zero limits refuse content and negative limits are invalid`() {
        assertThrows(IllegalArgumentException::class.java) { CanonicalJson.Limits(-1, 1) }
        assertThrows(IllegalArgumentException::class.java) { CanonicalJson.Limits(1, -1) }
        val input = "0".encodeToByteArray()
        assertLimit(CanonicalJson.Limit.INPUT, 0) { CanonicalJson.canonicalize(input, CanonicalJson.Limits(0, 1)) }
        assertLimit(CanonicalJson.Limit.OUTPUT, 0) { CanonicalJson.canonicalize(input, CanonicalJson.Limits(1, 0)) }
    }

    private fun assertLimit(direction: CanonicalJson.Limit, maxBytes: Int, operation: () -> Unit) {
        val error = assertThrows(CanonicalJson.LimitExceeded::class.java) { operation() }
        assertEquals(direction, error.limit)
        assertEquals(maxBytes, error.maxBytes)
    }

    private fun JsonObject.text(key: String): String = getValue(key).jsonPrimitive.content
}
