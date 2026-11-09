package com.islanddevcrew.jovra.core.contracts

import com.islanddevcrew.jovra.core.json.CanonicalJson
import com.islanddevcrew.jovra.core.pct.RateRatio
import java.math.BigDecimal
import java.math.BigInteger
import java.nio.file.Path
import kotlin.io.path.readText
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
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

class PracticeEvidenceTest {
    @TestFactory
    fun `real practice evidence rows retain rate provenance and stored availability`(): List<DynamicTest> {
        val root = Path.of(checkNotNull(System.getProperty("jovra.repoRoot"))).resolve("spec/fixtures/records")
        return listOf("practice-plan.sample.json", "practice-plan.all-fields.json").map { name ->
            dynamicTest(name) {
                val plan = Json.parseToJsonElement(root.resolve(name).readText()).jsonObject
                val item = plan.getValue("items").jsonArray.single().jsonObject
                val bytes = item.getValue("evidence").jsonArray.single().toString().encodeToByteArray()
                val row = PracticeEvidence.decodeJson(bytes, bytes.size)
                assertEquals(OpaqueId("b75c57d3-04df-5b4d-b969-32ed5cbfd97a"), row.sessionId)
                assertEquals("firstServePointsWon", row.stat)
                assertEquals(PracticeEvidence.Side.A, row.side)
                assertEquals(RateRatio(28, 40), row.value)
                assertEquals(70, row.value.pct)
                assertEquals(RecordProvenance.Status.REVIEWED, row.provenance.status)
                assertEquals("rule:practice.firstServePointsWon@1.0.0", row.provenance.source)
                assertEquals(true, row.provenance.sample)
                assertEquals(PracticeEvidence.Availability.VIDEO_UNAVAILABLE, row.availability)
                assertEquals(12, row.pointIds?.size)
                val expected = CanonicalJson.canonicalize(bytes)
                assertArrayEquals(expected, row.encodeJson(expected.size))
            }
        }
    }

    @Test
    fun `stored metadata stays independent and empty point IDs differ from absent IDs`() {
        val absent = decode(raw(availability = "available"))
        assertEquals(PracticeEvidence.Availability.AVAILABLE, absent.availability)
        assertNull(absent.pointIds)
        assertNull(absent.side)
        assertNull(absent.text)
        assertNull(absent.provenance.sample)

        val input = raw(
            ratio = """{"n":0,"d":0,"pct":null,"display":"—"}""",
            provenance = """{"status":"estimated","source":"model:pose@1","confidence":1e-39,"denominator":42,"sample":false}""",
            availability = "sessionDeleted",
            extra = """, "pointIds":[], "side":"B", "text":""""",
        )
        val deleted = decode(input)
        assertEquals(PracticeEvidence.Availability.SESSION_DELETED, deleted.availability)
        assertEquals(PracticeEvidence.Side.B, deleted.side)
        assertEquals("", deleted.text)
        assertEquals(emptyList<OpaqueId>(), deleted.pointIds)
        assertNull(deleted.value.pct)
        assertEquals("—", deleted.value.display)
        assertEquals(42L, deleted.provenance.denominator)
        assertEquals(RecordProvenance.Status.ESTIMATED, deleted.provenance.status)
        assertEquals(BigDecimal("1e-39"), deleted.provenance.confidence)
        assertEquals(false, deleted.provenance.sample)
        val expected = """{"availability":"sessionDeleted","pointIds":[],"provenance":{"confidence":0.000000000000000000000000000000000000001,"denominator":42,"sample":false,"source":"model:pose@1","status":"estimated"},"sessionId":"session-1","side":"B","stat":"firstServeIn","text":"","value":{"d":0,"display":"—","n":0,"pct":null}}"""
        assertArrayEquals(expected.encodeToByteArray(), deleted.encodeJson(expected.encodeToByteArray().size))
    }

    @Test
    fun `nested raw integer tokens and forged ratio fields are refused`() {
        for (field in listOf("n" to "1", "d" to "8", "pct" to "13")) {
            val (name, correct) = field
            for (token in listOf("$correct.0", "${correct}e0", "\"$correct\"")) {
                assertRefused(raw(ratio = ratio.replace("\"$name\":$correct", "\"$name\":$token")))
            }
        }
        assertRefused(raw(ratio = ratio.replace("\"pct\":13", "\"pct\":12")))
        assertRefused(raw(ratio = ratio.replace("13%", "12%")))
    }

    @Test
    fun `nested provenance denominator retains the original exact integer token`() {
        for (token in listOf("744.0", "744e0", "\"744\"")) {
            assertRefused(raw(provenance = provenance.dropLast(1) + ",\"denominator\":$token}"))
        }
        val exact = decode(raw(provenance = provenance.dropLast(1) + ",\"denominator\":9007199254740993}"))
        assertEquals(9_007_199_254_740_993L, exact.provenance.denominator)
    }

