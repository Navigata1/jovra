package com.islanddevcrew.jovra.core.contracts

import com.islanddevcrew.jovra.core.json.CanonicalJson
import java.math.BigDecimal
import java.math.BigInteger
import java.nio.file.Path
import kotlin.io.path.readText
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.DynamicTest.dynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory

class RecordProvenanceTest {
    @TestFactory
    fun `shared session and practice provenance records round-trip`(): List<DynamicTest> {
        val root = Path.of(checkNotNull(System.getProperty("jovra.repoRoot"))).resolve("spec/fixtures")
        val files = mapOf(
            "records/session.all-fields.json" to 17,
            "records/session.order-overrides.json" to 1,
            "sample/jon-vs-alex.session.json" to 1,
            "records/practice-plan.all-fields.json" to 1,
            "records/practice-plan.sample.json" to 1,
        )
        return files.flatMap { (file, count) ->
            val rootRecord = Json.parseToJsonElement(root.resolve(file).readText())
            val records = provenanceObjects(rootRecord)
            assertEquals(count, records.size, file)
            records.mapIndexed { index, record ->
                dynamicTest("$file provenance " + (index + 1)) {
                    val input = record.toString()
                    val expected = CanonicalJson.canonicalize(input.encodeToByteArray())
                    val provenance = decode(input)
                    assertEquals(record.getValue("status").jsonPrimitive.content, provenance.status.wireName)
                    assertEquals(record.getValue("source").jsonPrimitive.content, provenance.source)
                    assertArrayEquals(expected, provenance.encodeJson(expected.size))
                }
            }
        }
    }

    @Test
    fun `all optional fields preserve exact evidence values without changing provenance`() {
        val input = """{"status":"estimated","source":"model:pose.v2@2.0+test","capabilityId":"swing.pose2D","capabilityVersion":"v1+local","confidence":0.1234567890123456789012345678901234567890,"calibrationId":"court-1","denominator":9007199254740993,"computedAt":"2026-10-07T18:00:00.125Z","sample":true}"""
        val record = decode(input)
        assertEquals(RecordProvenance.Status.ESTIMATED, record.status)
        assertEquals("model:pose.v2@2.0+test", record.source)
        assertEquals("swing.pose2D", record.capabilityId)
        assertEquals("v1+local", record.capabilityVersion)
        assertEquals(0, BigDecimal("0.123456789012345678901234567890123456789").compareTo(record.confidence))
        assertEquals(OpaqueId("court-1"), record.calibrationId)
        assertEquals(9007199254740993L, record.denominator)
        assertEquals("2026-10-07T18:00:00.125Z", record.computedAt)
        assertEquals(true, record.sample)
        val expected = """{"calibrationId":"court-1","capabilityId":"swing.pose2D","capabilityVersion":"v1+local","computedAt":"2026-10-07T18:00:00.125Z","confidence":0.123456789012345678901234567890123456789,"denominator":9007199254740993,"sample":true,"source":"model:pose.v2@2.0+test","status":"estimated"}"""
        assertCanonical(record, expected)
        assertEquals(record, decode(expected))
    }

    @Test
    fun `status and producer tokens follow the shared lexical rules`() {
        for ((wire, status) in listOf(
            "manual" to RecordProvenance.Status.MANUAL,
            "estimated" to RecordProvenance.Status.ESTIMATED,
            "reviewed" to RecordProvenance.Status.REVIEWED,
            "validated" to RecordProvenance.Status.VALIDATED,
        )) {
            val record = decode(record(status = quote(wire), extra = ",\"sample\":false"))
            assertEquals(status, record.status)
            assertEquals(false, record.sample)
        }
        for (source in listOf("user", "model:pose.v2@2.0+test", "rule:rate.v1@1-rc", "import:archive_1", "sample:demo@1.0")) {
            assertEquals(source, decode(record(source = quote(source))).source)
        }
        for (source in listOf("User", "user\n", "user\r", "model:pose", "model:@1", "model:a@",
                             "rule:a@1\n", "import:archive@1", "sample:demo", "model:a/b@1", "")) {
            assertRefused(record(source = quote(source)))
        }
        assertRefused(record(status = "\"sample\""))
        assertRefused(record(status = "\"Manual\""))
    }

    @Test
    fun `confidence remains an exact numeric value and denominator remains an integer`() {
        assertCanonical(decode(record(extra = ",\"confidence\":7.500e-1")),
            """{"confidence":0.75,"source":"user","status":"manual"}""")
        assertCanonical(decode(record(extra = ",\"confidence\":-0.000,\"denominator\":0")),
            """{"confidence":0,"denominator":0,"source":"user","status":"manual"}""")
        assertEquals(0, BigDecimal.ONE.compareTo(decode(record(extra = ",\"confidence\":1")).confidence))
        for (token in listOf("\"0.5\"", "true", "null", "-0.0001", "1.000000000000000000000000000000000000001", "NaN")) {
            assertRefused(record(extra = ",\"confidence\":" + token))
        }
        for (token in listOf("744.0", "744e0", "\"744\"", "true", "null", "-1", "9223372036854775808")) {
            assertRefused(record(extra = ",\"denominator\":" + token))
        }
        assertEquals(Long.MAX_VALUE, decode(record(extra = ",\"denominator\":9223372036854775807")).denominator)
    }

