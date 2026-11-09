package com.islanddevcrew.jovra.core.json

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

private val integer = Regex("-?(0|[1-9][0-9]*)")

/** Read the original token before canonical number normalization can erase its lexical form. */
internal fun JsonElement?.requireStrictLong(): Long {
    val scalar = this as? JsonPrimitive
    require(scalar != null && !scalar.isString && integer.matches(scalar.content)) {
        "Expected a JSON integer token"
    }
    return requireNotNull(scalar.content.toLongOrNull()) { "JSON integer exceeds signed 64-bit range" }
}

internal fun JsonObject.requireString(name: String): String {
    val token = this[name] as? JsonPrimitive
    require(token != null && token.isString) { "Expected a JSON string field: $name" }
    return token.content
}

internal fun JsonObject.optionalString(name: String): String? =
    if (name in this) requireString(name) else null
