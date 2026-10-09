import Foundation

public struct UnitDisplay: Codable, Equatable, Sendable {
    public var value: String
    public var unit: String
    public var converted: Bool
}
public struct GaugeRange: Codable, Equatable, Sendable {
    public var source: String
    public var minMm: String
    public var maxMm: String
}
public struct GaugeHint: Codable, Equatable, Sendable {
    public var label: String
    public var known: Bool
    public var ranges: [GaugeRange]
}
public enum UnitError: Error, Equatable, Sendable {
    case unknownUnit(String), incompatibleDimensions, invalidDecimal(String), precisionExceeded, invalidPlaces
}

/// Exact decimal inputs and one half-up rounding at the requested output step. Stored quantities
/// are never rewritten: a same-unit display returns their text untouched.
public enum Units {
    private struct Definition {
        var dimension: String
        var numerator: Decimal
        var denominator: Decimal
        var step: Decimal
    }
    private static func decimal(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }
    private static let definitions: [String: Definition] = {
        func def(_ dimension: String, _ n: String, _ d: String = "1", _ step: String) -> Definition {
            Definition(dimension: dimension, numerator: decimal(n), denominator: decimal(d), step: decimal(step))
        }
        return [
            "lb": def("tension", "0.45359237", "1", "0.5"), "kg": def("tension", "1", "1", "0.1"),
            "N": def("tension", "1", "9.80665", "1"),
            "mph": def("speed", "0.44704", "1", "1"), "km/h": def("speed", "1000", "3600", "1"),
            "m/s": def("speed", "1", "1", "0.1"),
            "mm": def("length", "1", "1", "0.01"), "cm": def("length", "10", "1", "0.1"),
            "m": def("length", "1000", "1", "0.01"), "in": def("length", "25.4", "1", "0.01"),
            "ft": def("length", "304.8", "1", "0.1"),
            "cm2": def("area", "1", "1", "0.1"), "in2": def("area", "6.4516", "1", "0.1"),
            "g": def("mass", "1", "1", "1"), "oz": def("mass", "28.349523125", "1", "0.1")
        ]
    }()
    private static func definition(_ unit: String) throws -> Definition {
        guard let result = definitions[unit] else { throw UnitError.unknownUnit(unit) }
        return result
    }
    private static func value(_ text: String) throws -> Decimal {
        var normalized = text
        while normalized.hasPrefix("0"), normalized.count > 1, normalized.dropFirst().first != "." { normalized.removeFirst() }
        guard text.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !value.isNaN,
              try CanonicalJSON.canonicalize(Data(normalized.utf8)) == CanonicalJSON.canonicalize(Data(NSDecimalNumber(decimal: value).stringValue.utf8)) else {
            throw UnitError.invalidDecimal(text)
        }
        return value
    }
    private static func multiply(_ a: Decimal, _ b: Decimal) throws -> Decimal {
        var a = a, b = b, result = Decimal()
        guard NSDecimalMultiply(&result, &a, &b, .plain) == .noError else { throw UnitError.precisionExceeded }
        return result
    }
    private static func divide(_ a: Decimal, _ b: Decimal) throws -> Decimal {
        var a = a, b = b, result = Decimal()
        let error = NSDecimalDivide(&result, &a, &b, .plain)
        // A nonterminating rational is retained at Decimal's full precision until the sole display rounding.
        guard error == .noError || error == .lossOfPrecision else { throw UnitError.precisionExceeded }
        return result
    }
    private static func exact(_ text: String, from: String, to: String) throws -> Decimal {
        let a = try definition(from), b = try definition(to)
        guard a.dimension == b.dimension else { throw UnitError.incompatibleDimensions }
        let numerator = try multiply(multiply(value(text), a.numerator), b.denominator)
        let denominator = try multiply(a.denominator, b.numerator)
        return try divide(numerator, denominator)
    }
    private static func rounded(_ value: Decimal, places: Int) -> Decimal {
        var value = value, result = Decimal()
        NSDecimalRound(&result, &value, places, .plain)
        return result
    }
    private static func text(_ value: Decimal) throws -> String {
        String(decoding: try CanonicalJSON.canonicalize(Data(NSDecimalNumber(decimal: value).stringValue.utf8)), as: UTF8.self)
    }
    public static func convert(_ value: String, from: String, to: String, places: Int) throws -> String {
        guard (0...20).contains(places) else { throw UnitError.invalidPlaces }
        var result = try text(rounded(exact(value, from: from, to: to), places: places))
        if places > 0 {
            if !result.contains(".") { result += "." }
            let count = result.split(separator: ".", omittingEmptySubsequences: false).last!.count
            result += String(repeating: "0", count: places - count)
        }
        return result
    }
    public static func display(_ stored: String, unit: String, preferredUnit: String) throws -> UnitDisplay {
        _ = try value(stored)
        _ = try definition(unit)
        _ = try definition(preferredUnit)
        if unit == preferredUnit { return UnitDisplay(value: stored, unit: unit, converted: false) }
        let step = try definition(preferredUnit).step
        let count = try divide(exact(stored, from: unit, to: preferredUnit), step)
        let result = try multiply(rounded(count, places: 0), step)
        return UnitDisplay(value: try text(result), unit: preferredUnit, converted: true)
    }
    public static func gaugeHint(_ label: String) -> GaugeHint {
        let ranges: [String: [(String, String, String)]] = [
            "15": [("tennisCompanion", "1.41", "1.49"), ("tennisWarehouse", "1.35", "1.40")],
            "15L": [("tennisCompanion", "1.33", "1.41")],
            "16": [("tennisCompanion", "1.26", "1.34"), ("tennisWarehouse", "1.25", "1.30")],
            "16L": [("tennisCompanion", "1.22", "1.30")],
            "17": [("tennisCompanion", "1.16", "1.24"), ("tennisWarehouse", "1.20", "1.25")],
            "18": [("tennisCompanion", "1.06", "1.16"), ("tennisWarehouse", "1.15", "1.20")],
            "19": [("tennisCompanion", "0.90", "1.06"), ("tennisWarehouse", "1.10", "1.15")]
        ]
        let values = ranges[label]
        return GaugeHint(label: label, known: values != nil,
                         ranges: (values ?? []).map { GaugeRange(source: $0.0, minMm: $0.1, maxMm: $0.2) })
    }
}
