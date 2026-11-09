package com.islanddevcrew.jovra.core.pct

import kotlin.math.abs

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

/** The shared fixture form preserves the counts and represents an undefined percentage with a dash. */
data class RateRatio(val n: Long, val d: Long) {
    val pct: Int? = Percent.pct(n, d)
    val display: String get() = pct?.let { "$it%" } ?: "—"
}
