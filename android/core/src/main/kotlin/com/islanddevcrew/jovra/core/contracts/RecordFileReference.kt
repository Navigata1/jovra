package com.islanddevcrew.jovra.core.contracts

import com.islanddevcrew.jovra.core.json.CanonicalJson
import com.islanddevcrew.jovra.core.json.optionalString
import com.islanddevcrew.jovra.core.json.requireStrictLong
import com.islanddevcrew.jovra.core.json.requireString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Wire spelling of common.relativePath. Filesystem containment is a separate storage check. */
@JvmInline
value class RecordRelativePath(val value: String) {
    init {
        require(!value.startsWith('/') && ".." !in value && pattern.matches(value)) {
            "Invalid relative path metadata"
        }
    }

    private companion object {
        val pattern = Regex("[A-Za-z0-9 ._()/-]{1,255}")
    }
}

/** Shared fileRef metadata. Digest and byte fields describe the record's claims about file content. */
data class RecordFileReference(
    val path: RecordRelativePath,
    val mimeType: String? = null,
    val bytes: Long? = null,
    val sha256: String? = null,
    val md5: String? = null,
) {
    init {
        require(mimeType == null || mimePattern.matches(mimeType)) { "Invalid file MIME type" }
        require(bytes == null || bytes >= 0) { "File byte count must be non-negative" }
        require(sha256 == null || sha256Pattern.matches(sha256)) { "Invalid SHA-256 text" }
        require(md5 == null || md5Pattern.matches(md5)) { "Invalid MD5 text" }
    }

    fun encodeJson(): ByteArray {
        val fields = buildJsonObject {
            put("path", path.value)
            mimeType?.let { put("mimeType", it) }
            bytes?.let { put("bytes", it) }
            sha256?.let { put("sha256", it) }
            md5?.let { put("md5", it) }
        }
        return CanonicalJson.canonicalize(fields.toString().encodeToByteArray())
    }

    companion object {
        private val fieldNames = setOf("path", "mimeType", "bytes", "sha256", "md5")
        private val mimePattern = Regex("[a-z]+/[a-z0-9.+-]+")
        private val sha256Pattern = Regex("[0-9a-f]{64}")
        private val md5Pattern = Regex("[0-9a-f]{32}")

        /** Decodes an individual file-reference record within the caller's UTF-8 byte limit. */
        fun decodeJson(bytes: ByteArray, maxInputBytes: Int): RecordFileReference {
            val input = CanonicalJson.decodeJsonInput(bytes, maxInputBytes)
            CanonicalJson.validateFlatObject(input)
            val fields = Json.parseToJsonElement(input) as JsonObject
            require(fields.keys.all { it in fieldNames }) { "Unknown file reference field" }
            return RecordFileReference(
                path = RecordRelativePath(fields.requireString("path")),
                mimeType = fields.optionalString("mimeType"),
                bytes = fields["bytes"]?.requireStrictLong(),
                sha256 = fields.optionalString("sha256"),
                md5 = fields.optionalString("md5"),
            )
        }
    }
}
