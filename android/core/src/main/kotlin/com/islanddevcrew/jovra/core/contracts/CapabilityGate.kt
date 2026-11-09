package com.islanddevcrew.jovra.core.contracts

import com.islanddevcrew.jovra.core.json.CanonicalJson
import com.islanddevcrew.jovra.core.json.optionalString
import com.islanddevcrew.jovra.core.json.requireString
import java.util.Collections
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** A stored capability gate and its exact benchmark threshold text. */
class CapabilityGate(
    val promotesTo: Target,
    thresholds: List<Threshold>,
    val minimumData: String,
) {
    enum class Target(val wireName: String) {
        ESTIMATED("estimated"), VALIDATED("validated"),
    }

    enum class Comparator(val wireName: String) {
        AT_LEAST(">="), AT_MOST("<="),
    }

    data class Threshold(
        val name: String,
        val comparator: Comparator,
        val threshold: String,
        val unit: String? = null,
    ) {
        init {
            requireScalarLength(name, 1..80, "Threshold name")
            require(decimalText.matches(threshold)) { "Expected exact decimal threshold text" }
            unit?.let { requireScalarLength(it, 0..16, "Threshold unit") }
        }
    }

    val thresholds: List<Threshold> = Collections.unmodifiableList(ArrayList(thresholds))

    init {
        require(this.thresholds.isNotEmpty()) { "Expected at least one capability threshold" }
        requireScalarLength(minimumData, 1..300, "Minimum data")
    }

    /** Writes canonical gate metadata under the caller's aggregate output byte limit. */
    fun encodeJson(maxOutputBytes: Int): ByteArray {
        require(maxOutputBytes >= 0) { "Capability gate output limit must be non-negative" }
        requireOutputBudget(maxOutputBytes)
        val fields = buildJsonObject {
            put("promotesTo", promotesTo.wireName)
            put("minimumData", minimumData)
            put("metrics", JsonArray(thresholds.map { item ->
                buildJsonObject {
                    put("name", item.name)
                    put("comparator", item.comparator.wireName)
                    put("threshold", item.threshold)
                    item.unit?.let { put("unit", it) }
                }
            }))
        }
        val input = fields.toString().encodeToByteArray()
        return CanonicalJson.canonicalize(input, CanonicalJson.Limits(input.size, maxOutputBytes))
    }

    private fun requireOutputBudget(maxOutputBytes: Int) {
        // Structure and UTF-16 lengths are a lower bound on canonical UTF-8 bytes. This
        // catches large aggregate arrays and exact ASCII thresholds before assembling JSON.
        var minimumBytes = MIN_GATE_BYTES + minimumData.length.toLong() + promotesTo.wireName.length
        for ((index, item) in thresholds.withIndex()) {
            if (index > 0) minimumBytes++
            minimumBytes += MIN_THRESHOLD_BYTES + item.name.length.toLong() +
                item.comparator.wireName.length + item.threshold.length
            item.unit?.let { minimumBytes += MIN_UNIT_BYTES + it.length }
            if (minimumBytes > maxOutputBytes) {
                throw CanonicalJson.LimitExceeded(CanonicalJson.Limit.OUTPUT, maxOutputBytes)
            }
        }
    }

    companion object {
        private const val WIRE_DEPTH = 4 // Gate, threshold array, threshold object, scalar.
        private val MIN_GATE_BYTES = """{"metrics":[],"minimumData":"","promotesTo":""}""".length
        private val MIN_THRESHOLD_BYTES = """{"name":"","comparator":"","threshold":""}""".length
        private val MIN_UNIT_BYTES = ",\"unit\":\"\"".length
        private val gateFields = setOf("promotesTo", "metrics", "minimumData")
        private val thresholdFields = setOf("name", "comparator", "threshold", "unit")
        private val decimalText = Regex("[0-9]+(?:\\.[0-9]+)?")

        /** Reads one non-null gate from original JSON under the caller's input byte limit. */
        fun decodeJson(bytes: ByteArray, maxInputBytes: Int): CapabilityGate {
            val input = CanonicalJson.decodeJsonInput(bytes, maxInputBytes)
            CanonicalJson.validateObject(input, WIRE_DEPTH)
            val fields = Json.parseToJsonElement(input) as JsonObject
            require(fields.keys == gateFields) { "Expected exactly promotesTo, metrics and minimumData" }
            val target = fields.requireString("promotesTo")
            val metrics = fields["metrics"] as? JsonArray
            require(metrics != null && metrics.isNotEmpty()) { "Expected a nonempty capability threshold array" }
            return CapabilityGate(
                promotesTo = requireNotNull(Target.entries.firstOrNull { it.wireName == target }) {
                    "Unknown capability gate target"
                },
                thresholds = metrics.map { metric ->
                    require(metric is JsonObject && metric.keys.all { it in thresholdFields }) {
                        "Expected a closed capability threshold object"
                    }
                    val comparator = metric.requireString("comparator")
                    Threshold(
                        name = metric.requireString("name"),
                        comparator = requireNotNull(Comparator.entries.firstOrNull { it.wireName == comparator }) {
                            "Unknown capability threshold comparator"
                        },
                        threshold = metric.requireString("threshold"),
                        unit = metric.optionalString("unit"),
                    )
                },
                minimumData = fields.requireString("minimumData"),
            )
        }

        private fun requireScalarLength(value: String, length: IntRange, field: String) {
            CanonicalJson.requireValidScalars(value)
            require(value.codePointCount(0, value.length) in length) { "$field has invalid Unicode scalar length" }
        }
    }
}
