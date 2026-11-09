package com.islanddevcrew.jovra.core.contracts

import com.islanddevcrew.jovra.core.json.CanonicalJson
import com.islanddevcrew.jovra.core.json.optionalString
import com.islanddevcrew.jovra.core.json.requireBoolean
import com.islanddevcrew.jovra.core.json.requireString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Shared common.schema.json ID. Its case and spelling carry identity. */
@JvmInline
value class OpaqueId(val value: String) {
    init {
        require(pattern.matches(value)) { "Invalid opaque ID" }
    }

    private companion object {
        val pattern = Regex("[A-Za-z0-9][A-Za-z0-9._:-]{0,63}")
    }
}

/** One complete player record as defined by session.schema.json. */
data class SessionPlayer(
    val id: OpaqueId,
    val displayName: String,
    val handedness: Handedness,
    val backhand: Backhand,
    val isSelf: Boolean,
    val level: String? = null,
    val profileId: OpaqueId? = null,
) {
    enum class Handedness(val wireName: String) { RIGHT("right"), LEFT("left"), UNKNOWN("unknown") }
    enum class Backhand(val wireName: String) { ONE_HANDED("oneHanded"), TWO_HANDED("twoHanded"), UNKNOWN("unknown") }

    init {
        CanonicalJson.requireValidScalars(displayName)
        require(displayName.codePointCount(0, displayName.length) in 1..60) {
            "Player display name must contain 1 to 60 Unicode scalars"
        }
        if (level != null) {
            CanonicalJson.requireValidScalars(level)
            require(level.codePointCount(0, level.length) <= 40) { "Player level exceeds 40 Unicode scalars" }
        }
    }

    fun encodeJson(): ByteArray {
        val fields = buildJsonObject {
            put("id", id.value)
            put("displayName", displayName)
            put("handedness", handedness.wireName)
            put("backhand", backhand.wireName)
            put("isSelf", isSelf)
            level?.let { put("level", it) }
            profileId?.let { put("profileId", it.value) }
        }
        return CanonicalJson.canonicalize(fields.toString().encodeToByteArray())
    }

    companion object {
        private val fieldNames = setOf("id", "displayName", "handedness", "backhand", "isSelf", "level", "profileId")

        /** Decodes an individual player from UTF-8 bytes within the supplied input limit. */
        fun decodeJson(bytes: ByteArray, maxInputBytes: Int): SessionPlayer {
            val input = CanonicalJson.decodeJsonInput(bytes, maxInputBytes)
            CanonicalJson.validateFlatObject(input)
            val fields = Json.parseToJsonElement(input) as JsonObject
            require(fields.keys.all { it in fieldNames }) { "Unknown player field" }

            val hand = fields.requireString("handedness")
            val backhand = fields.requireString("backhand")
            return SessionPlayer(
                id = OpaqueId(fields.requireString("id")),
                displayName = fields.requireString("displayName"),
                handedness = requireNotNull(Handedness.entries.firstOrNull { it.wireName == hand }) {
                    "Unknown player handedness"
                },
                backhand = requireNotNull(Backhand.entries.firstOrNull { it.wireName == backhand }) {
                    "Unknown player backhand"
                },
                isSelf = fields.requireBoolean("isSelf"),
                level = fields.optionalString("level"),
                profileId = fields.optionalString("profileId")?.let(::OpaqueId),
            )
        }
    }
}
