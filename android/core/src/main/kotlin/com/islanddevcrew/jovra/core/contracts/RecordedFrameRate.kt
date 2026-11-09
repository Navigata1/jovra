package com.islanddevcrew.jovra.core.contracts

import com.islanddevcrew.jovra.core.json.CanonicalJson
import com.islanddevcrew.jovra.core.json.requireStrictLong
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** The persisted nominal frame-rate pair in common.schema.json. */
data class RecordedFrameRate(val num: Long, val den: Long) {
    init {
        require(num > 0 && den > 0) { "Recorded frame-rate terms must be positive" }
    }

    fun encodeJson(): ByteArray {
        val fields = buildJsonObject {
            put("num", num)
            put("den", den)
        }
        return CanonicalJson.canonicalize(fields.toString().encodeToByteArray())
    }

    companion object {
        private val fieldNames = setOf("num", "den")

        /** Reads the original integer terms within a caller-defined UTF-8 input limit. */
        fun decodeJson(bytes: ByteArray, maxInputBytes: Int): RecordedFrameRate {
            val input = CanonicalJson.decodeJsonInput(bytes, maxInputBytes)
            CanonicalJson.validateFlatObject(input)
            val fields = Json.parseToJsonElement(input) as JsonObject
            require(fields.keys == fieldNames) { "Expected exactly num and den in recorded frame rate" }
            return RecordedFrameRate(fields["num"].requireStrictLong(), fields["den"].requireStrictLong())
        }
    }
}
