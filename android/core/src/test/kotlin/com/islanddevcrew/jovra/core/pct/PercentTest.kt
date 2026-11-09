package com.islanddevcrew.jovra.core.pct

import java.nio.file.Path
import kotlin.io.path.readText
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.DynamicTest.dynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory

class PercentTest {
    @TestFactory
    fun `shared T01 percentage cases`(): List<org.junit.jupiter.api.DynamicTest> {
        val root = Path.of(checkNotNull(System.getProperty("jovra.repoRoot")))
        val fixture = Json.parseToJsonElement(
            root.resolve("spec/fixtures/stats/T01-integer-percentages.json").readText(),
        ).jsonObject
        val cases = fixture.getValue("cases").jsonArray.map { it.jsonObject }
        assertEquals(mapOf("ratio" to 24, "delta" to 5, "pool" to 3), cases.groupingBy { it.op }.eachCount())

        return cases.mapIndexed { index, case ->
            dynamicTest("T01 ${index + 1} ${case.op}") {
                val expected = case.getValue("expected").jsonObject
                when (case.op) {
                    "ratio" -> assertRatio(
                        RateRatio(case.getValue("n").jsonPrimitive.long, case.getValue("d").jsonPrimitive.long),
                        expected,
                    )
                    "delta" -> assertEquals(
                        expected.getValue("text").jsonPrimitive.content,
                        Percent.delta(case.getValue("current").jsonArray.toRatio(), case.getValue("prior").jsonArray.toRatio()),
                    )
                    "pool" -> assertRatio(
                        Percent.pool(case.getValue("parts").jsonArray.map { it.jsonArray.toRatio() }),
                        expected,
                    )
                    else -> error("Unknown T01 operation: ${case.op}")
                }
            }
        }
    }

    @Test
    fun `rounding stays exact at signed Long limits`() {
        assertEquals(100, Percent.pct(Long.MAX_VALUE, Long.MAX_VALUE))
        assertEquals(12, Percent.pct(Long.MAX_VALUE / 8, Long.MAX_VALUE))
        assertEquals(13, Percent.pct(Long.MAX_VALUE / 8 + 1, Long.MAX_VALUE))
        assertEquals(100, Percent.pool(listOf(RateRatio(Long.MAX_VALUE - 1, Long.MAX_VALUE - 1), RateRatio(1, 1))).pct)
    }

    @Test
    fun `impossible counts are refused and zero opportunities remain unknown`() {
        assertThrows(IllegalArgumentException::class.java) { Percent.pct(-1, 8) }
        assertThrows(IllegalArgumentException::class.java) { Percent.pct(0, -1) }
        assertThrows(IllegalArgumentException::class.java) { RateRatio(9, 8) }
        assertThrows(IllegalArgumentException::class.java) { Percent.pct(1, 0) }
        assertNull(Percent.pct(0, 0))
        assertNull(Percent.pool(emptyList()).pct)
    }

    @Test
    fun `pooling refuses counts that cannot be represented`() {
        assertThrows(ArithmeticException::class.java) {
            Percent.pool(listOf(RateRatio(0, Long.MAX_VALUE), RateRatio(0, 1)))
        }
        assertThrows(ArithmeticException::class.java) {
            Percent.pool(listOf(RateRatio(Long.MAX_VALUE, Long.MAX_VALUE), RateRatio(1, 1)))
        }
    }

    private val JsonObject.op: String get() = getValue("op").jsonPrimitive.content
    private fun JsonArray.toRatio(): RateRatio = RateRatio(this[0].jsonPrimitive.long, this[1].jsonPrimitive.long)

    private fun assertRatio(actual: RateRatio, expected: JsonObject) {
        assertEquals(expected.getValue("n").jsonPrimitive.long, actual.n)
        assertEquals(expected.getValue("d").jsonPrimitive.long, actual.d)
        val pct = expected.getValue("pct").jsonPrimitive
        assertEquals(pct.contentOrNull?.let { checkNotNull(pct.intOrNull) }, actual.pct)
        assertEquals(expected.getValue("display").jsonPrimitive.content, actual.display)
    }
}
