package com.islanddevcrew.jovra.core.json

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
    private val numberPattern = Regex("""-?(0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?""")

    data class Limits(val maxInputBytes: Int, val maxOutputBytes: Int) {
        init {
            require(maxInputBytes >= 0 && maxOutputBytes >= 0) { "JSON byte limits must be non-negative" }
        }
    }

    enum class Limit { INPUT, OUTPUT }

    class LimitExceeded(val limit: Limit, val maxBytes: Int) :
        IllegalArgumentException("Canonical JSON $limit exceeds $maxBytes bytes")

    /** Controlled input path without a caller-defined aggregate cap. */
    fun canonicalize(bytes: ByteArray): ByteArray = canonicalize(decodeJsonInput(bytes, Int.MAX_VALUE), Int.MAX_VALUE)

    /**
     * Bounds supplied bytes and canonical output. Callers reading external streams must separately
     * bound their read before creating the input byte array.
     */
    fun canonicalize(bytes: ByteArray, limits: Limits): ByteArray =
        canonicalize(decodeJsonInput(bytes, limits.maxInputBytes), limits.maxOutputBytes)

    internal fun decodeJsonInput(bytes: ByteArray, maxInputBytes: Int): String {
        require(maxInputBytes >= 0) { "JSON input limit must be non-negative" }
        if (bytes.size > maxInputBytes) throw LimitExceeded(Limit.INPUT, maxInputBytes)
        return try {
            Charsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(bytes)).toString()
        } catch (error: CharacterCodingException) {
            throw IllegalArgumentException("Malformed UTF-8 JSON", error)
        }
    }

    // Reuse the strict grammar before a typed decoder reads the original scalar spellings.
    internal fun validateFlatObject(text: String) {
        val value = Parser(text, OutputBudget(Int.MAX_VALUE)).parse()
        require(value is ObjectValue && value.entries.values.none { it is ObjectValue || it is ArrayValue }) {
            "Expected a JSON object with scalar fields"
        }
    }

    internal fun validateObject(text: String) {
        require(Parser(text, OutputBudget(Int.MAX_VALUE)).parse() is ObjectValue) { "Expected a JSON object" }
    }

    private fun canonicalize(text: String, maxOutputBytes: Int): ByteArray {
        val budget = OutputBudget(maxOutputBytes)
        val value = Parser(text, budget).parse()
        // Parsed values retain only input-sized tokens. Nothing expands until the exact size is admitted.
        val output = ByteBuffer.allocate(budget.bytes)
        value.writeTo(output)
        check(!output.hasRemaining()) { "Canonical JSON byte count drifted" }
        return output.array()
    }

    private class OutputBudget(private val maximum: Int) {
        var bytes = 0
            private set

        fun charge(count: Long) {
            if (count > maximum - bytes) throw LimitExceeded(Limit.OUTPUT, maximum)
            bytes += count.toInt()
        }
    }

    private class Parser(private val text: String, private val budget: OutputBudget) {
        private var offset = 0

        fun parse(): Value {
            val result = value(depth = 0)
            skipWhitespace()
            if (offset != text.length) malformed()
            return result
        }

        private fun value(depth: Int): Value {
            require(depth < MAX_DEPTH) { "JSON nesting exceeds $MAX_DEPTH values" }
            skipWhitespace()
            return when (text.getOrNull(offset)) {
                '{' -> objectValue(depth + 1)
                '[' -> array(depth + 1)
                '"' -> string().let {
                    budget.charge(quotedLength(it))
                    StringValue(it)
                }
                't' -> literal(Literal.TRUE)
                'f' -> literal(Literal.FALSE)
                'n' -> literal(Literal.NULL)
                null -> malformed()
                else -> number()
            }
        }

        private fun objectValue(childDepth: Int): Value {
            offset++
            budget.charge(2)
            val entries = TreeMap<String, Value>(::compareScalars)
            if (take('}')) return ObjectValue(entries)
            while (true) {
                val key = string()
                require(key !in entries) { "Duplicate JSON object key at offset $offset" }
                if (!take(':')) malformed()
                budget.charge(quotedLength(key) + 1)
                entries[key] = value(childDepth)
                if (take('}')) return ObjectValue(entries)
                if (!take(',')) malformed()
                budget.charge(1)
            }
        }

        private fun array(childDepth: Int): Value {
            offset++
            budget.charge(2)
            val items = mutableListOf<Value>()
            if (!take(']')) {
                items.add(value(childDepth))
                while (take(',')) {
                    budget.charge(1)
                    items.add(value(childDepth))
                }
                if (!take(']')) malformed()
            }
            return ArrayValue(items)
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

        private fun literal(literal: Literal): Value {
            if (!text.startsWith(literal.text, offset)) malformed()
            offset += literal.text.length
            budget.charge(literal.text.length.toLong())
            return literal
        }

        private fun number(): Value {
            val start = offset
            while (offset < text.length && text[offset] !in numberEnd) offset++
            val token = text.substring(start, offset)
            val match = numberPattern.matchEntire(token) ?: malformed()
            val exponent = match.groups[3]?.value?.let {
                val amount = it.toIntOrNull()
                require(amount != null && amount in -MAX_EXPONENT..MAX_EXPONENT) { "JSON exponent exceeds $MAX_EXPONENT" }
                amount
            } ?: 0

            val digits = Digits(match.groupValues[1], match.groupValues[2])
            val first = (0 until digits.count).firstOrNull { digits[it] != '0' }
            if (first == null) {
                budget.charge(1)
                return Literal.ZERO
            }
            val last = (digits.count - 1 downTo first).first { digits[it] != '0' }
            // Position of the decimal point relative to the first significant digit.
            val point = digits.whole.length.toLong() + exponent - first
            val number = NumberValue(digits, first..last, point, token.startsWith('-'))
            budget.charge(number.length)
            return number
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

    private interface Value {
        fun writeTo(output: ByteBuffer)
    }

    private enum class Literal(val text: String) : Value {
        TRUE("true"), FALSE("false"), NULL("null"), ZERO("0");

        override fun writeTo(output: ByteBuffer) {
            for (character in text) output.putAscii(character)
        }
    }

    private class StringValue(private val text: String) : Value {
        override fun writeTo(output: ByteBuffer) = forEachQuotedScalar(text) { output.putScalar(it) }
    }

    private class ObjectValue(val entries: Map<String, Value>) : Value {
        override fun writeTo(output: ByteBuffer) {
            output.putAscii('{')
            for ((index, entry) in entries.entries.withIndex()) {
                if (index > 0) output.putAscii(',')
                forEachQuotedScalar(entry.key) { output.putScalar(it) }
                output.putAscii(':')
                entry.value.writeTo(output)
            }
            output.putAscii('}')
        }
    }

    private class ArrayValue(private val items: List<Value>) : Value {
        override fun writeTo(output: ByteBuffer) {
            output.putAscii('[')
            for ((index, item) in items.withIndex()) {
                if (index > 0) output.putAscii(',')
                item.writeTo(output)
            }
            output.putAscii(']')
        }
    }

    private class Digits(val whole: String, private val fraction: String) {
        val count = whole.length + fraction.length

        operator fun get(index: Int): Char =
            if (index < whole.length) whole[index] else fraction[index - whole.length]
    }

    private class NumberValue(
        private val digits: Digits,
        private val significant: IntRange,
        private val point: Long,
        private val negative: Boolean,
    ) : Value {
        private val count = significant.last - significant.first + 1
        val length: Long = (if (negative) 1L else 0L) + when {
            point <= 0 -> 2L - point + count
            point >= count -> point
            else -> count + 1L
        }

        override fun writeTo(output: ByteBuffer) {
            if (negative) output.putAscii('-')
            if (point <= 0) {
                output.putAscii('0')
                output.putAscii('.')
                repeat((-point).toInt()) { output.putAscii('0') }
            }
            for (index in significant) {
                if (point > 0 && (index - significant.first).toLong() == point) output.putAscii('.')
                output.putAscii(digits[index])
            }
            if (point > count) repeat((point - count).toInt()) { output.putAscii('0') }
        }
    }

    internal fun requireValidScalars(text: String) {
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

    private fun quotedLength(text: String): Long {
        var length = 0L
        forEachQuotedScalar(text) { length += scalarSize(it) }
        return length
    }

    private inline fun forEachQuotedScalar(text: String, emit: (Int) -> Unit) {
        emit('"'.code)
        var index = 0
        while (index < text.length) {
            val scalar = text.codePointAt(index)
            index += Character.charCount(scalar)
            val escaped = when (scalar) {
                '"'.code -> '"'
                '\\'.code -> '\\'
                '\b'.code -> 'b'
                '\u000c'.code -> 'f'
                '\n'.code -> 'n'
                '\r'.code -> 'r'
                '\t'.code -> 't'
                else -> null
            }
            if (escaped != null) {
                emit('\\'.code)
                emit(escaped.code)
            } else if (scalar < ' '.code) {
                emit('\\'.code)
                emit('u'.code)
                emit('0'.code)
                emit('0'.code)
                emit(HEX[scalar / 16].code)
                emit(HEX[scalar % 16].code)
            } else {
                emit(scalar)
            }
        }
        emit('"'.code)
    }

    private fun scalarSize(value: Int): Int = when {
        value < 0x80 -> 1
        value < 0x800 -> 2
        value < 0x10000 -> 3
        else -> 4
    }

    private fun ByteBuffer.putScalar(value: Int) {
        when (scalarSize(value)) {
            1 -> put(value.toByte())
            2 -> {
                put((0xc0 or (value shr 6)).toByte())
                putContinuation(value)
            }
            3 -> {
                put((0xe0 or (value shr 12)).toByte())
                putContinuation(value shr 6)
                putContinuation(value)
            }
            4 -> {
                put((0xf0 or (value shr 18)).toByte())
                putContinuation(value shr 12)
                putContinuation(value shr 6)
                putContinuation(value)
            }
        }
    }

    private fun ByteBuffer.putContinuation(value: Int) {
        put((0x80 or (value and 0x3f)).toByte())
    }

    private fun ByteBuffer.putAscii(character: Char) {
        put(character.code.toByte())
    }
}
