package com.islanddevcrew.jovra.core.contracts

import com.islanddevcrew.jovra.core.json.CanonicalJson
import com.islanddevcrew.jovra.core.pct.RateRatio
import java.nio.file.Path
import kotlin.io.path.readText
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.DynamicTest.dynamicTest
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
}
