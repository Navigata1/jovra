package com.islanddevcrew.jovra.core.pct

import com.islanddevcrew.jovra.core.json.CanonicalJson
import com.islanddevcrew.jovra.core.json.requireStrictLong
import com.islanddevcrew.jovra.core.json.requireString
import kotlin.math.abs
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Whole percentages use the shared half-up rule from ADR-0011. */
object Percent {
    fun pct(n: Long, d: Long): Int? {
        require(n in 0..d) { "Expected 0 <= numerator <= denominator" }
        if (d == 0L) return null

        val quotient = d / 200
        val remainder = d % 200
        var low = 0
        var high = 100
        while (low < high) {
            val candidate = (low + high + 1) / 2
            val multiplier = 2 * candidate - 1
            // The half-up rule reaches p at n >= ceil((2p - 1) * d / 200).
            // Split d by 200 so neither product overflows a signed Long.
            val threshold = quotient * multiplier + (remainder * multiplier + 199) / 200
            if (n >= threshold) {
                low = candidate
            } else {
                high = candidate - 1
            }
        }
        return low
    }

    fun pool(parts: Iterable<RateRatio>): RateRatio {
        var numerator = 0L
        var denominator = 0L
        for (part in parts) {
            numerator = Math.addExact(numerator, part.n)
            denominator = Math.addExact(denominator, part.d)
        }
        return RateRatio(numerator, denominator)
    }

    fun delta(current: RateRatio, prior: RateRatio): String {
        val currentPercent = current.pct ?: return "—"
        val priorPercent = prior.pct ?: return "—"
        val difference = currentPercent - priorPercent
        val sign = if (difference > 0) "+" else ""
        val unit = if (abs(difference) == 1) "percentage point" else "percentage points"
        return "$sign$difference $unit"
    }
}

/** A displayed rate with exact counts and half-up percentage (common.schema.json, ratio). */
data class RateRatio(val n: Long, val d: Long) {
    val pct: Int? = Percent.pct(n, d)
    val display: String get() = pct?.let { "$it%" } ?: "—"

    /** Encodes the canonical, locale-independent wire display within the caller's output limit. */
    fun encodeJson(maxOutputBytes: Int): ByteArray {
        val input = toJsonObject().toString().encodeToByteArray()
        return CanonicalJson.canonicalize(input, CanonicalJson.Limits(input.size, maxOutputBytes))
    }

    internal fun toJsonObject(): JsonObject = buildJsonObject {
        put("n", n)
        put("d", d)
        put("pct", pct?.let(::JsonPrimitive) ?: JsonNull)
        put("display", display)
    }

    companion object {
        private val wireFields = setOf("n", "d", "pct", "display")

        /** Validates the original integer tokens and the required fields derived from the counts. */
        fun decodeJson(bytes: ByteArray, maxInputBytes: Int): RateRatio {
            val input = CanonicalJson.decodeJsonInput(bytes, maxInputBytes)
            CanonicalJson.validateFlatObject(input)
            return fromJsonObject(Json.parseToJsonElement(input) as JsonObject)
        }

        internal fun fromJsonObject(fields: JsonObject): RateRatio {
            require(fields.keys == wireFields) { "Expected exactly n, d, pct and display" }
            val ratio = RateRatio(fields["n"].requireStrictLong(), fields["d"].requireStrictLong())
            val percentToken = fields.getValue("pct")
            val percent = if (percentToken == JsonNull) null else percentToken.requireStrictLong()
            require(percent == ratio.pct?.toLong()) { "Rate percentage does not match the counts" }
            require(fields.requireString("display") == ratio.display) { "Rate display does not match the counts" }
            return ratio
        }
    }
}
