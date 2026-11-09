package com.islanddevcrew.jovra.core.contracts

import com.islanddevcrew.jovra.core.json.CanonicalJson
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
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.DynamicTest.dynamicTest
import org.junit.jupiter.api.Test
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

    @Test
    fun `decimal text retains spelling including zeros and values beyond binary precision`() {
        val threshold = "0009007199254740993.0100"
        val gate = decode(raw(metrics = "[${metric(threshold = quote(threshold), extra = ",\"unit\":\"\"")}]"))
        assertEquals(threshold, gate.thresholds.single().threshold)
        assertEquals("", gate.thresholds.single().unit)
        assertNull(decode(raw()).thresholds.single().unit)
        val expected = """{"metrics":[{"comparator":">=","name":"precision","threshold":"$threshold","unit":""}],"minimumData":"Synthetic controls","promotesTo":"estimated"}"""
        val bytes = expected.encodeToByteArray()
        assertArrayEquals(bytes, gate.encodeJson(bytes.size))
        assertEquals("0.90", decode(raw()).thresholds.single().threshold)
    }

    @Test
    fun `threshold accepts exact decimal text and rejects other types and spellings`() {
        for (token in listOf("0.90", "90", "true", "null", "{}", "[]") +
            listOf("-0.90", "+0.90", " 0.90", "0.90 ", "0.90\n", "0.90\r", ".90", "90.", "9e-1", "٠.٩٠", "").map(::quote)) {
            assertRefused(raw(metrics = "[${metric(threshold = token)}]"))
        }
        assertEquals("000.10", decode(raw(metrics = "[${metric(threshold = quote("000.10"))}]")).thresholds.single().threshold)
        assertThrows(IllegalArgumentException::class.java) {
            CapabilityGate.Threshold("precision", CapabilityGate.Comparator.AT_LEAST, "0.90\n")
        }
    }

    @TestFactory
    fun `duplicate keys including escaped names are refused at both object levels`(): List<DynamicTest> = listOf(
        "gate repeated" to raw(extra = ""","promotesTo":"estimated""""),
        "gate escaped" to raw(extra = ""","\u0070romotesTo":"estimated""""),
        "threshold repeated" to raw(metrics = "[${metric(extra = ""","threshold":"0.90"""")}]"),
        "threshold escaped" to raw(metrics = "[${metric(extra = ""","\u0074hreshold":"0.90"""")}]"),
    ).map { (name, input) -> dynamicTest(name) { assertRefused(input) } }

    @Test
    fun `closed gate and threshold shapes reject absent null unknown and nested fields`() {
        for (required in listOf("promotesTo", "metrics", "minimumData")) {
            val obj = Json.parseToJsonElement(raw()).jsonObject
            assertRefused(JsonObject(obj - required).toString())
            assertRefused(JsonObject(obj + (required to JsonNull)).toString())
        }
        for (required in listOf("name", "comparator", "threshold")) {
            val obj = Json.parseToJsonElement(metric()).jsonObject
            assertRefused(raw(metrics = "[${JsonObject(obj - required)}]"))
            assertRefused(raw(metrics = "[${JsonObject(obj + (required to JsonNull))}]"))
        }
        for (input in listOf(
            "null", "[]", raw(metrics = "[]"), raw(metrics = "{}"), raw(metrics = "[[${metric()}]]"),
            raw(metrics = "[null]"), raw(metrics = "[${metric(extra = ""","unit":null""")}]"),
            raw(metrics = "[${metric(extra = ""","unknown":0""")}]"), raw(extra = ""","unknown":0"""),
            raw(target = "manual"), raw(metrics = "[${metric(comparator = "=")}]"),
            raw().dropLast(1) + ",}", raw() + " {}",
        )) assertRefused(input)
    }

    @Test
    fun `text limits count Unicode scalars and preserve optional empty unit`() {
        val gate = decode(raw(minimumData = "🎾".repeat(300), metrics =
            "[${metric(name = "🎾".repeat(80), extra = ",\"unit\":${quote("🎾".repeat(16))}")}]"))
        assertEquals("🎾".repeat(300), gate.minimumData)
        assertEquals("🎾".repeat(80), gate.thresholds.single().name)
        assertEquals("🎾".repeat(16), gate.thresholds.single().unit)
        assertRefused(raw(minimumData = "🎾".repeat(301)))
        assertRefused(raw(minimumData = ""))
        assertRefused(raw(metrics = "[${metric(name = "🎾".repeat(81))}]"))
        assertRefused(raw(metrics = "[${metric(name = "")}]"))
        assertRefused(raw(metrics = "[${metric(extra = ",\"unit\":${quote("🎾".repeat(17))}")}]"))
        assertRefused(raw(metrics = "[${metric(extra = ""","unit":"\uD800"""")}]"))
        assertThrows(IllegalArgumentException::class.java) {
            CapabilityGate.Threshold("\uD800", CapabilityGate.Comparator.AT_MOST, "1")
        }
    }

    @Test
    fun `wire budgets count exact aggregate bytes and reject malformed UTF-8`() {
        val bytes = raw(minimumData = "🎾").encodeToByteArray()
        val gate = CapabilityGate.decodeJson(bytes, bytes.size)
        val expected = CanonicalJson.canonicalize(bytes)
        assertArrayEquals(expected, gate.encodeJson(expected.size))
        assertEquals(CanonicalJson.Limit.INPUT, assertThrows(CanonicalJson.LimitExceeded::class.java) {
            CapabilityGate.decodeJson(bytes, bytes.size - 1)
        }.limit)
        assertEquals(CanonicalJson.Limit.OUTPUT, assertThrows(CanonicalJson.LimitExceeded::class.java) {
            gate.encodeJson(expected.size - 1)
        }.limit)
        val invalid = byteArrayOf(0xc0.toByte(), 0xaf.toByte())
        assertThrows(CanonicalJson.LimitExceeded::class.java) { CapabilityGate.decodeJson(invalid, 1) }
        assertThrows(IllegalArgumentException::class.java) { CapabilityGate.decodeJson(invalid, invalid.size) }
    }

    @Test
    fun `caller budget covers repeated unbounded threshold text and construction owns its list`() {
        val first = CapabilityGate.Threshold("first", CapabilityGate.Comparator.AT_LEAST, "0.90")
        val second = CapabilityGate.Threshold("second", CapabilityGate.Comparator.AT_MOST, "7.0", "%")
        val supplied = mutableListOf(first, second)
        val gate = CapabilityGate(CapabilityGate.Target.VALIDATED, supplied, "Synthetic controls")
        supplied.reverse()
        assertEquals(listOf(first, second), gate.thresholds)
        assertEquals(listOf(first, second), decode(gate.encodeJson(256).decodeToString()).thresholds)
        val long = first.copy(threshold = "0." + "0".repeat(100_000) + "1")
        val many = CapabilityGate(CapabilityGate.Target.ESTIMATED, List(500) { long }, "Synthetic controls")
        val budget = 256
        val refusal = assertThrows(CanonicalJson.LimitExceeded::class.java) { many.encodeJson(budget) }
        assertEquals(CanonicalJson.Limit.OUTPUT, refusal.limit)
        assertEquals(budget, refusal.maxBytes)
    }

    private fun raw(
        target: String = "estimated",
        minimumData: String = "Synthetic controls",
        metrics: String = "[${metric()}]",
        extra: String = "",
    ) = """{"promotesTo":${quote(target)},"minimumData":${quote(minimumData)},"metrics":$metrics$extra}"""

    private fun metric(
        name: String = "precision",
        comparator: String = ">=",
        threshold: String = "\"0.90\"",
        extra: String = "",
    ) = """{"name":${quote(name)},"comparator":${quote(comparator)},"threshold":$threshold$extra}"""

    private fun quote(value: String): String = Json.encodeToString(value)

    private fun decode(raw: String): CapabilityGate {
        val bytes = raw.encodeToByteArray()
        return CapabilityGate.decodeJson(bytes, bytes.size)
    }

    private fun assertRefused(raw: String) {
        assertThrows(IllegalArgumentException::class.java, { decode(raw) }, raw)
    }
}
