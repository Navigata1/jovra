package com.islanddevcrew.jovra.core.units

import java.nio.file.Path
import kotlin.io.path.readText
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.DynamicTest.dynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory

class UnitsTest {
    @TestFactory
    fun `shared U01 units cases`(): List<DynamicTest> {
        val root = Path.of(checkNotNull(System.getProperty("jovra.repoRoot")))
        val fixture = Json.parseToJsonElement(
            root.resolve("spec/fixtures/units/U01-exact-conversions.json").readText(),
        ).jsonObject
        val cases = fixture.getValue("cases").jsonArray.map { it.jsonObject }
        assertEquals(mapOf("convert" to 9, "display" to 19, "gaugeHint" to 3), cases.groupingBy { it.text("op") }.eachCount())

        return cases.mapIndexed { index, case ->
            val op = case.text("op")
            dynamicTest("U01 ${index + 1} $op") {
                val expected = case.getValue("expected").jsonObject
                when (op) {
                    "convert" -> assertEquals(
                        expected.text("value"),
                        Units.convert(
                            case.text("value"), case.text("from"), case.text("to"),
                            case.getValue("places").jsonPrimitive.int,
                        ),
                    )
                    "display" -> assertEquals(
                        UnitDisplay(expected.text("value"), expected.text("unit"), expected.boolean("converted")),
                        Units.display(case.text("value"), case.text("unit"), case.text("preferredUnit")),
                    )
                    "gaugeHint" -> assertEquals(
                        GaugeHint(
                            expected.text("label"),
                            expected.boolean("known"),
                            expected.getValue("ranges").jsonArray.map { range ->
                                val item = range.jsonObject
                                GaugeRange(item.text("source"), item.text("minMm"), item.text("maxMm"))
                            },
                        ),
                        Units.gaugeHint(case.text("label")),
                    )
                    else -> error("Unknown U01 operation: $op")
                }
            }
        }
    }

    @Test
    fun `display rounds once at the destination step`() {
        val belowHalf = "1.249999999999999999999999999999"
        assertEquals(UnitDisplay("4", "km/h", true), Units.display(belowHalf, "m/s", "km/h"))
        assertEquals(UnitDisplay("5", "km/h", true), Units.display("1.25", "m/s", "km/h"))
        // Exact kgf equivalents of 50.25 lb and slightly below 50.25 lb.
        assertEquals(UnitDisplay("50.5", "lb", true), Units.display("22.7930165925", "kg", "lb"))
        assertEquals(UnitDisplay("50", "lb", true), Units.display("22.793016592499999999999999999999", "kg", "lb"))
    }

    @Test
    fun `fixed places and entered decimal text are preserved at their own boundaries`() {
        assertEquals("1.01", Units.convert("1.005", "kg", "kg", 2))
        assertEquals("0.000", Units.convert("0", "in", "mm", 3))
        assertEquals("0.00000000000000000000", Units.convert("0", "in", "mm", 20))
        assertEquals(UnitDisplay("00052.000", "lb", false), Units.display("00052.000", "lb", "lb"))
    }

    @Test
    fun `invalid decimal representations and unsupported places are refused`() {
        for (invalid in listOf("", " 52", "52 ", "52\n", "52\r", "52\r\n", "5e1", "+52", "-52", "52,0", ".5", "52.", "５２")) {
            assertThrows(IllegalArgumentException::class.java) { Units.convert(invalid, "lb", "kg", 2) }
            assertThrows(IllegalArgumentException::class.java) { Units.display(invalid, "lb", "lb") }
        }
        assertThrows(IllegalArgumentException::class.java) { Units.convert("1", "lb", "kg", -1) }
        assertThrows(IllegalArgumentException::class.java) { Units.convert("1", "lb", "kg", 21) }
    }

    @Test
    fun `unknown units and incompatible dimensions cannot relabel a quantity`() {
        assertThrows(IllegalArgumentException::class.java) { Units.display("52", "lbs", "lbs") }
        assertThrows(IllegalArgumentException::class.java) { Units.display("52", "lb", "KG") }
        assertThrows(IllegalArgumentException::class.java) { Units.display("1", "kg", "g") }
        assertThrows(IllegalArgumentException::class.java) { Units.convert("1", "mm", "cm2", 2) }
    }

    private fun JsonObject.text(key: String): String = getValue(key).jsonPrimitive.content
    private fun JsonObject.boolean(key: String): Boolean = getValue(key).jsonPrimitive.boolean
}
