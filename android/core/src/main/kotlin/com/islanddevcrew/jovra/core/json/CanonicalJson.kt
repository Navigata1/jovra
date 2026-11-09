package com.islanddevcrew.jovra.core.json

import java.math.BigDecimal
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.util.TreeMap
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json

/** Sorted, compact UTF-8 JSON with exact decimal normalization (ADR-0029). */
object CanonicalJson {
    private const val MAX_DEPTH = 512
    private const val MAX_EXPONENT = 10_000
    private const val HEX = "0123456789abcdef"
    private val whitespace = setOf(' ', '\t', '\r', '\n')
    private val numberEnd = whitespace + setOf(',', ']', '}')
    private val numberPattern = Regex("""-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE]([+-]?[0-9]+))?""")

    fun canonicalize(bytes: ByteArray): ByteArray {
        val text = try {
            Charsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(bytes)).toString()
        } catch (error: CharacterCodingException) {
            throw IllegalArgumentException("Malformed UTF-8 JSON", error)
        }
        return Parser(text).canonicalize().encodeToByteArray()
    }

    private class Parser(private val text: String) {
        private var offset = 0

        fun canonicalize(): String = buildString {
            value(depth = 0, output = this)
            skipWhitespace()
            if (offset != text.length) malformed()
        }

        private fun value(depth: Int, output: StringBuilder) {
            require(depth < MAX_DEPTH) { "JSON nesting exceeds $MAX_DEPTH values" }
            skipWhitespace()
            when (text.getOrNull(offset)) {
                '{' -> objectValue(depth + 1, output)
                '[' -> array(depth + 1, output)
                '"' -> output.appendQuoted(string())
                't' -> literal("true", output)
                'f' -> literal("false", output)
                'n' -> literal("null", output)
                null -> malformed()
                else -> number(output)
            }
        }

        private fun objectValue(childDepth: Int, output: StringBuilder) {
            offset++
            output.append('{')
            if (!take('}')) {
                val entries = TreeMap<String, String>(::compareScalars)
                do {
                    val key = string()
                    require(key !in entries) { "Duplicate JSON object key at offset $offset" }
                    if (!take(':')) malformed()
                    entries[key] = buildString { value(childDepth, this) }
                } while (take(','))
                if (!take('}')) malformed()

                for ((index, entry) in entries.entries.withIndex()) {
                    if (index > 0) output.append(',')
                    output.appendQuoted(entry.key)
                    output.append(':').append(entry.value)
                }
            }
            output.append('}')
        }

        private fun array(childDepth: Int, output: StringBuilder) {
            offset++
            output.append('[')
            if (!take(']')) {
                value(childDepth, output)
                while (take(',')) {
                    output.append(',')
                    value(childDepth, output)
                }
                if (!take(']')) malformed()
            }
            output.append(']')
        }

        private fun string(): String {
            if (!take('"')) malformed()
            val start = offset - 1
            while (offset < text.length) {
                when (val character = text[offset++]) {
                    '"' -> {
                        // Decode only this string token. Object decoding must not collapse duplicate keys.
                        val decoded = Json.decodeFromString(String.serializer(), text.substring(start, offset))
                        requireValidScalars(decoded)
                        return decoded
                    }
                    '\\' -> {
                        if (offset >= text.length || text[offset] < ' ') malformed()
                        offset++
                    }
                    else -> if (character < ' ') malformed()
                }
            }
            malformed()
        }

        private fun literal(expected: String, output: StringBuilder) {
            if (!text.startsWith(expected, offset)) malformed()
            offset += expected.length
            output.append(expected)
        }

        private fun number(output: StringBuilder) {
            val start = offset
            while (offset < text.length && text[offset] !in numberEnd) offset++
            val token = text.substring(start, offset)
            val match = numberPattern.matchEntire(token) ?: malformed()
            val exponent = match.groups[1]?.value
            if (exponent != null) {
                val amount = exponent.toIntOrNull()
                require(amount != null && amount in -MAX_EXPONENT..MAX_EXPONENT) { "JSON exponent exceeds $MAX_EXPONENT" }
            }
            output.append(BigDecimal(token).stripTrailingZeros().toPlainString())
        }

        private fun take(character: Char): Boolean {
            skipWhitespace()
            if (text.getOrNull(offset) != character) return false
            offset++
            return true
        }

        private fun skipWhitespace() {
            while (offset < text.length && text[offset] in whitespace) offset++
        }

        private fun malformed(): Nothing = throw IllegalArgumentException("Malformed JSON at offset $offset")
    }

    private fun requireValidScalars(text: String) {
        var index = 0
        while (index < text.length) {
            val character = text[index++]
            if (Character.isHighSurrogate(character)) {
                require(index < text.length && Character.isLowSurrogate(text[index])) { "Unpaired JSON surrogate" }
                index++
            } else {
                require(!Character.isLowSurrogate(character)) { "Unpaired JSON surrogate" }
            }
        }
    }

    // UTF-16 compares supplementary scalars before some BMP scalars. Canonical ordering compares scalar values.
    private fun compareScalars(left: String, right: String): Int {
        var index = 0
        val sharedLength = minOf(left.length, right.length)
        while (index < sharedLength) {
            val leftScalar = left.codePointAt(index)
            val rightScalar = right.codePointAt(index)
            if (leftScalar != rightScalar) return leftScalar.compareTo(rightScalar)
            index += Character.charCount(leftScalar)
        }
        return left.length.compareTo(right.length)
    }

    private fun StringBuilder.appendQuoted(value: String) {
        append('"')
        for (character in value) {
            when (character) {
                '"' -> append("\\\"")
                '\\' -> append("\\\\")
                '\b' -> append("\\b")
                '\u000c' -> append("\\f")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> {
                    if (character < ' ') {
                        append("\\u00")
                        append(HEX[character.code / 16])
                        append(HEX[character.code % 16])
                    } else {
                        append(character)
                    }
                }
            }
        }
        append('"')
    }
}
