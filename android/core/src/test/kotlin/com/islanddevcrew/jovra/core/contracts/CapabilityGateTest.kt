package com.islanddevcrew.jovra.core.contracts

import java.nio.file.Path
import kotlin.io.path.readText
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.DynamicTest.dynamicTest
import org.junit.jupiter.api.TestFactory

class CapabilityGateTest {
    @TestFactory
    fun `committed capability gates retain ordered exact thresholds`(): List<DynamicTest> {
        val root = Path.of(checkNotNull(System.getProperty("jovra.repoRoot")))
        val registry = Json.parseToJsonElement(root.resolve("spec/contracts/capability-registry.v1.json").readText()).jsonObject
        val capabilities = registry.getValue("capabilities").jsonArray.map { it.jsonObject }
        assertEquals(20, capabilities.size)
        assertEquals(14, capabilities.count { it.getValue("gate") == JsonNull })
        val gates = capabilities.filter { it.getValue("gate") != JsonNull }
        assertEquals(6, gates.size)
        assertEquals(11, gates.sumOf { it.getValue("gate").jsonObject.getValue("metrics").jsonArray.size })
        return gates.map { capability ->
            dynamicTest(capability.getValue("id").jsonPrimitive.content) {
                val fixture = capability.getValue("gate").jsonObject
                val metrics = fixture.getValue("metrics").jsonArray.map { it.jsonObject }
                val input = fixture.toString().encodeToByteArray()
                val gate = CapabilityGate.decodeJson(input, input.size)
                assertEquals(fixture.getValue("promotesTo").jsonPrimitive.content, gate.promotesTo.wireName)
                assertEquals(fixture.getValue("minimumData").jsonPrimitive.content, gate.minimumData)
                assertEquals(metrics.map { it.getValue("threshold").jsonPrimitive.content }, gate.thresholds.map { it.threshold })
                assertEquals(metrics.map { it.getValue("comparator").jsonPrimitive.content }, gate.thresholds.map { it.comparator.wireName })
                assertEquals(metrics.map { it["unit"]?.jsonPrimitive?.content }, gate.thresholds.map { it.unit })
                val ordered = fixture.toSortedMap().apply {
                    put("metrics", JsonArray(metrics.map { JsonObject(it.toSortedMap()) }))
                }
                val expected = JsonObject(ordered).toString().encodeToByteArray()
                assertArrayEquals(expected, gate.encodeJson(expected.size))
            }
        }
    }
}
