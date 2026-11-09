package com.islanddevcrew.jovra.core.pct

import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class RateRatioWireTest {
    @Test
    fun `half-up rates and undefined rates round-trip exact canonical wire bytes`() {
        val examples = listOf(
            RateRatio(1, 8) to """{"d":8,"display":"13%","n":1,"pct":13}""",
            RateRatio(0, 0) to """{"d":0,"display":"—","n":0,"pct":null}""",
        )
        for ((expected, wire) in examples) {
            val bytes = wire.encodeToByteArray()
            assertEquals(expected, RateRatio.decodeJson(bytes, bytes.size))
            assertArrayEquals(bytes, expected.encodeJson(bytes.size))
        }
    }
}
