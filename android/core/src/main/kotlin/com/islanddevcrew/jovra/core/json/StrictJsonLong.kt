package com.islanddevcrew.jovra.core.json

import kotlinx.serialization.json.JsonElement
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