    @Test
    fun `confidence output cannot expand beyond the caller budget`() {
        val tiny = decode(record(extra = ",\"confidence\":1e-10000"))
        val tinyDecimal = "0." + "0".repeat(9_999) + "1"
        assertCanonical(tiny, """{"confidence":$tinyDecimal,"source":"user","status":"manual"}""")
        val plainBeyondExponentGuard = "0." + "0".repeat(10_000) + "1"
        val plain = decode(record(extra = ",\"confidence\":" + plainBeyondExponentGuard))
        assertCanonical(plain, """{"confidence":$plainBeyondExponentGuard,"source":"user","status":"manual"}""")
        val extreme = tiny.copy(confidence = BigDecimal(BigInteger.ONE, Int.MAX_VALUE))
        for (record in listOf(tiny, extreme)) {
            val failure = assertThrows(CanonicalJson.LimitExceeded::class.java) { record.encodeJson(128) }
            assertEquals(CanonicalJson.Limit.OUTPUT, failure.limit)
        }
    }

    @Test
    fun `optional metadata preserves valid scalar spelling and refuses nulls`() {
        val base = decode(record())
        assertNull(base.capabilityId)
        assertNull(base.capabilityVersion)
        assertNull(base.confidence)
        assertNull(base.calibrationId)
        assertNull(base.denominator)
        assertNull(base.computedAt)
        assertNull(base.sample)
        assertCanonical(base, """{"source":"user","status":"manual"}""")
        val version = "🎾".repeat(64)
        assertEquals(version, decode(record(extra = ",\"capabilityVersion\":" + quote(version))).capabilityVersion)
        for (extra in listOf(
            ",\"capabilityId\":\"Pose.v1\"", ",\"capabilityId\":\"pose..v1\"", ",\"capabilityId\":\"pose_v1\"",
            ",\"capabilityVersion\":\"\"", ",\"capabilityVersion\":" + quote("🎾".repeat(65)),
            ",\"calibrationId\":\"court\\n\"", ",\"sample\":\"false\"", ",\"sample\":0",
            ",\"computedAt\":\"2026-10-07T18:00:00+00:00\"", ",\"computedAt\":\"2026-10-07T18:00:00.1234Z\"",
            ",\"computedAt\":\"2026-10-07T18:00:00Z\\n\"",
        )) {
            assertRefused(record(extra = extra))
        }
        for (field in listOf("capabilityId", "capabilityVersion", "confidence", "calibrationId", "denominator", "computedAt", "sample")) {
            assertRefused(record(extra = ",\"$field\":null"))
        }
        assertThrows(IllegalArgumentException::class.java) { base.copy(capabilityVersion = "\uD800") }
        assertThrows(IllegalArgumentException::class.java) { base.copy(denominator = -1) }
    }

    @Test
    fun `closed provenance input and byte limits refuse malformed input`() {
        for (raw in listOf(
            """{}""", """{"status":"manual"}""", """{"source":"user"}""",
            record(extra = ",\"unknown\":false"), record(extra = ",\"source\":\"user\""),
            record(extra = ",\"\\u0073ource\":\"user\""), record(extra = ",\"sample\":{}"),
            record().dropLast(1) + ",}", record() + " null", record().replace(",\"source\"", " \"source\""),
        )) {
            assertRefused(raw)
        }
        val bytes = record().encodeToByteArray()
        assertEquals("user", RecordProvenance.decodeJson(bytes, bytes.size).source)
        val failure = assertThrows(CanonicalJson.LimitExceeded::class.java) {
            RecordProvenance.decodeJson(bytes, bytes.size - 1)
        }
        assertEquals(CanonicalJson.Limit.INPUT, failure.limit)
        val invalid = byteArrayOf(0xc0.toByte(), 0xaf.toByte())
        assertThrows(CanonicalJson.LimitExceeded::class.java) { RecordProvenance.decodeJson(invalid, 1) }
        assertThrows(IllegalArgumentException::class.java) { RecordProvenance.decodeJson(invalid, 2) }
    }

    private fun provenanceObjects(value: JsonElement): List<JsonObject> = when (value) {
        is JsonObject -> value.flatMap { (key, child) ->
            if (key == "provenance" && child is JsonObject) listOf(child) else provenanceObjects(child)
        }
        is JsonArray -> value.flatMap(::provenanceObjects)
        else -> emptyList()
    }

    private fun record(status: String = "\"manual\"", source: String = "\"user\"", extra: String = "") =
        """{"status":$status,"source":$source$extra}"""

    private fun quote(value: String): String = Json.encodeToString(value)

    private fun assertCanonical(record: RecordProvenance, expected: String) {
        val bytes = expected.encodeToByteArray()
        assertArrayEquals(bytes, record.encodeJson(bytes.size))
        val failure = assertThrows(CanonicalJson.LimitExceeded::class.java) { record.encodeJson(bytes.size - 1) }
        assertEquals(CanonicalJson.Limit.OUTPUT, failure.limit)
    }

    private fun decode(input: String): RecordProvenance {
        val bytes = input.encodeToByteArray()
        return RecordProvenance.decodeJson(bytes, bytes.size)
    }

    private fun assertRefused(input: String) {
        assertThrows(IllegalArgumentException::class.java, { decode(input) }, input)
    }
}