    @TestFactory
    fun `duplicates including escaped names fail at each object boundary`(): List<DynamicTest> = listOf(
        "row repeated" to raw(extra = ""","stat":"secondServeIn""""),
        "row escaped" to raw(extra = ""","\u0073tat":"secondServeIn""""),
        "ratio repeated" to raw(ratio = ratio.dropLast(1) + ""","n":1}"""),
        "ratio escaped" to raw(ratio = ratio.dropLast(1) + ""","\u006e":1}"""),
        "provenance repeated" to raw(provenance = provenance.dropLast(1) + ""","source":"user"}"""),
        "provenance escaped" to raw(provenance = provenance.dropLast(1) + ""","\u0073ource":"user"}"""),
    ).map { (name, input) -> dynamicTest(name) { assertRefused(input) } }

    @Test
    fun `closed row and nested shapes reject missing unknown invalid and null fields`() {
        for (field in listOf("sessionId", "stat", "value", "provenance", "availability")) {
            val obj = Json.parseToJsonElement(raw()).jsonObject
            assertRefused(JsonObject(obj - field).toString())
        }
        for (field in listOf("side", "text", "pointIds")) assertRefused(raw(extra = ",\"$field\":null"))
        for (invalid in listOf(
            raw(extra = ""","unknown":true"""),
            raw(extra = ""","side":"a""""),
            raw(extra = ""","side":"C""""),
            raw(availability = "deleted"),
            raw(ratio = "null"),
            raw(ratio = ratio.dropLast(1) + ""","unknown":0}"""),
            raw(provenance = "[]"),
            raw(provenance = provenance.dropLast(1) + ""","unknown":0}"""),
            raw().dropLast(1) + ",}",
            raw() + " []",
            "[${raw()}]",
        )) assertRefused(invalid)
    }

    @Test
    fun `opaque references preserve spelling and point order within the 50 item limit`() {
        val ids = List(50) { if (it % 2 == 0) "point:A-1" else "point:B-2" }
        val encodedIds = ids.joinToString(prefix = "[", postfix = "]") { quote(it) }
        val decoded = decode(raw(extra = ",\"pointIds\":$encodedIds"))
        assertEquals(ids.map(::OpaqueId), decoded.pointIds)
        assertRefused(raw(extra = ",\"pointIds\":" + (ids + "point:C-3").joinToString(prefix = "[", postfix = "]") { quote(it) }))
        for (token in listOf("\"pt-1\\n\"", "123", "null", "{}")) assertRefused(raw(extra = ",\"pointIds\":[$token]"))
        assertRefused(raw(sessionId = "session-1\n"))
        val mutableIds = mutableListOf(OpaqueId("point:A-1"))
        val row = PracticeEvidence(decoded.sessionId, decoded.stat, decoded.value, decoded.provenance, decoded.availability, pointIds = mutableIds)
        mutableIds.clear()
        assertEquals(listOf(OpaqueId("point:A-1")), row.pointIds)
    }

    @Test
    fun `stat and text use Unicode scalar limits and reject malformed Unicode`() {
        val stat = "🎾".repeat(80)
        val text = "🎾".repeat(120)
        val row = decode(raw(stat = stat, extra = ",\"text\":${quote(text)}"))
        assertEquals(stat, row.stat)
        assertEquals(text, row.text)
        assertRefused(raw(stat = ""))
        assertRefused(raw(stat = "$stat🎾"))
        assertRefused(raw(extra = ",\"text\":${quote("$text🎾")}"))
        assertRefused(raw(extra = ""","text":"\uD800""""))
        assertThrows(IllegalArgumentException::class.java) {
            PracticeEvidence(row.sessionId, "\uD800", row.value, row.provenance, row.availability)
        }
    }

    @Test
    fun `row budgets measure exact UTF-8 bytes and refuse large nested expansion`() {
        val input = raw(extra = ""","text":"🎾"""")
        val bytes = input.encodeToByteArray()
        val row = PracticeEvidence.decodeJson(bytes, bytes.size)
        val expected = CanonicalJson.canonicalize(bytes)
        assertArrayEquals(expected, row.encodeJson(expected.size))
        assertEquals(CanonicalJson.Limit.INPUT, assertThrows(CanonicalJson.LimitExceeded::class.java) {
            PracticeEvidence.decodeJson(bytes, bytes.size - 1)
        }.limit)
        assertEquals(CanonicalJson.Limit.OUTPUT, assertThrows(CanonicalJson.LimitExceeded::class.java) {
            row.encodeJson(expected.size - 1)
        }.limit)
        val invalid = byteArrayOf(0xc0.toByte(), 0xaf.toByte())
        assertThrows(CanonicalJson.LimitExceeded::class.java) { PracticeEvidence.decodeJson(invalid, 1) }
        assertThrows(IllegalArgumentException::class.java) { PracticeEvidence.decodeJson(invalid, invalid.size) }
        val precise = decode(raw(provenance = provenance.dropLast(1) + ",\"confidence\":1e-10000}"))
        val largeSource = "import:" + "x".repeat(8192)
        val longMetadata = PracticeEvidence(row.sessionId, row.stat, row.value,
            row.provenance.copy(source = largeSource, capabilityId = "a".repeat(8192)), row.availability)
        val huge = PracticeEvidence(row.sessionId, row.stat, row.value,
            row.provenance.copy(confidence = BigDecimal(BigInteger.ONE, Int.MAX_VALUE), source = largeSource), row.availability)
        for (oversize in listOf(precise, huge, longMetadata)) {
            assertEquals(CanonicalJson.Limit.OUTPUT, assertThrows(CanonicalJson.LimitExceeded::class.java) {
                oversize.encodeJson(256)
            }.limit)
        }
    }

    private val ratio = """{"n":1,"d":8,"pct":13,"display":"13%"}"""
    private val provenance = """{"status":"manual","source":"user"}"""

    private fun raw(
        ratio: String = this.ratio,
        provenance: String = this.provenance,
        availability: String = "available",
        sessionId: String = "session-1",
        stat: String = "firstServeIn",
        extra: String = "",
    ) = """{"sessionId":${quote(sessionId)},"stat":${quote(stat)},"value":$ratio,"provenance":$provenance,"availability":"$availability"$extra}"""

    private fun quote(value: String): String = Json.encodeToString(value)

    private fun decode(raw: String): PracticeEvidence {
        val bytes = raw.encodeToByteArray()
        return PracticeEvidence.decodeJson(bytes, bytes.size)
    }

    private fun assertRefused(raw: String) {
        assertThrows(IllegalArgumentException::class.java, { decode(raw) }, raw)
    }
}
