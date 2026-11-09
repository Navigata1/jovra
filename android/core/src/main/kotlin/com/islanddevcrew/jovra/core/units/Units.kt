package com.islanddevcrew.jovra.core.units

import java.math.BigDecimal
import java.math.RoundingMode

data class UnitDisplay(val value: String, val unit: String, val converted: Boolean)
data class GaugeRange(val source: String, val minMm: String, val maxMm: String)
data class GaugeHint(val label: String, val known: Boolean, val ranges: List<GaugeRange>)

/** Keep entered values as text and round an exact conversion once at its output boundary. */
object Units {
    private enum class Dimension { TENSION, SPEED, LENGTH, AREA, MASS }

    private data class Definition(
        val dimension: Dimension,
        val numerator: BigDecimal,
        val denominator: BigDecimal,
        val step: BigDecimal,
    )

    private data class ExactConversion(val numerator: BigDecimal, val denominator: BigDecimal)

    private val decimalPattern = Regex("[0-9]+(\\.[0-9]+)?")

    private val definitions = mapOf(
        // Tennis tension labels lb and kg represent lbf and kgf.
        "lb" to definition(Dimension.TENSION, "0.45359237", step = "0.5"),
        "kg" to definition(Dimension.TENSION, "1", step = "0.1"),
        "N" to definition(Dimension.TENSION, "1", "9.80665", "1"),
        "mph" to definition(Dimension.SPEED, "0.44704", step = "1"),
        "km/h" to definition(Dimension.SPEED, "1000", "3600", "1"),
        "m/s" to definition(Dimension.SPEED, "1", step = "0.1"),
        "mm" to definition(Dimension.LENGTH, "1", step = "0.01"),
        "cm" to definition(Dimension.LENGTH, "10", step = "0.1"),
        "m" to definition(Dimension.LENGTH, "1000", step = "0.01"),
        "in" to definition(Dimension.LENGTH, "25.4", step = "0.01"),
        "ft" to definition(Dimension.LENGTH, "304.8", step = "0.1"),
        "cm2" to definition(Dimension.AREA, "1", step = "0.1"),
        "in2" to definition(Dimension.AREA, "6.4516", step = "0.1"),
        "g" to definition(Dimension.MASS, "1", step = "1"),
        "oz" to definition(Dimension.MASS, "28.349523125", step = "0.1"),
    )

    private val gaugeRanges = mapOf(
        "15" to listOf(companionRange("1.41", "1.49"), warehouseRange("1.35", "1.40")),
        "15L" to listOf(companionRange("1.33", "1.41")),
        "16" to listOf(companionRange("1.26", "1.34"), warehouseRange("1.25", "1.30")),
        "16L" to listOf(companionRange("1.22", "1.30")),
        "17" to listOf(companionRange("1.16", "1.24"), warehouseRange("1.20", "1.25")),
        "18" to listOf(companionRange("1.06", "1.16"), warehouseRange("1.15", "1.20")),
        "19" to listOf(companionRange("0.90", "1.06"), warehouseRange("1.10", "1.15")),
    )

    fun convert(value: String, from: String, to: String, places: Int): String {
        require(places in 0..20) { "Expected 0 to 20 decimal places" }
        val exact = exactConversion(parseDecimal(value), definition(from), definition(to))
        return exact.numerator.divide(exact.denominator, places, RoundingMode.HALF_UP).toPlainString()
    }

    fun display(value: String, unit: String, preferredUnit: String): UnitDisplay {
        val parsed = parseDecimal(value)
        val from = definition(unit)
        if (unit == preferredUnit) return UnitDisplay(value, unit, converted = false)

        val to = definition(preferredUnit)
        val exact = exactConversion(parsed, from, to)
        val steps = exact.numerator.divide(exact.denominator * to.step, 0, RoundingMode.HALF_UP)
        val display = (steps * to.step).stripTrailingZeros().toPlainString()
        return UnitDisplay(display, preferredUnit, converted = true)
    }

    fun gaugeHint(label: String): GaugeHint {
        val ranges = gaugeRanges[label]
        return GaugeHint(label, known = ranges != null, ranges = ranges.orEmpty().toList())
    }

    private fun parseDecimal(value: String): BigDecimal {
        require(decimalPattern.matches(value)) { "Expected a non-negative decimal string" }
        return BigDecimal(value)
    }

    private fun definition(unit: String): Definition = requireNotNull(definitions[unit]) { "Unknown unit: $unit" }

    private fun definition(dimension: Dimension, numerator: String, denominator: String = "1", step: String): Definition =
        Definition(dimension, BigDecimal(numerator), BigDecimal(denominator), BigDecimal(step))

    private fun exactConversion(value: BigDecimal, from: Definition, to: Definition): ExactConversion {
        require(from.dimension == to.dimension) { "Cannot convert between incompatible dimensions" }
        return ExactConversion(value * from.numerator * to.denominator, from.denominator * to.numerator)
    }

    private fun companionRange(minMm: String, maxMm: String) = GaugeRange("tennisCompanion", minMm, maxMm)

    private fun warehouseRange(minMm: String, maxMm: String) = GaugeRange("tennisWarehouse", minMm, maxMm)
}
