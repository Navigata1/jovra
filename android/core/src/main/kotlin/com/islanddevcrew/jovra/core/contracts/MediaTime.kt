package com.islanddevcrew.jovra.core.contracts

import com.islanddevcrew.jovra.core.json.CanonicalJson
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.descriptors.element
import kotlinx.serialization.encoding.CompositeDecoder
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.encoding.decodeStructure
import kotlinx.serialization.encoding.encodeStructure
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonPrimitive

/**
 * Exact rational time on the session timeline (common.schema.json, mediaTime).
 * The schema gives timescale a minimum but no maximum. The portable type uses the positive
 * signed 32-bit range accepted by Swift MediaTime; the value remains signed 64-bit.
 */
data class MediaTime(val value: Long, val timescale: Int) {
    init {
        require(value >= 0) { "Media time value must be non-negative" }
        require(timescale > 0) { "Media time timescale must be positive" }
    }

    fun encodeJson(): ByteArray =
        CanonicalJson.canonicalize(Json.encodeToString(MediaTimeSerializer, this).encodeToByteArray())

    companion object {
        /** Decodes the original integer tokens within an explicit caller input limit. */
        fun decodeJson(bytes: ByteArray, maxInputBytes: Int): MediaTime {
            val input = CanonicalJson.decodeJsonInput(bytes, maxInputBytes)
            CanonicalJson.validateFlatObject(input)
            return Json.decodeFromString(MediaTimeSerializer, input)
        }
    }
}

private object MediaTimeSerializer : KSerializer<MediaTime> {
    override val descriptor = buildClassSerialDescriptor("MediaTime") {
        element("value", StrictLong.descriptor)
        element("timescale", StrictLong.descriptor)
    }

    override fun deserialize(decoder: Decoder): MediaTime = decoder.decodeStructure(descriptor) {
        var value: Long? = null
        var timescale: Long? = null
        while (true) {
            when (val index = decodeElementIndex(descriptor)) {
                CompositeDecoder.DECODE_DONE -> break
                0 -> {
                    require(value == null) { "Duplicate media time value" }
                    value = decodeSerializableElement(descriptor, index, StrictLong)
                }
                1 -> {
                    require(timescale == null) { "Duplicate media time timescale" }
                    timescale = decodeSerializableElement(descriptor, index, StrictLong)
                }
                else -> throw SerializationException("Unknown media time field")
            }
        }
        val scale = requireNotNull(timescale) { "Missing media time timescale" }
        require(scale in 1..Int.MAX_VALUE.toLong()) { "Media time timescale exceeds the portable range" }
        MediaTime(requireNotNull(value) { "Missing media time value" }, scale.toInt())
    }

    override fun serialize(encoder: Encoder, value: MediaTime) = encoder.encodeStructure(descriptor) {
        encodeLongElement(descriptor, 0, value.value)
        encodeLongElement(descriptor, 1, value.timescale.toLong())
    }
}

private object StrictLong : KSerializer<Long> {
    override val descriptor = PrimitiveSerialDescriptor("StrictJsonLong", PrimitiveKind.LONG)
    private val integer = Regex("-?(0|[1-9][0-9]*)")

    override fun deserialize(decoder: Decoder): Long {
        // Read the scalar from the original stream. Canonical output can erase its decimal or exponent form.
        val scalar = (decoder as JsonDecoder).decodeJsonElement() as? JsonPrimitive
        require(scalar != null && !scalar.isString && integer.matches(scalar.content)) {
            "Expected a JSON integer token"
        }
        return requireNotNull(scalar.content.toLongOrNull()) { "JSON integer exceeds signed 64-bit range" }
    }

    override fun serialize(encoder: Encoder, value: Long) = encoder.encodeLong(value)
}
