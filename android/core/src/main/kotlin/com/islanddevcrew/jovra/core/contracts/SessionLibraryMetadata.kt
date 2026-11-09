package com.islanddevcrew.jovra.core.contracts

import com.islanddevcrew.jovra.core.json.CanonicalJson
import com.islanddevcrew.jovra.core.json.requireBoolean
import com.islanddevcrew.jovra.core.json.requireStrictLong
import com.islanddevcrew.jovra.core.json.requireString
import java.util.Collections
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Read-only projection for a Library summary, with selected metadata from session schema 1.0–1.2.
 * Known unprojected sections are opaque. Their JSON grammar and duplicate keys are checked, but
 * their schema and references are unvalidated. This is not document admission or migration.
 */
class SessionLibraryMetadata private constructor(
    val schemaVersion: String,
    val id: OpaqueId,
    val title: String,
    val sessionKind: Kind,
    val createdAt: String,
    val updatedAt: String,
    val players: List<SessionPlayer>,
    val sample: Sample?,
    val recording: Recording,
    val storedOriginals: Originals,
    val includeInDeviceBackup: Boolean,
    val storedArchiveState: ArchiveState,
) {
    enum class Kind(val wireName: String) {
        MATCH("match"), TIEBREAK_ONLY("tiebreakOnly"), PRACTICE_SET("practiceSet"),
        SERVE_PRACTICE("servePractice"), STROKE_PRACTICE("strokePractice"), RALLY("rally"),
        LESSON("lesson"), DRILL("drill"),
    }

    enum class RecordingMode(val wireName: String) {
        CAMERA("camera"), IMPORT("import"), SIMULATOR_FIXTURE("simulatorFixture"), NONE("none"),
    }

    enum class Originals(val wireName: String) {
        ON_DEVICE("onDevice"), ARCHIVED_ONLY("archivedOnly"), REMOVED("removed"), NONE("none"),
    }

    enum class ArchiveState(val wireName: String) {
        LOCAL_ONLY("localOnly"), AWAITING_SETUP("awaitingSetup"), QUEUED("queued"),
        WAITING_FOR_WIFI("waitingForWiFi"), HASHING("hashing"), UPLOADING("uploading"),
        VERIFYING("verifying"), BACKED_UP("backedUp"), FAILED("failed"),
        NEEDS_RECONNECT("needsReconnect"), QUOTA_BLOCKED("quotaBlocked"),
    }

    data class Sample(val synthetic: Boolean, val generator: String, val mediaIds: List<OpaqueId>?)

    /** `mediaAvailable` is stored metadata. No file or playback probe was performed. */
    data class Recording(val mode: RecordingMode, val durationMs: Long?, val mediaAvailable: Boolean)

    companion object {
        private const val WIRE_DEPTH = 16 // Projection resource budget, including opaque sections.
        private val supportedVersion = Regex("1\\.[012]\\.[0-9]+")
        private val utcTimestamp = Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,3})?Z")
        private val required = setOf(
            "schemaVersion", "kind", "id", "sport", "createdAt", "updatedAt", "title", "sessionKind",
            "players", "recording", "storage", "archive",
        )
        private val known = required + setOf(
            "sample", "capturePurpose", "sides", "match", "marks", "shots", "calibrations", "annotations",
            "voiceNotes", "comparisons", "derivedValues", "analysis", "review", "equipmentUse", "consent",
            "notes", "rallyPlayback", "serveMarks", "swings", "exports", "original",
        )
        private val matchKinds = setOf(Kind.MATCH, Kind.TIEBREAK_ONLY, Kind.PRACTICE_SET)
        private val recordingFields = setOf(
            "mode", "importSource", "startedAt", "timeZone", "durationMs", "segments", "gaps", "microphone",
            "mediaAvailable", "device", "captureEvents", "recovery",
        )
        private val archiveFields = setOf("state", "copy", "restoredAt", "provider", "manifest", "backedUpAt", "lastError")
        private val storageFields = setOf("originals", "includeInDeviceBackup", "removeAfterVerifiedBackup")
        private val sampleFields = setOf("label", "synthetic", "generator", "mediaIds")

        /** Reads only selected metadata from the original JSON under explicit byte and fixed depth limits. */
        fun decodeJson(bytes: ByteArray, maxInputBytes: Int): SessionLibraryMetadata {
            val input = CanonicalJson.decodeJsonInput(bytes, maxInputBytes)
            CanonicalJson.validateObject(input, WIRE_DEPTH)
            val fields = Json.parseToJsonElement(input) as JsonObject
            require(fields.keys.containsAll(required) && fields.keys.all { it in known }) { "Invalid session root fields" }
            require(fields.requireString("kind") == "jovra.session" && fields.requireString("sport") == "tennis") {
                "Expected a JOVRA tennis session"
            }
            val version = fields.requireString("schemaVersion")
            require(supportedVersion.matches(version)) { "Unsupported session projection version" }
            val kind = fields.wireValue("sessionKind", Kind.entries, Kind::wireName)
            if (kind in matchKinds) {
                require(fields["sides"] is JsonObject && fields["match"] is JsonObject) { "Expected match and sides objects" }
            }
            val players = fields["players"] as? JsonArray
            require(players != null && players.size in 1..4) { "Expected one to four session players" }
            val storage = fields.closedObject("storage", storageFields)
            val archive = fields.closedObject("archive", archiveFields)
            val archiveState = archive.wireValue("state", ArchiveState.entries, ArchiveState::wireName)
            require(!version.startsWith("1.0.") || archiveState != ArchiveState.WAITING_FOR_WIFI) {
                "Waiting for Wi-Fi requires session schema 1.1 or later"
            }
            return SessionLibraryMetadata(
                schemaVersion = version,
                id = OpaqueId(fields.requireString("id")),
                title = fields.requireText("title", 120),
                sessionKind = kind,
                createdAt = fields.requireTimestamp("createdAt"),
                updatedAt = fields.requireTimestamp("updatedAt"),
                players = Collections.unmodifiableList(players.map { player ->
                    SessionPlayer.fromJsonObject(requireNotNull(player as? JsonObject) { "Expected a player object" })
                }),
                sample = if ("sample" in fields) decodeSample(fields.closedObject("sample", sampleFields), version) else null,
                recording = decodeRecording(fields.closedObject("recording", recordingFields)),
                storedOriginals = storage.wireValue("originals", Originals.entries, Originals::wireName),
                includeInDeviceBackup = storage.requireBoolean("includeInDeviceBackup"),
                storedArchiveState = archiveState,
            )
        }

        private fun decodeSample(fields: JsonObject, version: String): Sample {
            require(fields.requireString("label") == "Sample") { "Invalid Sample label" }
            val mediaIds = fields["mediaIds"]?.let { raw ->
                require(!version.startsWith("1.0.") && raw is JsonArray && raw.size in 1..8) { "Invalid Sample media IDs" }
                val ids = raw.map { id ->
                    require(id is JsonPrimitive && id.isString) { "Expected a Sample media ID string" }
                    OpaqueId(id.content)
                }
                require(ids.toSet().size == ids.size) { "Duplicate Sample media ID" }
                Collections.unmodifiableList(ids)
            }
            return Sample(fields.requireBoolean("synthetic"), fields.requireText("generator", 120), mediaIds)
        }

        private fun decodeRecording(fields: JsonObject): Recording {
            require(fields["segments"] is JsonArray && fields["gaps"] is JsonArray && "microphone" in fields) {
                "Expected recording segment and gap arrays and microphone metadata"
            }
            val duration = fields["durationMs"]?.requireStrictLong()
            require(duration == null || duration >= 0) { "Recording duration must be non-negative" }
            return Recording(
                fields.wireValue("mode", RecordingMode.entries, RecordingMode::wireName),
                duration,
                fields.requireBoolean("mediaAvailable"),
            )
        }

        private fun JsonObject.closedObject(name: String, allowed: Set<String>): JsonObject {
            val value = this[name] as? JsonObject
            require(value != null && value.keys.all { it in allowed }) { "Invalid session $name object" }
            return value
        }

        private fun JsonObject.requireTimestamp(name: String): String = requireString(name).also {
            require(utcTimestamp.matches(it)) { "Expected UTC timestamp spelling for $name" }
        }

        private fun JsonObject.requireText(name: String, maxScalars: Int): String = requireString(name).also {
            // Original grammar admission already rejected lone surrogates.
            require(it.codePointCount(0, it.length) in 1..maxScalars) { "Invalid session text length for $name" }
        }

        private fun <T> JsonObject.wireValue(name: String, values: List<T>, wireName: (T) -> String): T {
            val value = requireString(name)
            return requireNotNull(values.firstOrNull { wireName(it) == value }) { "Unknown session $name" }
        }
    }
}
