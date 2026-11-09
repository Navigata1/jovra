package com.islanddevcrew.jovra.core.contracts

import com.islanddevcrew.jovra.core.json.CanonicalJson
import com.islanddevcrew.jovra.core.json.optionalString
import com.islanddevcrew.jovra.core.json.requireString
import com.islanddevcrew.jovra.core.pct.RateRatio
import java.util.Collections
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Stored evidence for one practice item. Availability and provenance are independent metadata. */
class PracticeEvidence(
    val sessionId: OpaqueId,
    val stat: String,
    val value: RateRatio,
    val provenance: RecordProvenance,
    val availability: Availability,
    val side: Side? = null,
    val text: String? = null,
    pointIds: List<OpaqueId>? = null,
) {
    enum class Availability(val wireName: String) {
        AVAILABLE("available"), VIDEO_UNAVAILABLE("videoUnavailable"), SESSION_DELETED("sessionDeleted"),
    }

    enum class Side { A, B }

    val pointIds: List<OpaqueId>? = pointIds?.let {
        require(it.size <= MAX_POINT_IDS) { "Practice evidence contains too many point IDs" }
        Collections.unmodifiableList(ArrayList(it))
    }

    init {
        CanonicalJson.requireValidScalars(stat)
        require(stat.codePointCount(0, stat.length) in 1..80) { "Practice evidence stat must contain 1 to 80 Unicode scalars" }
        if (text != null) {
            CanonicalJson.requireValidScalars(text)
            require(text.codePointCount(0, text.length) <= 120) { "Practice evidence text exceeds 120 Unicode scalars" }
        }
    }

    /** Encodes the evidence row in canonical JSON under the caller's output byte limit. */
    fun encodeJson(maxOutputBytes: Int): ByteArray {
        require(maxOutputBytes >= 0) { "Practice evidence output limit must be non-negative" }
        val fields = buildJsonObject {
            put("sessionId", sessionId.value)
            put("stat", stat)
            put("value", value.toJsonObject())
            put("provenance", provenance.toJsonObject(maxOutputBytes))
            put("availability", availability.wireName)
            side?.let { put("side", it.name) }
            text?.let { put("text", it) }
            pointIds?.let { put("pointIds", JsonArray(it.map { id -> JsonPrimitive(id.value) })) }
        }
        val input = fields.toString().encodeToByteArray()
        return CanonicalJson.canonicalize(input, CanonicalJson.Limits(input.size, maxOutputBytes))
    }

    companion object {
        private const val MAX_POINT_IDS = 50
        private const val WIRE_DEPTH = 3 // Row, nested object or point IDs array, scalar.
        private val fieldNames = setOf("sessionId", "stat", "value", "provenance", "availability", "side", "text", "pointIds")

        /** Validates original JSON grammar and duplicate keys before reading nested typed values. */
        fun decodeJson(bytes: ByteArray, maxInputBytes: Int): PracticeEvidence {
            val input = CanonicalJson.decodeJsonInput(bytes, maxInputBytes)
            CanonicalJson.validateObject(input, WIRE_DEPTH)
            val fields = Json.parseToJsonElement(input) as JsonObject
            require(fields.keys.all { it in fieldNames }) { "Unknown practice evidence field" }
            val availability = fields.requireString("availability")
            val side = fields.optionalString("side")
            return PracticeEvidence(
                sessionId = OpaqueId(fields.requireString("sessionId")),
                stat = fields.requireString("stat"),
                value = RateRatio.fromJsonObject(requireNotNull(fields["value"] as? JsonObject) { "Expected a rate object" }),
                provenance = RecordProvenance.fromJsonObject(
                    requireNotNull(fields["provenance"] as? JsonObject) { "Expected a provenance object" },
                ),
                availability = requireNotNull(Availability.entries.firstOrNull { it.wireName == availability }) {
                    "Unknown practice evidence availability"
                },
                side = side?.let { Side.valueOf(it) },
                text = fields.optionalString("text"),
                pointIds = fields["pointIds"]?.let(::decodePointIds),
            )
        }

        private fun decodePointIds(element: JsonElement): List<OpaqueId> {
            require(element is JsonArray && element.size <= MAX_POINT_IDS) { "Expected up to 50 point IDs" }
            return element.map { token ->
                require(token is JsonPrimitive && token.isString) { "Expected a point ID string" }
                OpaqueId(token.content)
            }
        }
    }
}
