package com.islanddevcrew.jovra.core.contracts

import com.islanddevcrew.jovra.core.json.CanonicalJson
import java.nio.file.Path
import kotlin.io.path.readText
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.DynamicTest.dynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory

class RecordFileReferenceTest {
    @TestFactory
    fun `actual recording consent and export file references round-trip`(): List<DynamicTest> {
        val root = Path.of(checkNotNull(System.getProperty("jovra.repoRoot")))
        val file = root.resolve("spec/fixtures/records/session.all-fields.json")
        val session = Json.parseToJsonElement(file.readText()).jsonObject
        val segment = session.getValue("recording").jsonObject.getValue("segments").jsonArray.single().jsonObject
        val consent = session.getValue("consent").jsonObject.getValue("writtenConsents").jsonArray.single().jsonObject
        val export = session.getValue("exports").jsonArray.mapNotNull { it.jsonObject["file"] }.single()

        return listOf("recording" to segment.getValue("file"), "consent" to consent.getValue("attachment"), "export" to export)
            .map { (name, raw) ->
                dynamicTest(name) {
                    val input = raw.toString()
                    val reference = decode(input)
                    assertEquals(raw.jsonObject.getValue("path").jsonPrimitive.content, reference.path.value)
                    assertEquals(raw.jsonObject["mimeType"]?.jsonPrimitive?.content, reference.mimeType)
                    assertNull(reference.bytes)
                    assertNull(reference.sha256)
                    assertNull(reference.md5)
                    assertArrayEquals(CanonicalJson.canonicalize(input.encodeToByteArray()), reference.encodeJson())
                }
            }
    }

    @Test
    fun `optional metadata remains exact and absent fields stay absent`() {
        val pathOnly = decode("""{"path":"media/a.mp4"}""")
        assertEquals(RecordFileReference(RecordRelativePath("media/a.mp4")), pathOnly)
        assertArrayEquals("""{"path":"media/a.mp4"}""".encodeToByteArray(), pathOnly.encodeJson())

        val sha = "a".repeat(64)
        val md5 = "f".repeat(32)
        val exact = decode("""{"path":"media/a.mp4","mimeType":"video/x-test+mp4","bytes":9223372036854775807,"sha256":"$sha","md5":"$md5"}""")
        assertEquals(RecordFileReference(RecordRelativePath("media/a.mp4"), "video/x-test+mp4", Long.MAX_VALUE, sha, md5), exact)
        val expected = """{"bytes":9223372036854775807,"md5":"$md5","mimeType":"video/x-test+mp4","path":"media/a.mp4","sha256":"$sha"}"""
        assertArrayEquals(expected.encodeToByteArray(), exact.encodeJson())
        assertEquals(0L, decode("""{"path":"media/a.mp4","bytes":0}""").bytes)
    }

    @Test
    fun `shared path text preserves spelling within its lexical boundary`() {
        for (path in listOf(".", "media/", "media//a.mp4", "media/./a (1).mp4", " media/a.mp4 ", "a".repeat(255))) {
            val raw = Json.encodeToString(path)
            val record = decode("""{"path":$raw}""")
            assertEquals(path, record.path.value)
            assertEquals(path, RecordRelativePath(path).value)
            assertArrayEquals("""{"path":$raw}""".encodeToByteArray(), record.encodeJson())
        }
        for (path in listOf(
            "media/../a.mp4", "../a.mp4", "media/a..mp4", "/media/a.mp4", "//media/a.mp4",
            "media\\a.mp4", "C:/a.mp4", "media/%2e%2e/a.mp4", "media/a\n", "media/a\r",
            "media/a\r\n", "media/🎾.mp4", "a".repeat(256), "",
        )) {
            assertThrows(IllegalArgumentException::class.java, { RecordRelativePath(path) }, path)
            val raw = Json.encodeToString(path)
            assertRefused("""{"path":$raw}""")
        }
    }

    @Test
    fun `mime and digest fields enforce their wire spelling only`() {
        val reference = decode("""{"path":"media/a.mp4","mimeType":"video/mp4"}""")
        for (value in listOf("Video/mp4", "video/MP4", "video/mp4; charset=utf8", "/mp4", "video/", "video/mp4\n")) {
            val raw = Json.encodeToString(value)
            assertRefused("""{"path":"media/a.mp4","mimeType":$raw}""")
        }
        for ((field, length) in listOf("sha256" to 64, "md5" to 32)) {
            for (value in listOf("a".repeat(length - 1), "a".repeat(length + 1), "A".repeat(length),
                                 "g".repeat(length), "a".repeat(length) + "\n")) {
                val raw = Json.encodeToString(value)
                assertRefused("""{"path":"media/a.mp4","$field":$raw}""")
            }
        }
        assertThrows(IllegalArgumentException::class.java) { reference.copy(mimeType = "Video/mp4") }
        assertThrows(IllegalArgumentException::class.java) { reference.copy(sha256 = "invalid") }
        assertThrows(IllegalArgumentException::class.java) { reference.copy(md5 = "invalid") }
    }

    @Test
    fun `bytes must be a nonnegative raw signed 64 bit integer`() {
        val exact = decode("""{"path":"media/a.mp4","bytes":9007199254740993}""")
        assertEquals(9007199254740993L, exact.bytes)
        for (token in listOf("744.0", "744e0", "\"744\"", "true", "null", "-1", "9223372036854775808")) {
            assertRefused("""{"path":"media/a.mp4","bytes":$token}""")
        }
        assertThrows(IllegalArgumentException::class.java) { exact.copy(bytes = -1) }
    }

    @Test
    fun `closed file references refuse malformed input and explicit nulls`() {
        for (input in listOf(
            """{}""", """{"path":42}""", """{"path":null}""", """{"path":"a","unknown":true}""",
            """{"path":"a","path":"a"}""", """{"path":"a","\u0070ath":"b"}""",
            """{"path":"a","bytes":1,"bytes":2}""", """{"path":"a" "bytes":1}""", """{"path":"a",}""",
            """{"path":"a","mimeType":null}""", """{"path":"a","sha256":null}""", """{"path":"a","md5":null}""",
            """{"path":"a","bytes":[]}""", """["a"]""", """{"path":"a"} null""",
        )) {
            assertRefused(input)
        }
    }

    @Test
    fun `caller input byte cap applies before UTF-8 decoding`() {
        val input = """{"path":"media/a.mp4"}""".encodeToByteArray()
        assertEquals("media/a.mp4", RecordFileReference.decodeJson(input, input.size).path.value)
        val failure = assertThrows(CanonicalJson.LimitExceeded::class.java) {
            RecordFileReference.decodeJson(input, input.size - 1)
        }
        assertEquals(CanonicalJson.Limit.INPUT, failure.limit)
        assertEquals(input.size - 1, failure.maxBytes)
        val invalid = byteArrayOf(0xc0.toByte(), 0xaf.toByte())
        assertThrows(CanonicalJson.LimitExceeded::class.java) { RecordFileReference.decodeJson(invalid, 1) }
        assertThrows(IllegalArgumentException::class.java) { RecordFileReference.decodeJson(invalid, 2) }
    }

    private fun decode(input: String): RecordFileReference {
        val bytes = input.encodeToByteArray()
        return RecordFileReference.decodeJson(bytes, bytes.size)
    }

    private fun assertRefused(input: String) {
        assertThrows(IllegalArgumentException::class.java, { decode(input) }, input)
    }
}
