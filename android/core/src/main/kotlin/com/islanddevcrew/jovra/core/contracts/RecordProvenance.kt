package com.islanddevcrew.jovra.core.contracts

import com.islanddevcrew.jovra.core.json.CanonicalJson
import com.islanddevcrew.jovra.core.json.optionalString
import com.islanddevcrew.jovra.core.json.requireBoolean
import com.islanddevcrew.jovra.core.json.requireStrictLong
import com.islanddevcrew.jovra.core.json.requireString
import java.math.BigDecimal
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Stored provenance metadata from common.schema.json, independent of capability promotion.
 * Confidence keeps exact JVM decimal values, including some the Swift Decimal codec cannot represent.
 */
data class RecordProvenance(
    val status: Status,
    val source: String,
    val capabilityId: String? = null,
    val capabilityVersion: String? = null,
    val confidence: BigDecimal? = null,
    val calibrationId: OpaqueId? = null,
    val denominator: Long? = null,
    val computedAt: String? = null,
    val sample: Boolean? = null,
) {
    enum class Status(val wireName: String) {
        MANUAL("manual"), ESTIMATED("estimated"), REVIEWED("reviewed"), VALIDATED("validated"),
    }

    init {
        require(sourcePattern.matches(source)) { "Invalid provenance source" }
        require(capabilityId == null || capabilityPattern.matches(capabilityId)) { "Invalid capability ID" }
        if (capabilityVersion != null) {
            CanonicalJson.requireValidScalars(capabilityVersion)
            require(capabilityVersion.codePointCount(0, capabilityVersion.length) in 1..64) {
                "Capability version must contain 1 to 64 Unicode scalars"
            }
        }
        require(confidence == null || (confidence.signum() >= 0 && confidence <= BigDecimal.ONE)) {
            "Confidence must be between zero and one"
        }
        require(denominator == null || denominator >= 0) { "Provenance denominator must be non-negative" }
        require(computedAt == null || dateTimePattern.matches(computedAt)) { "Invalid provenance timestamp spelling" }
    }

    // BigDecimal equality includes scale, while provenance confidence has numeric value semantics.
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        return other is RecordProvenance &&
            status == other.status && source == other.source && capabilityId == other.capabilityId &&
            capabilityVersion == other.capabilityVersion &&
            confidence?.stripTrailingZeros() == other.confidence?.stripTrailingZeros() &&
            calibrationId == other.calibrationId && denominator == other.denominator &&
            computedAt == other.computedAt && sample == other.sample
    }

    override fun hashCode(): Int {
        var result = status.hashCode()
        result = 31 * result + source.hashCode()
        result = 31 * result + capabilityId.hashCode()
        result = 31 * result + capabilityVersion.hashCode()
        result = 31 * result + confidence?.stripTrailingZeros().hashCode()
        result = 31 * result + calibrationId.hashCode()
        result = 31 * result + denominator.hashCode()
        result = 31 * result + computedAt.hashCode()
        result = 31 * result + sample.hashCode()
        return result
    }

    /** Encodes exact confidence text without allocating its expanded decimal beyond the caller limit. */
    fun encodeJson(maxOutputBytes: Int): ByteArray {
        require(maxOutputBytes >= 0) { "Provenance output limit must be non-negative" }
        val input = toJsonObject(maxOutputBytes).toString().encodeToByteArray()
        return CanonicalJson.canonicalize(input, CanonicalJson.Limits(input.size, maxOutputBytes))
    }

    internal fun toJsonObject(maxOutputBytes: Int): JsonObject = buildJsonObject {
        put("status", status.wireName)
        put("source", source)
        capabilityId?.let { put("capabilityId", it) }
        capabilityVersion?.let { put("capabilityVersion", it) }
        confidence?.let { put("confidence", confidenceToken(it, maxOutputBytes)) }
        calibrationId?.let { put("calibrationId", it.value) }
        denominator?.let { put("denominator", it) }
        computedAt?.let { put("computedAt", it) }
        sample?.let { put("sample", it) }
    }

    companion object {
        private val fieldNames = setOf(
            "status", "source", "capabilityId", "capabilityVersion", "confidence",
            "calibrationId", "denominator", "computedAt", "sample",
        )
        private val sourcePattern = Regex("""user|(?:model|rule|sample):[A-Za-z0-9._-]+@[A-Za-z0-9._+-]+|import:[A-Za-z0-9._-]+""")
        // Dots unambiguously separate components, so matching never needs to backtrack across them.
        private val capabilityPattern = Regex("""[a-z][a-zA-Z0-9]*(?:\.[a-z][a-zA-Z0-9]*)*+""")
        private val dateTimePattern = Regex("""[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,3})?Z""")

        /** Reads one provenance record within the caller's UTF-8 input byte limit. */
        fun decodeJson(bytes: ByteArray, maxInputBytes: Int): RecordProvenance {
            val input = CanonicalJson.decodeJsonInput(bytes, maxInputBytes)
            CanonicalJson.validateFlatObject(input)
            return fromJsonObject(Json.parseToJsonElement(input) as JsonObject)
        }

        internal fun fromJsonObject(fields: JsonObject): RecordProvenance {
            require(fields.keys.all { it in fieldNames }) { "Unknown provenance field" }
            val status = fields.requireString("status")
            return RecordProvenance(
                status = requireNotNull(Status.entries.firstOrNull { it.wireName == status }) {
                    "Unknown provenance status"
                },
                source = fields.requireString("source"),
                capabilityId = fields.optionalString("capabilityId"),
                capabilityVersion = fields.optionalString("capabilityVersion"),
                confidence = fields["confidence"]?.let(::parseConfidence),
                calibrationId = fields.optionalString("calibrationId")?.let(::OpaqueId),
                denominator = fields["denominator"]?.requireStrictLong(),
                computedAt = fields.optionalString("computedAt"),
                sample = if ("sample" in fields) fields.requireBoolean("sample") else null,
            )
        }

        private fun parseConfidence(element: JsonElement): BigDecimal {
            val token = element as? JsonPrimitive
            require(token != null && !token.isString) { "Expected a JSON confidence number" }
            return requireNotNull(token.content.toBigDecimalOrNull()) { "Expected a JSON confidence number" }
                .stripTrailingZeros()
        }

        private fun confidenceToken(value: BigDecimal, maxOutputBytes: Int): JsonElement {
            val normalized = value.stripTrailingZeros()
            // For a fraction between zero and one, plain text has "0." and exactly scale fractional digits.
            val length = if (normalized.scale() == 0) 1L else 2L + normalized.scale()
            if (length > maxOutputBytes) throw CanonicalJson.LimitExceeded(CanonicalJson.Limit.OUTPUT, maxOutputBytes)
            return Json.parseToJsonElement(normalized.toPlainString())
        }
    }
}
